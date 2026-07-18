# synthetic patches mimicking dft_transition_vectors() output schema:
# two 1-ha squares in a projected CRS, 200 m apart
attribute_test_patches <- function() {
  sq <- function(x0) {
    sf::st_polygon(list(rbind(
      c(x0, 0), c(x0 + 100, 0), c(x0 + 100, 100), c(x0, 100), c(x0, 0)
    )))
  }
  sf::st_sf(
    patch_id = 1:2,
    transition = c("Trees -> Rangeland", "Trees -> Crops"),
    area_ha = c(1, 1),
    geometry = sf::st_sfc(sq(0), sq(300), crs = "EPSG:32609")
  )
}

# overlay straddling patch 1 unevenly: poly with fire_year 2018 covers its
# left 30 m, poly with fire_year 2022 its right 70 m. Patch 2 is outside both.
# `ignore_me` exists to prove only `cols` are carried over.
attribute_test_overlay <- function() {
  rect <- function(x0, x1) {
    sf::st_polygon(list(rbind(
      c(x0, -10), c(x1, -10), c(x1, 110), c(x0, 110), c(x0, -10)
    )))
  }
  sf::st_sf(
    fire_year = c(2018, 2022),
    cause = c("fire", "harvest"),
    ignore_me = c("x", "y"),
    geometry = sf::st_sfc(rect(-10, 30), rect(30, 150), crs = "EPSG:32609")
  )
}

test_that("attributes patches from the bundled-raster fixture chain", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  patches <- dft_transition_vectors(result$raster, changes_only = TRUE)

  overlay <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"), quiet = TRUE
  )
  overlay$fire_year <- 2018

  out <- dft_transition_attribute(patches, overlay, cols = "fire_year",
                                  match_mode = "largest")

  expect_s3_class(out, "sf")
  expect_equal(nrow(out), nrow(patches))
  expect_true(all(c("patch_id", "transition", "area_ha", "fire_year") %in%
                    names(out)))
  # AOI covers the raster, so every patch is attributed
  expect_false(any(is.na(out$fire_year)))
})

test_that("cols are appended, patch columns preserved, NA where no overlap", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()

  out <- dft_transition_attribute(patches, overlay,
                                  cols = c("fire_year", "cause"),
                                  match_mode = "largest")

  expect_s3_class(out, "sf")
  expect_equal(out$patch_id, patches$patch_id)
  expect_equal(out$transition, patches$transition)
  expect_equal(out$area_ha, patches$area_ha)
  expect_true(all(c("fire_year", "cause") %in% names(out)))
  # only requested cols carried over
  expect_false("ignore_me" %in% names(out))
  # patch 2 touches no overlay feature
  expect_true(is.na(out$fire_year[out$patch_id == 2]))
  expect_true(is.na(out$cause[out$patch_id == 2]))
})

test_that("match_mode = 'largest' assigns straddling patch by greatest overlap", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()

  out <- dft_transition_attribute(patches, overlay, cols = "fire_year",
                                  match_mode = "largest")

  # one row per patch, no duplicates
  expect_equal(nrow(out), nrow(patches))
  expect_equal(sort(out$patch_id), patches$patch_id)
  # patch 1 straddles 2018 (30 m) and 2022 (70 m) -> larger overlap wins
  expect_equal(out$fire_year[out$patch_id == 1], 2022)
})

test_that("match_mode = 'all' duplicates a straddling patch per match", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()

  out <- dft_transition_attribute(patches, overlay, cols = "fire_year",
                                  match_mode = "all")

  # patch 1 matches both overlay polys, patch 2 gets one NA row
  expect_equal(nrow(out), 3L)
  expect_equal(sum(out$patch_id == 1), 2L)
  expect_setequal(out$fire_year[out$patch_id == 1], c(2018, 2022))
  expect_true(is.na(out$fire_year[out$patch_id == 2]))
})

test_that("temporal filter is inclusive on both interval bounds", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()

  # inclusive: both 2018 and 2022 kept
  out_all <- dft_transition_attribute(patches, overlay, cols = "fire_year",
                                      match_mode = "all",
                                      year_col = "fire_year",
                                      interval = c(2018, 2022))
  expect_setequal(out_all$fire_year[out_all$patch_id == 1], c(2018, 2022))

  # only the 2022 feature survives the filter
  out_22 <- dft_transition_attribute(patches, overlay, cols = "fire_year",
                                     match_mode = "largest",
                                     year_col = "fire_year",
                                     interval = c(2022, 2023))
  expect_equal(out_22$fire_year[out_22$patch_id == 1], 2022)

  # no feature in interval -> all-NA cols, nrow preserved
  out_none <- dft_transition_attribute(patches, overlay,
                                       cols = c("fire_year", "cause"),
                                       match_mode = "largest",
                                       year_col = "fire_year",
                                       interval = c(2019, 2021))
  expect_equal(nrow(out_none), nrow(patches))
  expect_true(all(is.na(out_none$fire_year)))
  expect_true(all(is.na(out_none$cause)))
  expect_type(out_none$fire_year, "double")
  expect_type(out_none$cause, "character")
})

test_that("overlay features with NA year are dropped by the temporal filter", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()
  overlay$fire_year[2] <- NA_real_

  out <- dft_transition_attribute(patches, overlay, cols = "cause",
                                  match_mode = "largest",
                                  year_col = "fire_year",
                                  interval = c(2000, 2030))
  # only the 2018 feature remains -> patch 1 attributed to it
  expect_equal(out$cause[out$patch_id == 1], "fire")
})

test_that("overlay in a different CRS is transformed silently", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()
  overlay_4326 <- sf::st_transform(overlay, "EPSG:4326")

  out_proj <- dft_transition_attribute(patches, overlay, cols = "fire_year",
                                       match_mode = "largest")
  out_4326 <- dft_transition_attribute(patches, overlay_4326,
                                       cols = "fire_year",
                                       match_mode = "largest")

  expect_equal(out_4326$fire_year, out_proj$fire_year)
  expect_equal(sf::st_crs(out_4326), sf::st_crs(patches))
})

test_that("custom predicate is honoured", {
  patches <- attribute_test_patches()
  # one poly fully containing patch 1; patch 1 also *intersects* a second poly
  # that it is not within, so st_within and st_intersects must differ
  contains_p1 <- sf::st_polygon(list(rbind(
    c(-10, -10), c(110, -10), c(110, 110), c(-10, 110), c(-10, -10)
  )))
  clips_p1 <- sf::st_polygon(list(rbind(
    c(90, -10), c(150, -10), c(150, 110), c(90, 110), c(90, -10)
  )))
  overlay <- sf::st_sf(
    cause = c("containing", "clipping"),
    geometry = sf::st_sfc(contains_p1, clips_p1, crs = "EPSG:32609")
  )

  out <- dft_transition_attribute(patches, overlay, cols = "cause",
                                  predicate = sf::st_within,
                                  match_mode = "all")

  expect_equal(out$cause[out$patch_id == 1], "containing")
  expect_true(is.na(out$cause[out$patch_id == 2]))
})

test_that("match_mode defaults to 'all'", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()

  # no match_mode passed -> documented default is "all"
  out <- dft_transition_attribute(patches, overlay, cols = "fire_year")

  # "all" duplicates the straddling patch 1 (two overlay matches) -> 3 rows
  expect_equal(nrow(out), 3L)
  expect_equal(sum(out$patch_id == 1), 2L)
})

test_that("invalid overlay geometry is repaired (st_make_valid), not fatal", {
  patches <- attribute_test_patches()

  # self-intersecting bow-tie spanning patch 1 -- invalid until st_make_valid.
  # This is the real-world case the make_valid call exists for (BC fire /
  # cutblock perimeters routinely fail GEOS validity). "largest" runs
  # st_intersection internally, so an unrepaired input would throw here.
  bowtie <- sf::st_polygon(list(rbind(
    c(-10, -10), c(110, 110), c(110, -10), c(-10, 110), c(-10, -10)
  )))
  overlay <- sf::st_sf(
    fire_year = 2020,
    geometry = sf::st_sfc(bowtie, crs = "EPSG:32609")
  )
  expect_false(all(sf::st_is_valid(overlay)))  # fixture really is invalid

  out <- dft_transition_attribute(patches, overlay, cols = "fire_year",
                                  match_mode = "largest")

  expect_equal(nrow(out), nrow(patches))
  expect_equal(out$fire_year[out$patch_id == 1], 2020)
})

test_that("0-row patches return a 0-row sf with correctly-typed cols", {
  patches <- attribute_test_patches()[0, ]
  overlay <- attribute_test_overlay()

  out <- dft_transition_attribute(patches, overlay,
                                  cols = c("fire_year", "cause"))

  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
  expect_true(all(c("fire_year", "cause") %in% names(out)))
  expect_type(out$fire_year, "double")
  expect_type(out$cause, "character")
})

test_that("validation errors are raised with informative messages", {
  patches <- attribute_test_patches()
  overlay <- attribute_test_overlay()

  expect_error(dft_transition_attribute(data.frame(x = 1), overlay,
                                        cols = "fire_year"),
               "sf")
  expect_error(dft_transition_attribute(patches, data.frame(x = 1),
                                        cols = "fire_year"),
               "sf")
  expect_error(dft_transition_attribute(patches, overlay, cols = character(0)),
               "cols")
  expect_error(dft_transition_attribute(patches, overlay, cols = "nope"),
               "nope")
  # collision with an existing patches column
  overlay_clash <- overlay
  overlay_clash$transition <- "boom"
  expect_error(dft_transition_attribute(patches, overlay_clash,
                                        cols = "transition"),
               "transition")
  # predicate must be a function
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        predicate = "st_intersects"),
               "predicate")
  # year_col and interval must come together
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        year_col = "fire_year"),
               "interval")
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        interval = c(2018, 2022)),
               "year_col")
  # interval shape
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        year_col = "fire_year",
                                        interval = 2018),
               "interval")
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        year_col = "fire_year",
                                        interval = c("a", "b")),
               "interval")
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        year_col = "fire_year",
                                        interval = c(2022, 2018)),
               "interval")
  # year_col must exist and be numeric
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        year_col = "nope",
                                        interval = c(2018, 2022)),
               "year_col")
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        year_col = "cause",
                                        interval = c(2018, 2022)),
               "numeric")
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        match_mode = "banana"))
  # sf::st_join(largest = TRUE) ignores the join predicate, so a custom
  # predicate with match_mode = "largest" would silently mis-attribute
  expect_error(dft_transition_attribute(patches, overlay, cols = "fire_year",
                                        predicate = sf::st_within,
                                        match_mode = "largest"),
               "largest")
  # cols naming the overlay geometry column (when named differently from the
  # patches geometry) must be rejected, not silently dropped by st_join
  overlay_geom <- overlay
  names(overlay_geom)[names(overlay_geom) == "geometry"] <- "geom"
  sf::st_geometry(overlay_geom) <- "geom"
  expect_error(dft_transition_attribute(patches, overlay_geom,
                                        cols = c("fire_year", "geom")),
               "geom")
})

test_that("dft_transition_vectors returns sf with expected columns", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  patches <- dft_transition_vectors(result$raster)

  expect_s3_class(patches, "sf")
  expect_true(all(c("patch_id", "transition", "area_ha") %in% names(patches)))
  expect_true(nrow(patches) > 0)
})

test_that("total area matches raster summary", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  patches <- dft_transition_vectors(result$raster)

  expect_equal(sum(patches$area_ha), sum(result$summary$area), tolerance = 0.1)
})

test_that("each patch has a valid transition label", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  patches <- dft_transition_vectors(result$raster)
  lvls <- terra::cats(result$raster)[[1]]

  expect_true(all(patches$transition %in% lvls$transition))
})

test_that("patch_ids are unique", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  patches <- dft_transition_vectors(result$raster)

  expect_equal(length(unique(patches$patch_id)), nrow(patches))
})

test_that("patch_area_min filters small patches", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  all_patches <- dft_transition_vectors(result$raster)
  filtered <- dft_transition_vectors(result$raster, patch_area_min = 1000)

  expect_lt(nrow(filtered), nrow(all_patches))
  expect_true(all(as.numeric(sf::st_area(filtered)) >= 1000))
})

test_that("zone attribution adds zone column", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"), quiet = TRUE
  )
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  # Use AOI as a single zone
  aoi$zone_name <- "test_zone"
  patches <- dft_transition_vectors(result$raster, zones = aoi,
                                    zone_col = "zone_name")

  expect_true("zone_name" %in% names(patches))
})

test_that("errors on non-SpatRaster input", {
  expect_error(dft_transition_vectors(data.frame(x = 1)),
               "SpatRaster")
})

test_that("errors on non-factor SpatRaster", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  expect_error(dft_transition_vectors(r), "factor")
})

test_that("errors on geographic CRS", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  r_geo <- terra::project(result$raster, "EPSG:4326", method = "near")

  expect_error(dft_transition_vectors(r_geo), "projected CRS")
})

test_that("errors when zones supplied without zone_col", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"), quiet = TRUE
  )

  expect_error(dft_transition_vectors(result$raster, zones = aoi),
               "zone_col")
})

# builds a small projected factor raster from an integer matrix; codes become
# levels labelled "class_<code>"
transition_test_rast <- function(m) {
  r <- terra::rast(m)
  terra::ext(r) <- c(0, ncol(m) * 10, 0, nrow(m) * 10)
  terra::crs(r) <- "EPSG:32609"
  codes <- sort(unique(as.vector(m)))
  terra::set.cats(
    r, layer = 1,
    value = data.frame(id = codes, transition = paste0("class_", codes))
  )
  r
}

test_that("patch decomposition matches per-class brute-force reference", {
  m <- matrix(NA_integer_, nrow = 60, ncol = 80)
  m[5:7, 5:7] <- 10L    # two class-10 blocks touching only at a corner:
  m[8:10, 8:10] <- 10L  # 8-connectivity must merge them into one patch
  m[5:7, 8:10] <- 20L   # class-20 block edge-adjacent to class 10: must stay separate
  m[20, 20] <- 30L      # crossed diagonals: 30 and 40 each diagonal pairs
  m[21, 21] <- 30L      # crossing each other — each class merges to one patch
  m[20, 21] <- 40L
  m[21, 20] <- 40L
  m[40:42, 40:45] <- 0L # code 0 is a real class, not background
  m[30:36, 60:66] <- 50L      # class-50 ring ...
  m[32:34, 62:64] <- NA_integer_  # ... around a hole
  m[50, 70] <- 20L      # isolated second class-20 patch

  x <- transition_test_rast(m)
  patches <- dft_transition_vectors(x)

  # brute-force reference: per-class binary mask -> patches(directions = 8)
  codes <- sort(unique(as.vector(m)))
  for (code in codes) {
    r_class <- terra::classify(transition_test_rast(m), cbind(code, 1),
                               others = NA)
    p_ref <- terra::patches(r_class, directions = 8)
    ref_cells <- sort(terra::freq(p_ref)$count)

    got <- patches[patches$transition == paste0("class_", code), ]
    got_cells <- sort(round(got$area_ha * 1e4 / 100))  # 10 m cells -> cell counts
    expect_equal(got_cells, ref_cells, label = paste("class", code))
  }

  expect_equal(length(unique(patches$patch_id)), nrow(patches))
  # engineered expectations, independent of the reference implementation
  n_by_class <- table(patches$transition)
  expect_equal(unname(n_by_class[["class_10"]]), 1L)  # diagonal merge
  expect_equal(unname(n_by_class[["class_20"]]), 2L)  # class boundary held
  expect_equal(unname(n_by_class[["class_30"]]), 1L)  # crossed diagonal
  expect_equal(unname(n_by_class[["class_40"]]), 1L)
  expect_equal(unname(n_by_class[["class_0"]]), 1L)   # code 0 not background
})

test_that("all-NA raster returns empty sf with expected columns and CRS", {
  m <- matrix(NA_integer_, nrow = 10, ncol = 10)
  r <- terra::rast(m)
  terra::ext(r) <- c(0, 100, 0, 100)
  terra::crs(r) <- "EPSG:32609"
  terra::set.cats(r, layer = 1,
                  value = data.frame(id = 1L, transition = "class_1"))

  out <- dft_transition_vectors(r)

  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0)
  expect_true(all(c("patch_id", "transition", "area_ha") %in% names(out)))
  expect_equal(sf::st_crs(out), sf::st_crs(r))
})

test_that("fixture decomposition is stable (regression guard)", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  patches <- dft_transition_vectors(result$raster)

  expect_equal(nrow(patches), 185L)
  expect_equal(round(sum(patches$area_ha), 2), 123.11)
  expect_equal(nrow(dft_transition_vectors(result$raster, patch_area_min = 1000)),
               57L)
})

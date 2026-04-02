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

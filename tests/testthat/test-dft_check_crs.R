test_that("dft_check_crs passes for projected CRS", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  # Should not error — test data is UTM (EPSG:32609)
  expect_invisible(dft_check_crs(r, "test_fn"))
})

test_that("dft_check_crs errors for geographic CRS", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r_geo <- terra::project(r, "EPSG:4326", method = "near")

  expect_error(dft_check_crs(r_geo, "test_fn"),
               "projected CRS")
})

test_that("dft_check_crs error message includes function name", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r_geo <- terra::project(r, "EPSG:4326", method = "near")

  expect_error(dft_check_crs(r_geo, "dft_rast_transition"),
               "dft_rast_transition")
})

test_that("dft_check_crs error message suggests reprojecting", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r_geo <- terra::project(r, "EPSG:4326", method = "near")

  expect_error(dft_check_crs(r_geo, "test_fn"),
               "terra::project")
})

test_that("dft_rast_transition errors on geographic CRS input", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  r17_geo <- terra::project(r17, "EPSG:4326", method = "near")
  r20_geo <- terra::project(r20, "EPSG:4326", method = "near")
  classified <- dft_rast_classify(list("2017" = r17_geo, "2020" = r20_geo),
                                  source = "io-lulc")

  expect_error(dft_rast_transition(classified, from = "2017", to = "2020"),
               "projected CRS")
})

test_that("dft_rast_transition errors when only 'to' raster is geographic", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  r20_geo <- terra::project(r20, "EPSG:4326", method = "near")
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20_geo),
                                  source = "io-lulc")

  expect_error(dft_rast_transition(classified, from = "2017", to = "2020"),
               "projected CRS")
})

test_that("dft_rast_summarize errors on geographic CRS input", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r_geo <- terra::project(r, "EPSG:4326", method = "near")
  classified <- dft_rast_classify(r_geo, source = "io-lulc")

  expect_error(dft_rast_summarize(classified, source = "io-lulc"),
               "projected CRS")
})

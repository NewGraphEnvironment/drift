test_that("dft_rast_summarize returns expected columns for single raster", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_summarize(r, source = "io-lulc", unit = "ha")
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("code", "class_name", "color", "n_cells", "area", "pct") %in% names(result)))
  expect_false("year" %in% names(result))
})

test_that("dft_rast_summarize adds year column for list input", {
  files <- c("2017" = "example_2017.tif", "2020" = "example_2020.tif")
  rasters <- lapply(files, function(f) {
    terra::rast(system.file("extdata", f, package = "drift"))
  })
  result <- dft_rast_summarize(rasters, source = "io-lulc")
  expect_true("year" %in% names(result))
  expect_equal(sort(unique(result$year)), c("2017", "2020"))
})

test_that("dft_rast_summarize percentages sum to 100", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_summarize(r, source = "io-lulc")
  expect_equal(sum(result$pct), 100, tolerance = 0.1)
})

test_that("dft_rast_summarize respects unit parameter", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  ha <- dft_rast_summarize(r, source = "io-lulc", unit = "ha")
  km2 <- dft_rast_summarize(r, source = "io-lulc", unit = "km2")
  expect_equal(sum(ha$area) / sum(km2$area), 100, tolerance = 0.01)
})

test_that("dft_rast_summarize stores unit attribute", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_summarize(r, source = "io-lulc", unit = "km2")
  expect_equal(attr(result, "unit"), "km2")
})

test_that("dft_rast_summarize joins class names correctly", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_summarize(r, source = "io-lulc")
  expect_true("Water" %in% result$class_name)
  expect_true("Trees" %in% result$class_name)
  expect_true(all(grepl("^#", result$color)))
})

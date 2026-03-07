test_that("dft_rast_transition returns raster and summary", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  expect_type(result, "list")
  expect_named(result, c("raster", "summary"))
  expect_s4_class(result$raster, "SpatRaster")
  expect_s3_class(result$summary, "tbl_df")
  expect_true(terra::is.factor(result$raster))
})

test_that("summary has expected columns and positive values", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  s <- result$summary

  expect_true(all(c("from_class", "to_class", "n_cells", "area", "pct") %in% names(s)))
  expect_true(all(s$n_cells > 0))
  expect_true(all(s$area > 0))
  expect_true(all(s$pct > 0))
})

test_that("pct sums to 100", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  expect_equal(sum(result$summary$pct), 100, tolerance = 0.1)
})

test_that("from_class filter works", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                from_class = "Trees")

  expect_true(all(result$summary$from_class == "Trees"))
})

test_that("to_class filter works", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                to_class = c("Crops", "Rangeland", "Bare Ground"))

  expect_true(all(result$summary$to_class %in% c("Crops", "Rangeland", "Bare Ground")))
})

test_that("both from_class and to_class filter together", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                from_class = "Trees",
                                to_class = "Rangeland")

  if (nrow(result$summary) > 0) {
    expect_true(all(result$summary$from_class == "Trees"))
    expect_true(all(result$summary$to_class == "Rangeland"))
  }
})

test_that("impossible filter returns empty summary", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                from_class = "NONEXISTENT_CLASS")

  expect_equal(nrow(result$summary), 0)
})

test_that("unit parameter works", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  ha <- dft_rast_transition(classified, from = "2017", to = "2020", unit = "ha")
  km2 <- dft_rast_transition(classified, from = "2017", to = "2020", unit = "km2")

  # ha should be 100x km2
  expect_equal(ha$summary$area[1] / km2$summary$area[1], 100, tolerance = 0.01)
})

test_that("errors on single SpatRaster", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  expect_error(dft_rast_transition(r, from = "2017", to = "2020"),
               "named list")
})

test_that("errors on missing layer name", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  expect_error(dft_rast_transition(classified, from = "2017", to = "2099"),
               "2099")
})

test_that("transition labels use arrow format", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  lvls <- terra::cats(result$raster)[[1]]

  expect_true(all(grepl(" -> ", lvls$transition)))
})

test_that("summary is sorted by n_cells descending", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  s <- result$summary

  if (nrow(s) > 1) {
    expect_true(all(diff(s$n_cells) <= 0))
  }
})

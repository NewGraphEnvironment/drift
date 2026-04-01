test_that("dft_rast_consensus returns factor raster with modal class", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
  classified <- dft_rast_classify(
    list("2017" = r17, "2020" = r20, "2023" = r23), source = "io-lulc"
  )

  cons <- dft_rast_consensus(classified)

  expect_s4_class(cons, "SpatRaster")
  expect_equal(terra::nlyr(cons), 1)
  expect_true(terra::is.factor(cons))
  expect_equal(names(cons), "consensus")
})

test_that("consensus raster has same dimensions as input", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(
    list("2017" = r17, "2020" = r20), source = "io-lulc"
  )

  cons <- dft_rast_consensus(classified)

  expect_equal(terra::nrow(cons), terra::nrow(classified[["2017"]]))
  expect_equal(terra::ncol(cons), terra::ncol(classified[["2017"]]))
})

test_that("confidence layer returned when requested", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
  classified <- dft_rast_classify(
    list("2017" = r17, "2020" = r20, "2023" = r23), source = "io-lulc"
  )

  cons <- dft_rast_consensus(classified, confidence = TRUE)

  expect_equal(terra::nlyr(cons), 2)
  expect_equal(names(cons), c("consensus", "confidence"))
})

test_that("confidence values are between 0 and 1", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
  classified <- dft_rast_classify(
    list("2017" = r17, "2020" = r20, "2023" = r23), source = "io-lulc"
  )

  cons <- dft_rast_consensus(classified, confidence = TRUE)
  conf_vals <- terra::values(cons[["confidence"]])[, 1]
  conf_vals <- conf_vals[!is.na(conf_vals)]

  expect_true(all(conf_vals >= 0 & conf_vals <= 1))
})

test_that("unanimous pixels have confidence = 1", {
  # Create 3 identical rasters — every pixel should have confidence 1.0
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  classified <- dft_rast_classify(list("a" = r, "b" = r, "c" = r), source = "io-lulc")

  cons <- dft_rast_consensus(classified, confidence = TRUE)
  conf_vals <- terra::values(cons[["confidence"]])[, 1]
  conf_vals <- conf_vals[!is.na(conf_vals)]

  expect_true(all(conf_vals == 1))
})

test_that("consensus of identical rasters equals the input", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  classified <- dft_rast_classify(list("a" = r, "b" = r), source = "io-lulc")

  cons <- dft_rast_consensus(classified)
  # Raw values should match
  expect_equal(
    terra::values(cons)[, 1],
    terra::values(classified[["a"]])[, 1]
  )
})

test_that("errors on single SpatRaster", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  expect_error(dft_rast_consensus(r), "named list")
})

test_that("errors on list with fewer than 2 rasters", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  classified <- dft_rast_classify(list("a" = r), source = "io-lulc")
  expect_error(dft_rast_consensus(classified), "at least 2")
})

test_that("consensus works with dft_rast_transition", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
  classified <- dft_rast_classify(
    list("2017" = r17, "2020" = r20, "2023" = r23), source = "io-lulc"
  )

  # Use 2017+2020 as "early", 2023 alone as "late" (just to test integration)
  early <- dft_rast_consensus(classified[c("2017", "2020")])
  late <- classified[["2023"]]

  result <- dft_rast_transition(
    list(early = early, late = late),
    from = "early", to = "late"
  )

  expect_type(result, "list")
  expect_named(result, c("raster", "summary", "removed"))
  expect_true(nrow(result$summary) > 0)
})

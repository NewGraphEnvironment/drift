test_that("dft_rast_classify applies factor levels", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_classify(r, source = "io-lulc")
  expect_true(terra::is.factor(result))
  lvls <- terra::levels(result)[[1]]
  expect_true("class_name" %in% names(lvls))
  expect_true("Trees" %in% lvls$class_name)
})

test_that("dft_rast_classify applies color table", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_classify(r, source = "io-lulc")
  ctab <- terra::coltab(result)
  expect_false(is.null(ctab[[1]]))
})

test_that("dft_rast_classify handles named list", {
  files <- c("2017" = "example_2017.tif", "2020" = "example_2020.tif")
  rasters <- lapply(files, function(f) {
    terra::rast(system.file("extdata", f, package = "drift"))
  })
  result <- dft_rast_classify(rasters, source = "io-lulc")
  expect_type(result, "list")
  expect_named(result, c("2017", "2020"))
  expect_true(terra::is.factor(result[["2017"]]))
  expect_true(terra::is.factor(result[["2020"]]))
})

test_that("dft_rast_classify accepts explicit class_table", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  ct <- dft_class_table("io-lulc")
  result <- dft_rast_classify(r, class_table = ct)
  expect_true(terra::is.factor(result))
})

test_that("remap collapses classes", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_classify(r, source = "io-lulc",
    remap = list(Vegetation = c("Trees", "Rangeland")))
  lvls <- terra::levels(result)[[1]]
  expect_true("Vegetation" %in% lvls$class_name)
  expect_false("Trees" %in% lvls$class_name)
  expect_false("Rangeland" %in% lvls$class_name)
})

test_that("remap preserves unremapped classes", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  result <- dft_rast_classify(r, source = "io-lulc",
    remap = list(Vegetation = c("Trees", "Rangeland")))
  lvls <- terra::levels(result)[[1]]
  expect_true("Water" %in% lvls$class_name)
})

test_that("the caller's raster is not modified (#89)", {
  # set.cats() works in place, so it must only ever reach the copy that
  # `coltab<-` makes. File-backed, in-memory and list-element inputs each hold
  # the caller's own object, so each is checked.
  f <- system.file("extdata", "example_2017.tif", package = "drift")
  unchanged <- function(r, nm) {
    expect_identical(names(r), nm)
    expect_false(terra::is.factor(r))
    expect_false(terra::has.colors(r))
  }
  classified <- function(r) {
    expect_true(terra::is.factor(r))
    expect_identical(names(r), "class_name")
    expect_true(terra::has.colors(r))
  }

  r_file <- terra::rast(f)
  classified(dft_rast_classify(r_file, source = "io-lulc"))
  unchanged(r_file, "data")

  r_mem <- terra::rast(f) * 1L
  expect_true(terra::inMemory(r_mem))
  classified(dft_rast_classify(r_mem, source = "io-lulc"))
  unchanged(r_mem, "data")

  x <- list("2017" = terra::rast(f))
  classified(dft_rast_classify(x, source = "io-lulc")[["2017"]])
  unchanged(x[["2017"]], "data")
})

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

# Factor input (#91). terra::unique() returns a factor's labels, not its
# codes, so present codes must come from the raw values.
ex_2017 <- function() {
  terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
}

test_that("re-classifying a classified raster keeps its levels and colours (#91)", {
  once <- dft_rast_classify(ex_2017() * 1L, source = "io-lulc")
  twice <- dft_rast_classify(once, source = "io-lulc")
  expect_true(terra::is.factor(twice))
  expect_false(is.null(terra::cats(twice)[[1]]))
  expect_identical(terra::cats(twice), terra::cats(once))
  expect_identical(terra::coltab(twice), terra::coltab(once))
})

test_that("a raster carrying its own RAT gets class_table's levels (#91)", {
  r <- ex_2017() * 1L
  codes <- sort(terra::unique(r)[, 1])
  # A published-style RAT: its own labels and a palette that class_table
  # must replace, read back from disk so the input is file-backed.
  terra::set.cats(r, layer = 1,
                  value = data.frame(value = codes, label = paste0("c", codes)))
  terra::coltab(r) <- data.frame(value = codes, col = "#000000")
  f <- tempfile(fileext = ".tif")
  on.exit(unlink(paste0(f, c("", ".aux.xml"))), add = TRUE)
  terra::writeRaster(r, f, datatype = "INT1U")
  rat <- terra::rast(f)
  expect_true(terra::is.factor(rat))

  out <- dft_rast_classify(rat, source = "io-lulc")
  ct <- dft_class_table("io-lulc")
  lv <- terra::cats(out)[[1]]
  expect_equal(sort(lv$id), codes)
  expect_identical(lv$class_name, ct$class_name[match(lv$id, ct$code)])
  ctab <- terra::coltab(out)[[1]]
  expect_equal(sort(ctab$values), codes)
  rgb_expected <- grDevices::col2rgb(ct$color[match(ctab$values, ct$code)])
  expect_equal(unname(rbind(ctab$red, ctab$green, ctab$blue)),
               unname(rgb_expected))

  # the caller's raster still carries its own RAT
  expect_identical(terra::cats(rat)[[1]]$label, paste0("c", codes))
})

test_that("remap on factor input returns levels, matched or not (#91)", {
  once <- dft_rast_classify(ex_2017() * 1L, source = "io-lulc")

  hit <- dft_rast_classify(once, source = "io-lulc",
                           remap = list(Vegetation = c("Trees", "Rangeland")))
  lv <- terra::cats(hit)[[1]]
  expect_true("Vegetation" %in% lv$class_name)
  expect_false("Trees" %in% lv$class_name)

  expect_warning(
    miss <- dft_rast_classify(once, source = "io-lulc",
                              remap = list(Nothing = "Not A Class")),
    "No matching classes"
  )
  expect_identical(terra::cats(miss), terra::cats(once))
  expect_true(terra::has.colors(miss))
})

test_that("the caller's factor raster is not modified (#91)", {
  # A guard, not a reproduction: the factor path adds strip_copy(), which
  # calls the in-place set.cats(), so this pins that it reaches only a copy.
  once <- dft_rast_classify(ex_2017() * 1L, source = "io-lulc")
  cats_before <- terra::cats(once)
  col_before <- terra::coltab(once)
  # a class_table with different names and colours, so any leak shows
  ct <- dft_class_table("io-lulc")
  ct$class_name <- toupper(ct$class_name)
  ct$color <- "#123456"
  out <- dft_rast_classify(once, class_table = ct)
  expect_true("TREES" %in% terra::cats(out)[[1]]$class_name)
  expect_identical(terra::cats(once), cats_before)
  expect_identical(terra::coltab(once), col_before)
})

test_that("a factor whose active category is not the first reads codes (#91)", {
  r <- ex_2017() * 1L
  codes <- sort(terra::unique(r)[, 1])
  terra::set.cats(r, layer = 1, value = data.frame(
    value = codes, first = paste0("a", codes), second = paste0("b", codes)
  ))
  terra::activeCat(r) <- 2
  expect_identical(terra::unique(r)[, 1], paste0("b", codes))

  out <- dft_rast_classify(r, source = "io-lulc")
  expect_equal(sort(terra::cats(out)[[1]]$id), codes)
  expect_true(terra::has.colors(out))
  expect_identical(terra::activeCat(r), 2L)
})

test_that("a multi-layer stack classifies layer 1, as before (#91)", {
  # is.factor() is per layer; the factor check must not error on a stack.
  once <- dft_rast_classify(ex_2017() * 1L, source = "io-lulc")
  for (s in list(c(ex_2017() * 1L, ex_2017() * 1L), c(once, ex_2017() * 1L))) {
    out <- dft_rast_classify(s, source = "io-lulc")
    expect_identical(terra::nlyr(out), 2)
    expect_identical(terra::cats(out)[[1]], terra::cats(once)[[1]])
  }
})

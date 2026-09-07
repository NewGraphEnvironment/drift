years <- 2017:2023
cases <- break_series_cases()
x_cases <- break_series_list(cases, years)
res_cases <- dft_rast_break_class(x_cases, class_table = artifact_class_table())

# the same rule applied in R, with no terra::app() between it and the answer --
# so a chunk written across the wrong axis shows up as a difference
reference_category <- function(res) {
  ev <- terra::values(res$breaks)
  tr <- terra::values(res$raster)[, 1]
  break_category_code(ev[, "n_flips"],
                      pmin(ev[, "n_before"], ev[, "n_after"]),
                      tr %/% 1000L != tr %% 1000L)
}

test_that("return shape: two named layers, category a factor with ids 0:4", {
  out <- dft_rast_break_category(res_cases)
  expect_s4_class(out, "SpatRaster")
  expect_equal(terra::nlyr(out), 2)
  expect_identical(names(out), c("category", "strength"))
  expect_true(terra::is.factor(out[["category"]]))
  expect_false(terra::is.factor(out[["strength"]]))
  lv <- terra::cats(out[["category"]])[[1]]
  # ids 0:4 in this order are what inst/cartography/drift_temporal.csv and the
  # temporal-composition article key their colours on
  expect_identical(lv$id, 0:4)
  expect_identical(lv$category, break_category_levels())
})

test_that("widths 1, 2 and 3 all agree with the rule applied in R", {
  # terra::app() checks ncol(result) == ntest before nrow(result) == ntest, so a
  # TWO-column return on a TWO-column raster is read as transposed and written
  # across layers silently. Measured on terra 1.9.34: 1 and 3 are correct, 2 is
  # not. The parent's sweep is widths 4/5/6 and structurally cannot reach this.
  for (w in 1:3) {
    x <- break_series_list(cases[seq_len(w), , drop = FALSE], years)
    res <- dft_rast_break_class(x, class_table = artifact_class_table())
    expect_identical(as.integer(terra::ncol(res$raster)), as.integer(w))  # premise
    out <- dft_rast_break_category(res)
    expect_identical(as.integer(terra::values(out[["category"]])),
                     as.vector(reference_category(res)),
                     info = paste("width", w))
    expect_identical(as.integer(terra::values(out[["strength"]])),
                     as.integer(pmin(terra::values(res$breaks)[, "n_before"],
                                     terra::values(res$breaks)[, "n_after"])),
                     info = paste("width", w))
  }
})

test_that("`filename` refuses to clobber, and `overwrite` is the remedy its error names", {
  f <- withr::local_tempfile(fileext = ".tif")
  a <- dft_rast_break_category(res_cases, filename = f)
  expect_error(dft_rast_break_category(res_cases, filename = f), "exists")
  b <- dft_rast_break_category(res_cases, filename = f, overwrite = TRUE)
  expect_identical(terra::values(a), terra::values(b))
  expect_error(dft_rast_break_category(res_cases, filename = f, overwrite = "yes"),
               "must be TRUE or FALSE")
})

test_that("NA round-trips from the written file as NA, not the INT1U sentinel", {
  f <- withr::local_tempfile(fileext = ".tif")
  out <- dft_rast_break_category(res_cases, filename = f)
  expect_true(file.exists(f))
  expect_false(any(terra::inMemory(out)))
  reread <- terra::rast(f)
  v <- terra::values(reread)
  expect_true(any(is.na(v[, 1])))                  # the all-NA and na_year cases
  expect_false(any(v[, 1] == 255, na.rm = TRUE))   # 255 is INT1U's nodata value
  expect_identical(as.integer(v[, 1]), as.vector(reference_category(res_cases)))
})

test_that("pixel grain and summary grain are the same rule", {
  out <- dft_rast_break_category(res_cases)
  fr <- terra::freq(out[["category"]])
  pixel <- stats::setNames(as.integer(fr$count), as.character(fr$value))
  s <- dft_break_category(res_cases)
  rows <- tapply(s$n_cells, as.character(s$category), sum)
  rows <- rows[!is.na(rows)]
  expect_identical(sort(names(pixel)), sort(names(rows)))
  expect_identical(pixel[sort(names(pixel))], as.integer(rows[sort(names(rows))]),
                   ignore_attr = TRUE)
})

test_that("bundled seven-year series: the split, at pixel grain", {
  years7 <- 2017:2023
  x <- lapply(years7, function(yr) {
    terra::rast(system.file("extdata", paste0("example_", yr, ".tif"), package = "drift"))
  })
  names(x) <- years7
  res <- dft_rast_break_class(dft_rast_classify(x, source = "io-lulc"))
  fr <- terra::freq(dft_rast_break_category(res)[["category"]])
  n <- stats::setNames(as.integer(fr$count), as.character(fr$value))
  expect_equal(as.vector(n[c("break_sustained", "break_endpoint", "unsettled",
                             "stable_flicker")]),
               c(1098L, 1040L, 1265L, 2791L))
  changed <- sum(n[c("break_sustained", "break_endpoint", "unsettled")])
  expect_equal(changed, 3403L)
})

test_that("at pixel grain too, the flicker split is BY endpoint equality", {
  out <- dft_rast_break_category(res_cases)
  cv <- terra::values(out[["category"]])[, 1]
  tr <- terra::values(res_cases$raster)[, 1]
  differs <- tr %/% 1000L != tr %% 1000L
  lv <- break_category_levels()
  uns <- which(cv == match("unsettled", lv) - 1L)
  stf <- which(cv == match("stable_flicker", lv) - 1L)
  expect_gt(length(uns), 0L)                    # premise: both populations present
  expect_gt(length(stf), 0L)
  expect_true(all(differs[uns]))
  expect_false(any(differs[stf]))
})

test_that("the scan closure refuses a bare vector so terra::app() takes the vectorised path", {
  # app() tries apply(chunk, 1, fun) first -- one R call per cell, 57x slower,
  # values identical. Only refusing a non-matrix forces the fast path, and
  # nothing in the output would show which one ran.
  scan <- break_category_scan()
  expect_error(scan(c(2020, 2, 5, 1, 2003)), "matrix chunks only")
  m <- matrix(c(2020, 2, 5, 1, 2003), nrow = 1)
  expect_equal(dim(scan(m)), c(1L, 2L))
})

test_that("the caller's rasters are not mutated and no intermediates are left behind", {
  before_cats <- terra::cats(res_cases$raster)[[1]]
  before_files <- list.files(tempdir(), pattern = "^dft_break_category_", full.names = TRUE)
  out <- dft_rast_break_category(res_cases)
  expect_identical(terra::cats(res_cases$raster)[[1]], before_cats)
  expect_true(terra::is.factor(res_cases$raster))
  after <- list.files(tempdir(), pattern = "^dft_break_category_", full.names = TRUE)
  # exactly one survivor: the file `out` points at
  survivor <- setdiff(after, before_files)
  expect_length(survivor, 1L)
  expect_gt(file.size(survivor), 0L)
  expect_false(any(terra::inMemory(out)))
  # paste0(character(0), ".aux.xml") would land a stray ".aux.xml" in getwd()
  expect_false(file.exists(".aux.xml"))
})

test_that("the rule travels with the raster and an unsupported one is refused by name", {
  out <- dft_rast_break_category(res_cases)
  tg <- terra::metags(out)
  expect_true("drift_break_rule" %in% tg$name)
  expect_identical(tg$value[tg$name == "drift_break_rule"], "v1")
  expect_error(dft_rast_break_category(res_cases, rule = "v2"),
               'unsupported `rule`: v2\\. Supported: "v1"')
})

test_that("a result saved before $years existed still works, because nothing here reads it", {
  # strength is measured per pixel as pmin(n_before, n_after); only the row-grain
  # function has to recover it from break_year and therefore needs the series.
  # Requiring $years here would refuse a pre-0.16.0 result for no reason.
  old <- res_cases[c("raster", "breaks", "summary")]
  expect_null(old$years)                                   # premise
  expect_identical(as.integer(terra::values(dft_rast_break_category(old)[["category"]])),
                   as.integer(terra::values(dft_rast_break_category(res_cases)[["category"]])))
})

test_that("inputs it cannot scan are named errors", {
  expect_error(dft_rast_break_category(res_cases$summary), "use `dft_break_category\\(\\)`")
  expect_error(dft_rast_break_category(res_cases["raster"]), "carries no `breaks`")
  bad <- res_cases
  bad$breaks <- bad$breaks[[1:3]]
  expect_error(dft_rast_break_category(bad), "must have layers break_year")
  bad2 <- res_cases
  bad2$raster <- terra::aggregate(bad2$raster, 2, fun = "modal")
  expect_error(dft_rast_break_category(bad2), "different grids")
  expect_error(dft_rast_break_category(res_cases, filename = c("a.tif", "b.tif")),
               "single path or NULL")
})

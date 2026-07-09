# ---- guards (run without gdalcubes/bfast) ----------------------------------

test_that("dft_rast_break requires gdalcubes", {
  skip_if(requireNamespace("gdalcubes", quietly = TRUE),
          "gdalcubes is installed, can't test missing-package path")
  expect_error(dft_rast_break(NULL), "gdalcubes")
})

test_that("dft_rast_break requires bfast", {
  skip_if(requireNamespace("bfast", quietly = TRUE),
          "bfast is installed, can't test missing-package path")
  skip_if_not_installed("gdalcubes")
  expect_error(dft_rast_break(NULL), "bfast")
})

# ---- cadence -> frequency (pure) -------------------------------------------

test_that("cadence_frequency maps ISO durations to seasonal frequency", {
  expect_equal(drift:::cadence_frequency("P1M"), 12)
  expect_equal(drift:::cadence_frequency("P3M"), 4)
  expect_equal(drift:::cadence_frequency("P1Y"), 1)
  expect_true(is.na(drift:::cadence_frequency("P16D")))
  expect_true(is.na(drift:::cadence_frequency("garbage")))
})

# ---- .dft_break_pixel degenerate paths (no bfast needed) -------------------

test_that(".dft_break_pixel returns c(NA, NA) on all-NA input", {
  expect_equal(
    drift:::.dft_break_pixel(rep(NA_real_, 24), c(2018, 1), 12, c(2022, 1),
                             "all", 0.01, 6),
    c(NA_real_, NA_real_)
  )
})

test_that(".dft_break_pixel returns c(NA, NA) when fewer than min_obs", {
  v <- c(0.5, 0.6, NA, NA, 0.55, rep(NA_real_, 19))  # 3 non-NA < min_obs 6
  expect_equal(
    drift:::.dft_break_pixel(v, c(2018, 1), 12, c(2022, 1), "all", 0.01, 6),
    c(NA_real_, NA_real_)
  )
})

# ---- reducer is self-contained (worker-safe) -------------------------------

test_that("build_break_reducer yields a callback with no free variables", {
  f <- drift:::build_break_reducer("kndvi", c(2018, 1), 12, c(2022, 1),
                                   "all", 0.01, 6)
  # environment detached to baseenv and all params inlined as literals, so the
  # only globals referenced are base/pkg functions -> safe to serialize to a
  # gdalcubes worker (see findings.md: closures fail in workers)
  expect_identical(environment(f), baseenv())
  globals <- codetools::findGlobals(f, merge = FALSE)$variables
  expect_false("band" %in% globals)
  expect_false("ts_start" %in% globals)
})

# ---- break cache key -------------------------------------------------------

test_that("break_cache_key changes with each reducer parameter", {
  skip_if_not_installed("gdalcubes")
  skip_if_not_installed("bfast")
  cube <- synthetic_break_cube()$cube
  base <- drift:::break_cache_key(cube, "kndvi", "all", c(2022, 1), 12, 0.01, 6)
  expect_match(base, "^[0-9a-f]{12}$")
  expect_false(drift:::break_cache_key(cube, "kndvi", "ROC", c(2022, 1), 12, 0.01, 6) == base)
  expect_false(drift:::break_cache_key(cube, "kndvi", "all", c(2021, 1), 12, 0.01, 6) == base)
  expect_false(drift:::break_cache_key(cube, "kndvi", "all", c(2022, 1), 1, 0.01, 6) == base)
  expect_false(drift:::break_cache_key(cube, "kndvi", "all", c(2022, 1), 12, 0.05, 6) == base)
  expect_false(drift:::break_cache_key(cube, "kndvi", "all", c(2022, 1), 12, 0.01, 8) == base)
})

# ---- bfast-gated per-pixel behavior ----------------------------------------

test_that(".dft_break_pixel detects an injected step drop (negative magnitude)", {
  skip_if_not_installed("bfast")
  tt <- seq_len(72)
  v <- 0.6 + 0.15 * sin(2 * pi * tt / 12)
  v[54:72] <- v[54:72] - 0.3  # step drop at 2022-06 (monitoring period)
  out <- drift:::.dft_break_pixel(v, c(2018, 1), 12, c(2022, 1), "all", 0.01, 6)
  expect_true(is.finite(out[1]))
  expect_gt(out[1], 2022)
  expect_lt(out[1], 2022.9)
  expect_lt(out[2], 0)
})

test_that(".dft_break_pixel returns NA break on a stable series (non-error)", {
  skip_if_not_installed("bfast")
  tt <- seq_len(72)
  v <- 0.6 + 0.15 * sin(2 * pi * tt / 12)
  out <- drift:::.dft_break_pixel(v, c(2018, 1), 12, c(2022, 1), "all", 0.01, 6)
  expect_true(is.na(out[1]))
})

# ---- gdalcubes + bfast integration (synthetic cube, no network) ------------

test_that("dft_rast_break reduces a synthetic cube to a 2-band raster", {
  skip_if_not_installed("gdalcubes")
  skip_if_not_installed("bfast")
  sc <- synthetic_break_cube()
  breaks <- dft_rast_break(sc$cube, start = c(2022, 1),
                           cache_dir = sc$cache_dir)

  expect_s4_class(breaks, "SpatRaster")
  expect_equal(terra::nlyr(breaks), 2)
  expect_equal(names(breaks), c("break_date", "break_mag"))
  expect_equal(terra::crs(breaks, describe = TRUE)$code, "32609")

  bd <- terra::values(breaks[["break_date"]])[, 1]
  bm <- terra::values(breaks[["break_mag"]])[, 1]
  # the engineered drop pixel yields a finite break with negative magnitude;
  # the all-NA pixel yields NA
  expect_true(any(is.finite(bd)))
  expect_true(any(is.na(bd)))
  expect_true(any(is.finite(bd) & bm < 0))

  # second call hits the cache (one break_<key>.nc)
  breaks2 <- dft_rast_break(sc$cube, start = c(2022, 1),
                            cache_dir = sc$cache_dir)
  expect_equal(terra::values(breaks2[["break_date"]])[, 1], bd)
  expect_length(list.files(file.path(sc$cache_dir, "break"),
                           pattern = "^break_.*\\.nc$"), 1)
})

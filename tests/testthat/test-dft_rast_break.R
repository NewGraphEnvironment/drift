# ---- guards ----------------------------------------------------------------

test_that("dft_rast_break requires bfast", {
  skip_if(requireNamespace("bfast", quietly = TRUE),
          "bfast is installed, can't test missing-package path")
  expect_error(dft_rast_break(terra::rast(nrows = 1, ncols = 1)), "bfast")
})

test_that("dft_rast_break errors on non-SpatRaster input", {
  skip_if_not_installed("bfast")
  expect_error(dft_rast_break(list()), "SpatRaster")
})

test_that("dft_rast_break errors when layers lack times", {
  skip_if_not_installed("bfast")
  r <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3)
  terra::values(r) <- 1
  expect_error(dft_rast_break(r), "time")
})

# ---- cadence -> frequency (pure) -------------------------------------------

test_that("cadence_frequency maps layer times to seasonal frequency", {
  monthly   <- seq(as.Date("2020-01-01"), by = "month", length.out = 12)
  quarterly <- seq(as.Date("2020-01-01"), by = "3 months", length.out = 8)
  annual    <- seq(as.Date("2018-01-01"), by = "year", length.out = 5)
  expect_equal(drift:::cadence_frequency(monthly), 12)
  expect_equal(drift:::cadence_frequency(quarterly), 4)
  expect_equal(drift:::cadence_frequency(annual), 1)
  expect_true(is.na(drift:::cadence_frequency(as.Date("2020-01-01"))))  # length 1
})

# ---- .dft_break_pixel degenerate paths (no bfast needed) -------------------

test_that(".dft_break_pixel returns c(NA, NA) on all-NA input", {
  expect_equal(
    drift:::.dft_break_pixel(rep(NA_real_, 24), c(2018, 1), 12, c(2022, 1),
                             "all", 3, 0.01, 6),
    c(NA_real_, NA_real_)
  )
})

test_that(".dft_break_pixel returns c(NA, NA) when fewer than min_obs", {
  v <- c(0.5, 0.6, NA, NA, 0.55, rep(NA_real_, 19))  # 3 non-NA < min_obs 6
  expect_equal(
    drift:::.dft_break_pixel(v, c(2018, 1), 12, c(2022, 1), "all", 3, 0.01, 6),
    c(NA_real_, NA_real_)
  )
})

# ---- bfast-gated per-pixel behavior ----------------------------------------

test_that(".dft_break_pixel detects an injected step drop (negative magnitude)", {
  skip_if_not_installed("bfast")
  tt <- seq_len(72)
  v <- 0.6 + 0.15 * sin(2 * pi * tt / 12)
  v[54:72] <- v[54:72] - 0.3  # step drop at 2022-06 (monitoring period)
  out <- drift:::.dft_break_pixel(v, c(2018, 1), 12, c(2022, 1), "all", 1, 0.01, 6)
  expect_true(is.finite(out[1]))
  expect_gt(out[1], 2022)
  expect_lt(out[1], 2022.9)
  expect_lt(out[2], 0)
})

test_that(".dft_break_pixel returns NA break on a stable series (non-error)", {
  skip_if_not_installed("bfast")
  tt <- seq_len(72)
  v <- 0.6 + 0.15 * sin(2 * pi * tt / 12)
  out <- drift:::.dft_break_pixel(v, c(2018, 1), 12, c(2022, 1), "all", 1, 0.01, 6)
  expect_true(is.na(out[1]))
})

# ---- reduction over a stack (terra + bfast, no network) --------------------

test_that("dft_rast_break reduces a synthetic stack to a 2-band raster", {
  skip_if_not_installed("bfast")
  stk <- synthetic_break_stack()
  breaks <- dft_rast_break(stk, start = c(2022, 1), order = 1, cores = 2)

  expect_s4_class(breaks, "SpatRaster")
  expect_equal(terra::nlyr(breaks), 2)
  expect_equal(names(breaks), c("break_date", "break_mag"))

  bd <- terra::values(breaks[["break_date"]])[, 1]
  bm <- terra::values(breaks[["break_mag"]])[, 1]
  # the engineered drop pixel yields a finite break with negative magnitude;
  # the all-NA pixel yields NA
  expect_true(any(is.finite(bd)))
  expect_true(any(is.na(bd)))
  expect_true(any(is.finite(bd) & bm < 0))
})

test_that("dft_rast_break errors when frequency disagrees with the cadence", {
  skip_if_not_installed("bfast")
  stk <- synthetic_break_stack()  # monthly -> cadence 12
  expect_error(dft_rast_break(stk, frequency = 1), "frequency")
})

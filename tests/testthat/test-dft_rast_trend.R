# monthly decimal-year time axis for the pure-helper tests
t24 <- seq_len(24) / 12

test_that("dft_rast_trend errors on non-SpatRaster input", {
  expect_error(dft_rast_trend(list()), "SpatRaster")
})

test_that("dft_rast_trend errors when layers lack times", {
  r <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3)
  terra::values(r) <- 1
  expect_error(dft_rast_trend(r), "time")
})

# ---- .dft_trend_pixel degenerate paths (no stats needed) -------------------

test_that(".dft_trend_pixel returns c(NA, NA) on all-NA / too-short input", {
  expect_equal(drift:::.dft_trend_pixel(rep(NA_real_, 24), t24, 6),
               c(NA_real_, NA_real_))
  expect_equal(drift:::.dft_trend_pixel(c(0.5, 0.6, 0.55), t24[1:3], 6),
               c(NA_real_, NA_real_))
})

# ---- Theil-Sen slope + Mann-Kendall p direction ----------------------------

test_that(".dft_trend_pixel recovers a rising trend (positive, significant)", {
  y <- 0.40 + 0.01 * seq_len(24)
  out <- drift:::.dft_trend_pixel(y, t24, 6)
  expect_gt(out[1], 0)          # rising
  expect_lt(out[2], 0.05)       # significant
})

test_that(".dft_trend_pixel recovers a declining trend (negative, significant)", {
  y <- 0.60 - 0.01 * seq_len(24)
  out <- drift:::.dft_trend_pixel(y, t24, 6)
  expect_lt(out[1], 0)
  expect_lt(out[2], 0.05)
})

test_that(".dft_trend_pixel reports a flat series as ~0 slope, not significant", {
  y <- 0.5 + rep(c(0.01, -0.01), 12)   # wiggle, no trend
  out <- drift:::.dft_trend_pixel(y, t24, 6)
  expect_lt(abs(out[1]), 0.02)
  expect_gt(out[2], 0.05)
})

test_that("Theil-Sen slope is robust to one anomalous season", {
  y <- 0.40 + 0.01 * seq_len(24)   # rising
  y[19:24] <- y[19:24] - 0.30      # last 'year' crashes (a smoke/drought season)
  out <- drift:::.dft_trend_pixel(y, t24, 6)
  expect_gt(out[1], 0)             # median pairwise slope stays positive
})

# ---- integration over a stack (terra, no network) --------------------------

test_that("dft_rast_trend reduces a synthetic stack to a 2-band raster", {
  stk <- synthetic_break_stack()   # 3x3, 72 monthly layers, one all-NA pixel
  trend <- dft_rast_trend(stk, cores = 2)

  expect_s4_class(trend, "SpatRaster")
  expect_equal(terra::nlyr(trend), 2)
  expect_equal(names(trend), c("trend", "trend_p"))
  # the injected step-drop pixel (pixel 1) trends down; the all-NA pixel is NA
  vals <- terra::values(trend[["trend"]])[, 1]
  expect_true(is.finite(vals[1]))
  expect_true(is.na(vals[9]))
})

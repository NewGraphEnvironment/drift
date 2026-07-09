# Build a tiny synthetic monthly index STACK for dft_rast_break() tests, no
# network, no gdalcubes. 3x3 px, 72 monthly layers 2018-2023, time set:
#   pixel 1 = seasonal series with a -0.3 step drop at 2022-06 (a real break)
#   pixels 2-8 = stable seasonal series (no break)
#   pixel 9 = all NA (degenerate pixel)
synthetic_break_stack <- function() {
  n <- 72
  tt <- seq_len(n)
  seasonal <- 0.15 * sin(2 * pi * tt / 12)
  drop <- 0.6 + seasonal
  drop[54:n] <- drop[54:n] - 0.3
  stable <- 0.6 + seasonal

  lays <- lapply(seq_len(n), function(i) {
    r <- terra::rast(nrows = 3, ncols = 3, xmin = 0, xmax = 30,
                     ymin = 0, ymax = 30, crs = "EPSG:32609")
    vv <- rep(stable[i], 9)
    vv[1] <- drop[i]
    vv[9] <- NA_real_
    terra::values(r) <- vv
    r
  })
  stk <- terra::rast(lays)
  terra::time(stk) <- seq(as.Date("2018-01-01"), by = "month", length.out = n)
  names(stk) <- rep("kndvi", n)
  stk
}

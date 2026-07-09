# Build a tiny synthetic monthly index cube for dft_rast_break() tests, with no
# network. 2x2 px over 2018-01..2023-12 (72 monthly steps), band "kndvi":
#   pixel 1 = seasonal series with a -0.3 step drop at 2022-06 (a real break)
#   pixel 2, 3 = stable seasonal series (no break)
#   pixel 4 = all NA (degenerate pixel)
# Returns list(cube, cache_dir). Only called under skip_if_not_installed guards.
synthetic_break_cube <- function() {
  n <- 72
  tt <- seq_len(n)
  seasonal <- 0.15 * sin(2 * pi * tt / 12)
  drop <- 0.6 + seasonal
  drop[54:n] <- drop[54:n] - 0.3
  stable <- 0.6 + seasonal

  scratch <- tempfile("drift_break_cube_")
  dir.create(scratch)
  dates <- format(seq(as.Date("2018-01-01"), by = "month", length.out = n),
                  "%Y-%m-%d")
  files <- character(n)
  for (i in seq_len(n)) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20,
                     ymin = 0, ymax = 20, crs = "EPSG:32609")
    terra::values(r) <- c(drop[i], stable[i], stable[i], NA_real_)
    names(r) <- "kndvi"
    files[i] <- file.path(scratch, sprintf("kndvi_%03d.tif", i))
    terra::writeRaster(r, files[i], overwrite = TRUE)
  }
  col <- gdalcubes::create_image_collection(
    files, date_time = dates, band_names = "kndvi", quiet = TRUE
  )
  v <- gdalcubes::cube_view(
    srs = "EPSG:32609",
    extent = list(left = 0, right = 20, bottom = 0, top = 20,
                  t0 = "2018-01", t1 = "2023-12"),
    dx = 10, dy = 10, dt = "P1M", aggregation = "median", resampling = "near"
  )
  list(cube = gdalcubes::raster_cube(col, v),
       cache_dir = file.path(scratch, "cache"))
}

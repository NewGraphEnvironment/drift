# A local, dated gdalcubes collection for the #87 chunk-status tests: one GeoTIFF
# per band per item, in EPSG:32609, over `ext` (xmin, xmax, ymin, ymax) at `res`.
# B04 is a constant reflectance, SCL is 4 (vegetation, never masked). `dates` are
# ISO dates, one item each.
#
# `break_dates` names items whose files are DELETED after the collection is
# built, so gdalcubes knows the image but cannot open it: the same chunk-read
# failure as an expired signed URL or a refused request, without a network.
#
# Separate files per band: two-band files with one_band_per_file = FALSE
# segfaulted a gdalcubes 0.7.5 worker (#92).
chunk_fixture <- function(dates, ext = c(0, 400, 0, 400), res = 10,
                          break_dates = character(0),
                          envir = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = envir)
  r <- terra::rast(xmin = ext[1], xmax = ext[2], ymin = ext[3], ymax = ext[4],
                   resolution = res, crs = "EPSG:32609")
  paths <- character(0)
  for (dt in dates) {
    stem <- file.path(d, paste0(format(as.Date(dt), "%Y%m%d"), "_a"))
    b <- terra::init(r, 500)
    s <- terra::init(r, 4)
    terra::writeRaster(b, paste0(stem, "_B04.tif"), datatype = "INT2U")
    terra::writeRaster(s, paste0(stem, "_SCL.tif"), datatype = "INT1U")
    paths <- c(paths, paste0(stem, c("_B04.tif", "_SCL.tif")))
  }
  fmt_file <- file.path(d, "format.json")
  writeLines(c(
    '{"description": "drift #87 fixture", "tags": ["test"],',
    ' "pattern": ".*\\\\.tif",',
    ' "images": {"pattern": ".*/([0-9]{8}_[a-z]+)_.*"},',
    ' "datetime": {"pattern": ".*/([0-9]{8})_.*", "format": "%Y%m%d"},',
    ' "bands": {"B04": {"pattern": ".*_B04\\\\.tif", "nodata": 0},',
    '           "SCL": {"pattern": ".*_SCL\\\\.tif"}}}'
  ), fmt_file)
  col <- gdalcubes::create_image_collection(
    paths, format = fmt_file, out_file = file.path(d, "col.db")
  )
  for (dt in break_dates) {
    unlink(file.path(d, paste0(format(as.Date(dt), "%Y%m%d"), "_a_B04.tif")))
  }
  col
}

# Write a cube over a chunk_fixture() collection with gdalcubes itself, at a given
# worker count, and return the NetCDF path. `chunking` small enough that a
# fixture spans several chunks.
chunk_fixture_write <- function(col, ext = c(0, 400, 0, 400), res = 10,
                                t0 = "2021-07-01", t1 = "2021-07-31",
                                dt = "P1D", aggregation = "first",
                                parallel = 1, chunking = c(1, 16, 16),
                                envir = parent.frame()) {
  old <- gdalcubes::gdalcubes_options()$parallel
  gdalcubes::gdalcubes_options(parallel = parallel)
  on.exit(gdalcubes::gdalcubes_options(parallel = old), add = TRUE)
  v <- gdalcubes::cube_view(
    srs = "EPSG:32609",
    extent = list(left = ext[1], right = ext[2], bottom = ext[3], top = ext[4],
                  t0 = t0, t1 = t1),
    dx = res, dy = res, dt = dt, aggregation = aggregation, resampling = "near"
  )
  out <- withr::local_tempfile(fileext = ".nc", .local_envir = envir)
  # A broken fixture prints gdalcubes' "[WARNING] n out of m chunks" line from
  # C++ stdio, which no R handler or capture.output() can silence (#87).
  gdalcubes::write_ncdf(gdalcubes::raster_cube(col, v, chunking = chunking), out)
  out
}

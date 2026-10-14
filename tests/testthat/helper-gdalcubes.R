# A local, dated gdalcubes collection for the #87 / #99 chunk-status tests: one
# GeoTIFF per band per item, in EPSG:32609, over `ext` (xmin, xmax, ymin, ymax) at
# `res`. B04 is a constant reflectance, SCL is 4 (vegetation, never masked).
# `dates` are ISO dates, one item each.
#
# `break_dates` names items whose `break_asset` file (B04 or SCL) is broken after
# the collection is built, so gdalcubes knows the image but cannot read it:
# * `break_mode = "delete"` removes the file, so it fails to OPEN: the same
#   failure as an expired signed URL or a refused request, without a network.
# * `break_mode = "corrupt"` overwrites the start of its first tile (see
#   tif_corrupt_tile()), so it opens and then fails to READ: the throttled or
#   refused range request that 0.7.5 records as OK (drift#99).
#
# Files are DEFLATE COGs: the compression is what makes a corrupted tile fail to
# decode (raw tiles would read as garbage), and COG layout keeps the IFD ahead of
# the tile data, so the corrupted file still opens. Separate files per band:
# two-band files with one_band_per_file = FALSE segfaulted a gdalcubes 0.7.5
# worker (#92).
chunk_fixture <- function(dates, ext = c(0, 400, 0, 400), res = 10,
                          break_dates = character(0), break_asset = "B04",
                          break_mode = c("delete", "corrupt"),
                          envir = parent.frame()) {
  break_mode <- match.arg(break_mode)
  d <- withr::local_tempdir(.local_envir = envir)
  r <- terra::rast(xmin = ext[1], xmax = ext[2], ymin = ext[3], ymax = ext[4],
                   resolution = res, crs = "EPSG:32609")
  cog <- c("COMPRESS=DEFLATE", "OVERVIEWS=NONE")
  paths <- character(0)
  for (dt in dates) {
    stem <- file.path(d, paste0(format(as.Date(dt), "%Y%m%d"), "_a"))
    b <- terra::init(r, 500)
    s <- terra::init(r, 4)
    terra::writeRaster(b, paste0(stem, "_B04.tif"), datatype = "INT2U",
                       filetype = "COG", gdal = cog)
    terra::writeRaster(s, paste0(stem, "_SCL.tif"), datatype = "INT1U",
                       filetype = "COG", gdal = cog)
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
    f <- file.path(d, paste0(format(as.Date(dt), "%Y%m%d"), "_a_", break_asset, ".tif"))
    if (break_mode == "delete") unlink(f) else tif_corrupt_tile(f)
  }
  attr(col, "fixture_dir") <- d
  col
}

# Overwrite the start of the first tile's compressed stream, located from the
# TileOffsets tag (324) of the first IFD of a little-endian classic TIFF. Not the
# end of the file: a plain GTiff keeps its IFD there (so that tests an open
# failure), and in a COG the tail is the DEFLATE trailer, which still decoded.
tif_corrupt_tile <- function(f) {
  con <- file(f, "r+b")
  on.exit(close(con))
  # little-endian classic TIFF (42; BigTIFF, 43, has 8-byte offsets)
  stopifnot(identical(readBin(con, "raw", 2), charToRaw("II")),
            readBin(con, "integer", size = 2, signed = FALSE, endian = "little") == 42L)
  seek(con, 4)
  ifd <- readBin(con, "integer", size = 4, endian = "little")
  seek(con, ifd)
  n <- readBin(con, "integer", size = 2, signed = FALSE, endian = "little")
  tile <- NA
  for (i in seq_len(n)) {
    tag <- readBin(con, "integer", size = 2, signed = FALSE, endian = "little")
    seek(con, 2, origin = "current")
    count <- readBin(con, "integer", size = 4, endian = "little")
    val <- readBin(con, "integer", size = 4, endian = "little")
    # one tile: the value IS its offset; more and it points at an array of them,
    # and overwriting there would corrupt the directory, not the pixels
    if (tag == 324) {
      stopifnot(count == 1L)
      tile <- val
    }
  }
  stopifnot(!is.na(tile))
  seek(con, tile, rw = "write")
  writeBin(as.raw(rep(0xAB, 64)), con)
  invisible(f)
}

# Write a cube over a chunk_fixture() collection with gdalcubes itself, at a given
# worker count, and return the NetCDF path. `chunking` small enough that a
# fixture spans several chunks.
chunk_fixture_write <- function(col, ext = c(0, 400, 0, 400), res = 10,
                                t0 = "2021-07-01", t1 = "2021-07-31",
                                dt = "P1D", aggregation = "first",
                                parallel = 1, chunking = c(1, 16, 16),
                                mask = NULL, pixel = NULL,
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
  cube <- gdalcubes::raster_cube(col, v, mask = mask, chunking = chunking)
  # `pixel`, e.g. production_pixel, is applied before the write
  if (!is.null(pixel)) cube <- pixel(cube)
  gdalcubes::write_ncdf(cube, out)
  out
}

# Does the installed gdalcubes record a read that fails AFTER its image opened in
# chunk_status? 0.7.5 does not (drift#99); the NewGraphEnvironment/gdalcubes fix
# does. The tests that need it skip without it, naming drift#99. Asked of the
# capability, not a version. gdalcubes computes every chunk in Rscript worker
# processes, at parallel = 1 too, and they load gdalcubes from R_LIBS rather
# than from this session's .libPaths(); so this answers for the library that
# actually does drift's reads, which is the one that matters. Lazy and memoised:
# one small write per session, only in files that ask.
# DRIFT_TEST_ASSUME_READ_STATUS=true|false overrides it, which is how the tests
# are shown to fail against a gdalcubes without the fix.
read_failures_recorded <- local({
  answer <- NULL
  function() {
    forced <- tolower(Sys.getenv("DRIFT_TEST_ASSUME_READ_STATUS"))
    if (forced %in% c("true", "1")) return(TRUE)
    if (forced %in% c("false", "0")) return(FALSE)
    if (nzchar(forced)) stop("DRIFT_TEST_ASSUME_READ_STATUS must be true or false, not ", forced)
    if (is.null(answer)) {
      col <- chunk_fixture(c("2021-07-03", "2021-07-13"), break_dates = "2021-07-13",
                           break_mode = "corrupt")
      nc <- suppressWarnings(chunk_fixture_write(col, parallel = 2))
      answer <<- drift:::chunk_status_failed(nc)[["failed"]] > 0
    }
    answer
  }
})

skip_if_no_read_failure_status <- function() {
  testthat::skip_if_not_installed("gdalcubes")
  if (!read_failures_recorded()) {
    testthat::skip("installed gdalcubes records a failed read after open as OK (drift#99)")
  }
}

# The shape drift's cube and composite reads take: a masked raster_cube, then
# apply_pixel() on the band expression with no select_bands(). gdalcubes then reads
# the mask asset (SCL) as a BAND as well as the mask, which decides which SCL
# failures 0.7.5 already records (#99): a deleted SCL fails its band open and is
# recorded; a corrupted SCL is not.
production_pixel <- function(cube) gdalcubes::apply_pixel(cube, "B04 / 10000", names = "red")

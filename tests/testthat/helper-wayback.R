# Synthetic Wayback metadata service for the dft_wayback_* tests.
#
# Footprints are squares in EPSG:3857 around a BC origin. `wb_service()` takes a
# nested list release -> layer -> list of footprints and returns a function that
# answers wayback_get() the way the ArcGIS query endpoint does, paging at
# `page_size`, and counting the calls it serves.

wb_x0 <- -13800000
wb_y0 <- 7150000

wb_square <- function(x0, y0, size) {
  list(c(x0, y0), c(x0, y0 + size), c(x0 + size, y0 + size), c(x0 + size, y0),
       c(x0, y0))
}

wb_footprint <- function(rings, date = 20170611, res = 0.5, sensor = "WV02",
                         provider = "Maxar", draw = 1) {
  list(attributes = list(SRC_DATE = date, SRC_RES = res, SRC_DESC = sensor,
                         NICE_DESC = provider, DrawOrder = draw),
       geometry = list(rings = rings))
}

wb_releases <- function(n = 1) {
  tibble::tibble(
    release_id = as.character(seq_len(n) * 100),
    release_date = as.Date("2018-01-01") + 365 * (seq_len(n) - 1),
    meta_url = sprintf("https://m.example/R%d/MapServer", seq_len(n))
  )
}

wb_service <- function(spec, page_size = 1000L) {
  calls <- 0L
  fn <- function(url, ...) {
    calls <<- calls + 1L
    rel <- sub("^https://m.example/(R[0-9]+)/MapServer/.*$", "\\1", url)
    layer <- sub("^.*/MapServer/([0-9]+)/query.*$", "\\1", url)
    offset <- as.integer(sub("^.*resultOffset=([0-9]+).*$", "\\1", url))
    feats <- spec[[rel]][[layer]] %||% list()
    take <- seq_along(feats)
    take <- take[take > offset & take <= offset + page_size]
    more <- offset + page_size < length(feats)
    jsonlite::toJSON(list(features = feats[take], exceededTransferLimit = more),
                     auto_unbox = TRUE, null = "null", digits = NA)
  }
  list(fn = fn, calls = function() calls)
}

wb_point <- function(dx, dy) {
  sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(wb_x0 + dx, wb_y0 + dy)),
                                  crs = 3857))
}

# A local 3-band EPSG:3857 raster standing in for the tile service: 200 x 200
# at 1 m from the origin, every band 100, except an all-zero (empty, as a 404
# tile reads) block in the north-east `empty_px` columns and a red band of 0
# (a real black-ish pixel) in the first row.
wb_local_source <- function(dir, empty_px = 0L) {
  r <- terra::rast(nrows = 200, ncols = 200, nlyrs = 3,
                   xmin = wb_x0, xmax = wb_x0 + 200,
                   ymin = wb_y0, ymax = wb_y0 + 200, crs = "EPSG:3857")
  v <- matrix(100, terra::ncell(r), 3)
  v[1:200, 1] <- 0
  if (empty_px > 0) {
    cols <- (200 - empty_px + 1):200
    cells <- terra::cellFromRowColCombine(r, 1:200, cols)
    v[cells, ] <- 0
  }
  terra::values(r) <- v
  f <- file.path(dir, sprintf("src_%d.tif", empty_px))
  terra::writeRaster(r, f, datatype = "INT1U", overwrite = TRUE)
  f
}

wb_poly <- function(x0, y0, size) {
  sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(x0, y0), c(x0, y0 + size), c(x0 + size, y0 + size), c(x0 + size, y0),
    c(x0, y0)
  ))), crs = 3857))
}

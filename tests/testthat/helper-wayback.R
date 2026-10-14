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

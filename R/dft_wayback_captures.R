#' Find the Esri Wayback captures that image each feature
#'
#' For every feature of `aoi` and every Wayback release, reads the release's
#' capture metadata and returns the capture (acquisition date, resolution,
#' sensor) the release's tiles show there. A release date is not a capture date
#' (see [dft_wayback_releases()]), so this is the table to choose imagery from:
#' pass it to [dft_wayback_pick()] for the capture nearest a date, then fetch it
#' with [dft_wayback_fetch()].
#'
#' Each release's metadata service has one layer per scale band, and layer `L`
#' describes the tiles at zoom `23 - L`. That mapping is handled here: pass the
#' tile `zoom` levels you would fetch at. For each feature and release one zoom
#' is kept, and the `zoom` column is the zoom to fetch at: the **deepest** zoom
#' whose footprints cover the whole feature, since its tiles are the sharpest
#' that leave no hole. Where no zoom covers a polygon whole, the zoom covering
#' most of it is kept. For a point this is simply the deepest zoom that covers
#' it.
#'
#' Footprints overlap, and the tiles draw the one with the highest `DrawOrder`
#' on top (then the finer source). **Points and polygons are answered
#' differently:**
#' * A point gets the one capture drawn on top at it. `cover` is 1.
#' * A polygon can show several captures in one release. Every distinct
#'   capture visible over it is returned, with `cover` the share of the
#'   polygon's area where that capture is the one drawn on top. A capture
#'   wholly hidden under another earns no row, and the covers of one release
#'   sum to at most 1 (less where a base layer or no imagery shows).
#'   [dft_wayback_pick()] prefers the larger cover only among captures equally
#'   near the date, so filter on it first (for example `cover >= 0.5`) when a
#'   capture must image most of a patch. A fetch over a polygon is a mosaic of
#'   whatever its release shows there, not one capture.
#'
#' A footprint with no capture date is a base layer, not a capture, and yields
#' no row. A feature that no capture covers is absent from the result.
#'
#' One metadata query is made per release and zoom over the bounding box of
#' all of `aoi` (paged), not one per feature. Responses are cached under
#' [dft_cache_path()]; a past release's metadata does not change, so only
#' `force = TRUE` re-reads them. A new query bounding box (a grown or moved
#' `aoi`) is a new cache entry.
#'
#' @param aoi An `sf`, `sfc` or `terra::SpatVector` of `POINT`, `POLYGON` or
#'   `MULTIPOLYGON` features, in any CRS.
#' @param zoom Integer vector of tile zoom levels, each in 10 to 23 (default
#'   `17:19`; zoom 17 is about 0.7 m on the ground at 54 degrees north).
#'   Zoom 10 stands for every zoom at or below 10.
#' @param releases A release table from [dft_wayback_releases()], possibly
#'   filtered, to search only some releases. When `NULL`, every release.
#' @param cache_dir Character. Cache directory. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-read the metadata even if cached (default `FALSE`).
#'
#' @return A tibble with one row per (feature, release, capture): `feature`
#'   (the row of `aoi`), `release_id`, `release_date`, `capture_date` (Date),
#'   `res_m` (the source's resolution in metres), `source` (provider and
#'   sensor, e.g. `"Maxar WV02"`), `zoom` and `cover`. Sorted by feature,
#'   release date and capture date. Zero rows, with a warning, when no capture
#'   covers any feature.
#'
#' @seealso [dft_wayback_pick()], [dft_wayback_fetch()].
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
#' pts <- sf::st_as_sf(sf::st_sample(aoi, 10, type = "regular"))
#'
#' # Every capture over the points, in releases from 2017 on
#' rel <- dft_wayback_releases()
#' cap <- dft_wayback_captures(pts, releases = rel[rel$release_date >= "2017-01-01", ])
#' table(format(cap$capture_date, "%Y"))
#'
#' # The capture nearest mid-July 2017 at each point
#' dft_wayback_pick(cap, as.Date("2017-07-01"))
#' }
#'
#' @export
dft_wayback_captures <- function(aoi,
                                 zoom = 17:19,
                                 releases = NULL,
                                 cache_dir = NULL,
                                 force = FALSE) {
  feat <- wayback_aoi_check(aoi)
  zoom <- wayback_zoom_check(zoom)
  if (is.null(releases)) releases <- dft_wayback_releases()
  releases <- wayback_releases_check(releases)
  force <- isTRUE(as.logical(force))

  is_point <- as.character(sf::st_geometry_type(feat)) == "POINT"
  feat_3857 <- sf::st_geometry(sf::st_transform(feat, 3857))
  area <- ifelse(is_point, NA_real_, as.numeric(sf::st_area(feat_3857)))
  bbox <- wayback_query_bbox(feat)
  dir_meta <- file.path(cache_scheme_dir(cache_dir, "esri-wayback"), "meta")
  dir.create(dir_meta, recursive = TRUE, showWarnings = FALSE)

  t0 <- Sys.time()
  hits <- vector("list", nrow(releases))
  for (i in seq_len(nrow(releases))) {
    per_layer <- lapply(23L - zoom, function(layer) {
      m <- wayback_meta_cached(releases$meta_url[i], layer, bbox, dir_meta,
                               force)
      if (is.null(m) || !nrow(m)) return(NULL)
      h <- wayback_join(feat_3857, is_point, area, m)
      if (is.null(h)) return(NULL)
      h$zoom <- 23L - layer
      h
    })
    h <- do.call(rbind, per_layer)
    if (is.null(h)) next
    h <- wayback_zoom_keep(h)
    h$release_id <- releases$release_id[i]
    h$release_date <- releases$release_date[i]
    hits[[i]] <- h
    if (i %% 25L == 0L) {
      message(sprintf("  %d/%d releases read (%.1f min)", i, nrow(releases),
                      as.numeric(difftime(Sys.time(), t0, units = "mins"))))
    }
  }
  wayback_captures_finish(do.call(rbind, hits))
}


#' Keep one zoom per feature in one release
#'
#' The deepest zoom whose footprints (dated or not) cover the whole feature,
#' because its tiles are what a fetch at that zoom draws and it leaves no hole.
#' Where no zoom covers it whole, the zoom of greatest cover, the deeper on a
#' tie. A point is covered whole wherever it is covered, so this is simply the
#' deepest zoom that covers it.
#' @noRd
wayback_zoom_keep <- function(h) {
  tot <- stats::aggregate(h$cover, list(feature = h$feature, zoom = h$zoom),
                          sum)
  tot$full <- tot$x >= 0.999
  o <- order(tot$feature, -tot$full, -tot$x * !tot$full, -tot$zoom,
             method = "radix")
  tot <- tot[o, , drop = FALSE]
  tot <- tot[!duplicated(tot$feature), , drop = FALSE]
  h[paste(h$feature, h$zoom) %in% paste(tot$feature, tot$zoom), , drop = FALSE]
}


#' Turn per-release hits into the captures table
#'
#' A capture date that does not parse is a base layer (no date) and is dropped.
#' But if NO hit parses, the service's date format has changed, and returning
#' an empty table would read as "no imagery here": that aborts instead.
#' @noRd
wayback_captures_finish <- function(h) {
  empty <- tibble::tibble(
    feature = integer(0), release_id = character(0),
    release_date = as.Date(character(0)), capture_date = as.Date(character(0)),
    res_m = numeric(0), source = character(0), zoom = integer(0),
    cover = numeric(0)
  )
  if (is.null(h) || !nrow(h)) {
    cli::cli_warn("No Wayback capture covers any feature of {.arg aoi}.")
    return(empty)
  }
  dated <- grepl("^[0-9]{8}$", h$src_date)
  if (!any(dated) && any(!is.na(h$src_date))) {
    cli::cli_abort(c(
      "No Wayback capture date could be read.",
      "i" = "Expected {.code YYYYMMDD}; first seen: {.val {h$src_date[!is.na(h$src_date)][1]}}."
    ))
  }
  h <- h[dated, , drop = FALSE]
  if (!nrow(h)) {
    cli::cli_warn("Only base layers (no capture date) cover {.arg aoi}.")
    return(empty)
  }
  out <- tibble::tibble(
    feature = as.integer(h$feature),
    release_id = as.character(h$release_id),
    release_date = as.Date(h$release_date),
    capture_date = as.Date(h$src_date, format = "%Y%m%d"),
    res_m = as.numeric(h$src_res),
    source = h$source,
    zoom = as.integer(h$zoom),
    cover = as.numeric(h$cover)
  )
  out[order(out$feature, out$release_date, out$release_id, out$capture_date,
            out$res_m, out$source, method = "radix"), ]
}


#' Join features to one release-layer's capture footprints
#'
#' Footprints are ranked as the tiles draw them: the highest DrawOrder on top,
#' then the finer source, then service order, so the ranking is total. A point
#' takes the top-ranked footprint it falls in. A polygon is credited with each
#' footprint's VISIBLE part (the footprint minus every footprint ranked above
#' it), so a capture hidden under another earns no cover and the covers of one
#' release-layer sum to at most 1. Base layers (no date) take part in the
#' ranking and the cover, since they hide what is beneath them; they are dropped
#' only at the end, in wayback_captures_finish(). Returns NULL when nothing
#' intersects.
#' @noRd
wayback_join <- function(feat_3857, is_point, area, m) {
  # Both sides are EPSG:3857 already. Without a CRS, sf skips the CRS lookup
  # that every subset of an sfc otherwise repeats (a third of the run at scale).
  feat_3857 <- sf::st_set_crs(feat_3857, NA)
  geom <- sf::st_set_crs(sf::st_geometry(m), NA)
  # sf prepares the FIRST argument, so the few complex footprints go first and
  # the many small features second: at BULK scale (21,701 patches) this is the
  # bulk of the run time.
  idx <- wayback_transpose(sf::st_intersects(geom, feat_3857),
                           length(feat_3857))
  n <- lengths(idx)
  if (!any(n)) return(NULL)
  rank <- order(order(-m$draw_order, m$src_res, seq_len(nrow(m)),
                      method = "radix"))
  pairs <- data.frame(feature = rep(seq_along(idx), n),
                      poly = unlist(idx, use.names = FALSE))
  pairs$rank <- rank[pairs$poly]
  pairs$src_res <- m$src_res[pairs$poly]
  pairs$src_date <- m$src_date[pairs$poly]
  pairs$source <- m$source[pairs$poly]
  pt <- is_point[pairs$feature]

  p <- pairs[pt, , drop = FALSE]
  if (nrow(p)) {
    p <- p[order(p$feature, p$rank, method = "radix"), , drop = FALSE]
    p <- p[!duplicated(p$feature), , drop = FALSE]
    p$cover <- 1
  }

  g <- pairs[!pt, , drop = FALSE]
  if (nrow(g)) {
    vis <- wayback_visible(geom, rank, unique(g$poly))
    g$cover <- 0
    for (k in unique(g$poly)) {
      v <- vis[[as.character(k)]]
      if (is.null(v)) next
      j <- which(g$poly == k)
      # Covered whole is the common case for a patch and needs no overlay.
      inside <- seq_along(j) %in% unlist(sf::st_covers(v, feat_3857[g$feature[j]]))
      g$cover[j[inside]] <- 1
      for (jj in j[!inside]) {
        x <- sf::st_intersection(feat_3857[g$feature[jj]], v)
        g$cover[jj] <- if (length(x)) {
          sum(as.numeric(sf::st_area(x))) / area[g$feature[jj]]
        } else 0
      }
    }
    key <- paste(g$feature, g$src_date, g$src_res, g$source, sep = "\x1f")
    cover <- pmin(tapply(g$cover, key, sum), 1)
    g <- g[order(g$rank, method = "radix"), , drop = FALSE]
    g <- g[!duplicated(paste(g$feature, g$src_date, g$src_res, g$source,
                             sep = "\x1f")), , drop = FALSE]
    g$cover <- as.numeric(cover[paste(g$feature, g$src_date, g$src_res,
                                      g$source, sep = "\x1f")])
    # below a square centimetre on a hectare: a sliver of numerical noise
    g <- g[g$cover > 1e-8, , drop = FALSE]
  }
  out <- rbind(p, g)
  if (!nrow(out)) return(NULL)
  out[, c("feature", "src_date", "src_res", "source", "cover")]
}


#' Invert a sparse predicate list: for each of `n` targets, the sources that hit it
#' @noRd
wayback_transpose <- function(sgbp, n) {
  src <- rep(seq_along(sgbp), lengths(sgbp))
  split(src, factor(unlist(sgbp, use.names = FALSE), levels = seq_len(n)))
}


#' The visible part of each footprint in `ks`: itself minus all ranked above
#'
#' Returns a named list of sfc (NULL where a footprint is wholly hidden). Only
#' footprints that intersect footprint k are unioned, so the cost follows local
#' overlap rather than the number of footprints in the query box.
#' @noRd
wayback_visible <- function(geom, rank, ks) {
  out <- lapply(ks, function(k) {
    above <- which(rank < rank[k])
    g <- geom[k]
    if (length(above)) {
      hit <- above[unlist(sf::st_intersects(g, geom[above]))]
      if (length(hit)) {
        g <- sf::st_difference(g, sf::st_union(geom[hit]))
        g <- g[!sf::st_is_empty(g)]
        if (!length(g)) return(NULL)
      }
    }
    g
  })
  names(out) <- as.character(ks)
  out
}


#' One release-layer's footprints over a bbox, through the cache
#' @noRd
wayback_meta_cached <- function(meta_url, layer, bbox, dir_meta, force) {
  # The salt names the fixed query choices: change any of them, change it.
  key <- cache_key_hash(list(
    meta_url, as.integer(layer), as.numeric(bbox),
    "wayback-meta-v1 outSR=3857 geometryPrecision=1 orderBy=OBJECTID"
  ))
  f <- file.path(dir_meta, paste0("meta_", key, ".rds"))
  if (!force && file.exists(f)) {
    m <- tryCatch(readRDS(f), error = function(e) e)
    if (!inherits(m, "error")) return(m)
  }
  m <- wayback_meta_query(meta_url, layer, bbox)
  tmp <- paste0(f, ".tmp", Sys.getpid(), "-", basename(tempfile("")))
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(m, tmp)
  if (!isTRUE(file.rename(tmp, f))) {
    cli::cli_abort("Could not move the Wayback metadata cache entry into place.")
  }
  m
}


#' Query one release-layer's capture footprints over a bbox, paged
#'
#' `geometryPrecision=1` (0.1 m in EPSG:3857): some release-layers answer a
#' full-precision geometry request with HTTP 500 every time (2017_r12 layer 6,
#' measured in floodplains#115) and answer at 0.1 m, which moves no join.
#' @noRd
wayback_meta_query <- function(meta_url, layer, bbox) {
  q <- function(offset) {
    paste0(meta_url, "/", layer, "/query?", paste(c(
      paste0("geometry=", paste(sprintf("%.7f", bbox), collapse = ",")),
      "geometryType=esriGeometryEnvelope", "inSR=4326",
      "spatialRel=esriSpatialRelIntersects", "outSR=3857",
      "returnGeometry=true", "geometryPrecision=1", "f=json",
      "outFields=OBJECTID,SRC_DATE,SRC_RES,SRC_DESC,NICE_DESC,DrawOrder",
      # without an order, ArcGIS does not promise stable pages
      "orderByFields=OBJECTID", paste0("resultOffset=", offset)
    ), collapse = "&"))
  }
  feats <- list()
  repeat {
    d <- wayback_meta_page(q(length(feats)), meta_url, layer)
    page <- d$features %||% list()
    feats <- c(feats, page)
    if (!isTRUE(d$exceededTransferLimit)) break
    # A page that says "more" and holds nothing would loop forever.
    if (!length(page)) {
      cli::cli_abort("The Wayback metadata service paged with an empty page.",
                     class = "drift_wayback_http")
    }
  }
  ids <- vapply(feats, function(f) as.character(f$attributes$OBJECTID %||% NA),
                "")
  feats <- feats[is.na(ids) | !duplicated(ids)]
  wayback_meta_parse(feats)
}


#' One page of a metadata query; an HTTP 200 carrying a JSON error is retried
#' like a 5xx
#' @noRd
wayback_meta_page <- function(url, meta_url, layer, tries = 3L) {
  for (i in seq_len(tries)) {
    d <- jsonlite::fromJSON(wayback_get(url), simplifyVector = FALSE)
    if (is.null(d$error)) return(d)
    if (i < tries) Sys.sleep(2 * i)
  }
  cli::cli_abort(
    c("The Wayback metadata service returned an error: {d$error$message}.",
      "i" = "{.url {meta_url}/{layer}}"),
    class = "drift_wayback_http"
  )
}


#' Esri JSON polygon features to sf, in EPSG:3857
#'
#' All of a feature's rings go into one polygon and `st_make_valid()` sorts
#' them: its linework method keeps faces by parity, so a multi-part footprint
#' (several outer rings) and a holed one both come out right. These are drift's
#' own constructions, not a caller's geometry.
#' @noRd
wayback_meta_parse <- function(feats) {
  if (!length(feats)) return(NULL)
  rings <- lapply(feats, function(f) {
    sf::st_polygon(lapply(f$geometry$rings, function(r) {
      do.call(rbind, lapply(r, function(xy) as.numeric(unlist(xy))))
    }))
  })
  # a JSON null arrives as NULL; unlist() would drop it and misalign the column
  a <- function(k) {
    vapply(feats, function(f) {
      v <- f$attributes[[k]]
      if (is.null(v)) NA_character_ else as.character(v)
    }, character(1))
  }
  src_date <- a("SRC_DATE")
  # a number arrives as a double; format it without an exponent
  num <- !is.na(src_date) & grepl("e", src_date, ignore.case = TRUE)
  src_date[num] <- format(as.numeric(src_date[num]), scientific = FALSE)
  provider <- a("NICE_DESC")
  sensor <- a("SRC_DESC")
  source <- trimws(paste(ifelse(is.na(provider), "", provider),
                         ifelse(is.na(sensor), "", sensor)))
  source[!nzchar(source)] <- NA_character_
  draw <- suppressWarnings(as.numeric(a("DrawOrder")))
  sf::st_sf(
    src_date = src_date,
    src_res = suppressWarnings(as.numeric(a("SRC_RES"))),
    source = source,
    draw_order = ifelse(is.na(draw), -Inf, draw),
    geometry = sf::st_make_valid(sf::st_sfc(rings, crs = 3857))
  )
}


#' The query bbox: all of aoi, in EPSG:4326, padded by about 10 m
#'
#' The pad keeps a single point from being a zero-area envelope. Capture
#' footprints intersecting the padded box are a superset of those intersecting
#' any feature, and the join is done on the features themselves.
#' @noRd
wayback_query_bbox <- function(feat) {
  b <- as.numeric(sf::st_bbox(sf::st_transform(feat, 4326)))
  round(b + c(-1, -1, 1, 1) * 1e-4, 7)
}


#' @noRd
wayback_aoi_check <- function(aoi) {
  if (inherits(aoi, "SpatVector")) aoi <- sf::st_as_sf(aoi)
  if (inherits(aoi, "sfc")) aoi <- sf::st_sf(geometry = aoi)
  if (!inherits(aoi, "sf")) {
    cli::cli_abort("{.arg aoi} must be an {.cls sf}, {.cls sfc} or {.cls SpatVector}.")
  }
  if (!nrow(aoi)) cli::cli_abort("{.arg aoi} has no features.")
  if (is.na(sf::st_crs(aoi))) cli::cli_abort("{.arg aoi} has no CRS.")
  if (any(sf::st_is_empty(aoi))) {
    cli::cli_abort("{.arg aoi} has an empty geometry.")
  }
  type <- as.character(sf::st_geometry_type(aoi))
  ok <- type %in% c("POINT", "POLYGON", "MULTIPOLYGON")
  if (!all(ok)) {
    cli::cli_abort(c(
      "{.arg aoi} must hold points or polygons.",
      "x" = "Found {.val {unique(type[!ok])}}."
    ))
  }
  aoi
}


#' @noRd
wayback_zoom_check <- function(zoom, scalar = FALSE) {
  ok <- is.numeric(zoom) && length(zoom) > 0 && !anyNA(zoom) &&
    all(zoom == round(zoom)) && all(zoom >= 10 & zoom <= 23)
  if (ok && scalar) ok <- length(zoom) == 1L
  if (!ok) {
    cli::cli_abort(
      "{.arg zoom} must be {if (scalar) 'one whole number' else 'whole numbers'} in 10 to 23."
    )
  }
  sort(unique(as.integer(zoom)))
}


#' @noRd
wayback_releases_check <- function(releases) {
  need <- c("release_id", "release_date", "meta_url")
  if (!is.data.frame(releases) || !all(need %in% names(releases))) {
    cli::cli_abort(c(
      "{.arg releases} must be a table from {.fn dft_wayback_releases}.",
      "i" = "It needs columns {.val {need}}."
    ))
  }
  if (!nrow(releases)) cli::cli_abort("{.arg releases} has no rows.")
  releases$release_id <- as.character(releases$release_id)
  releases$release_date <- as.Date(releases$release_date)
  if (anyDuplicated(releases$release_id)) {
    cli::cli_abort("{.arg releases} lists a release more than once.")
  }
  releases
}

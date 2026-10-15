# Esri Wayback captures and Sentinel-2 composites for the wayback-change article
# (drift#108).
#
# The area is the ~3 x 3 km box of the new_graphiti post "Sentinel-2 Ortho Mosaics
# with STAC and gdalcubes" (2026-01-08), taken as a rectangle in UTM zone 9 so
# every raster is a full rectangle on one grid. Manual review there puts the main
# forest-cover changes in 2018, 2020, 2022 and 2023.
#
# Every call goes to the network the first time and to drift's cache after it
# (Wayback metadata and chips, and the composites, all under dft_cache_path()), so
# a rerun from a warm cache is quick and must leave the committed files unchanged.
# The sub-metre chips are hundreds of MB over the box, so only small display
# rasters are committed; the article reads those and makes no network call.
#
# Usage (from the repo root):
#   Rscript data-raw/wayback_change.R
#
# Outputs, vignettes/articles/wayback-change/ (outside the tarball, as
# vignettes/articles is in .Rbuildignore):
#   meta.csv          - releases searched and their date range, the box, the zoom window
#   captures.csv      - one row per dated capture over the box
#   picks.csv         - the capture picked for each target date, from the releases
#                       where it covers the most of the box
#   s2.csv            - per-year median reflectance of each composite, to check for haze
#   wb_<date>_window.tif - each sub-metre capture over the zoom window, 0.5 m, 8-bit
#   wb_overview.tif   - the newest capture over the whole box, 5 m, 8-bit
#   s2_<year>.tif     - Sentinel-2 Jun-Jul composite, 10 m, 8-bit on one shared stretch
#   floodplain.csv    - the published Bulkley co_ff04 floodplain in the box, as WKT in
#                       UTM 9N (a GeoPackage stores a timestamp and churns): the polygon
#                       clipped to the box (part "area", for its hectares) and its edge
#                       (part "edge", for drawing), which stops at the box rather than
#                       running along it where the floodplain continues outside

suppressMessages({
  library(sf)
  library(terra)
  pkgload::load_all(".", quiet = TRUE)
})

out_dir <- "vignettes/articles/wayback-change"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

crs <- "EPSG:32609"
# Releases are searched up to a fixed date: Esri adds one most months, and an
# open range would move the picks (the later of two releases serving a capture
# wins) and with them every chip's cache key.
release_from <- as.Date("2015-01-01")
release_to <- as.Date("2026-10-15")
# Zoom 18 is 0.35 m at 54 N, finer than the 0.5 m grid; a deeper zoom would
# read several times the tiles for nothing.
zoom <- 16:18
years_key <- c(2018, 2020, 2022, 2023)

# The post's box, as its UTM bounding rectangle
bbox_ll <- c(xmin = -126.17545256019142, ymin = 54.36161045287439,
             xmax = -126.12615394008702, ymax = 54.38908432381547)
aoi <- sf::st_bbox(bbox_ll, crs = 4326) |>
  sf::st_as_sfc() |>
  sf::st_transform(crs) |>
  sf::st_bbox() |>
  sf::st_as_sfc() |>
  sf::st_as_sf()

# Zoom window, 1 km square, chosen by eye from the captures and composites:
# forest in 2014 and 2016, a cut block with its spur road by 2020, and bare
# ground again in the 2020 and 2023 composites. UTM 9N metres.
window <- c(xmin = 683750, ymin = 6028350, xmax = 684750, ymax = 6029350)

# -- Wayback: releases, captures, picks ---------------------------------------

rel_all <- dft_wayback_releases()
rel <- rel_all[rel_all$release_date >= release_from &
                 rel_all$release_date <= release_to, ]
cap <- dft_wayback_captures(aoi, zoom = zoom, releases = rel)

# One row per capture. A capture keeps its date and sensor across releases, but
# the provider name changes (DigitalGlobe -> Maxar -> Vantor), so the source is
# taken from the newest release that serves it.
cap <- cap[order(cap$capture_date, cap$release_date), ]
captures <- do.call(rbind, lapply(split(cap, cap$capture_date), function(d) {
  data.frame(
    capture_date = d$capture_date[1],
    source = d$source[nrow(d)],
    res_m = min(d$res_m),
    cover_max = round(max(d$cover), 3),
    n_releases = length(unique(d$release_id)),
    release_first = min(d$release_date),
    release_last = max(d$release_date),
    # share of the box it is drawn on in the last release serving it
    cover_last = round(max(d$cover[d$release_date == max(d$release_date)]), 3)
  )
}))
captures$sub_metre <- captures$res_m < 1

# A polygon pick prefers the later release among captures equally near the
# date, and cover only breaks ties, so a capture still drawn on part of the box
# by a later release would fetch a release that mostly shows another capture
# (2014-06-01 covers 57% of the box in the last release serving it). Keep, for
# each capture, only the releases where it covers as much of the box as it ever
# does.
cover_best <- stats::ave(cap$cover, cap$capture_date, FUN = max)
cap_pick <- cap[cap$res_m < 1 & cap$cover >= cover_best - 0.001, ]
own_years <- as.integer(format(captures$capture_date[captures$sub_metre], "%Y"))
targets <- as.Date(paste0(sort(unique(c(own_years, years_key))), "-07-01"))
picks <- dft_wayback_pick(cap_pick, targets)
picks <- as.data.frame(picks[, c("date", "capture_date", "days_from_date", "source",
                                 "res_m", "cover", "release_id", "release_date", "zoom")])
own <- picks[format(picks$date, "%Y") %in% own_years, ]
own <- own[!duplicated(own$capture_date), ]
if (!identical(sort(format(own$capture_date, "%Y")), sort(as.character(own_years)))) {
  stop("Each sub-metre capture should be picked for its own year; got ",
       paste(own$capture_date, collapse = ", "))
}

meta <- data.frame(
  releases_all = nrow(rel_all),
  releases_searched = nrow(rel),
  release_from = min(rel$release_date),
  release_to = max(rel$release_date),
  zoom_searched = paste(range(zoom), collapse = ":"),
  cover_pick = "the capture's largest cover over the box",
  crs = crs,
  box_xmin = sf::st_bbox(aoi)[["xmin"]], box_ymin = sf::st_bbox(aoi)[["ymin"]],
  box_xmax = sf::st_bbox(aoi)[["xmax"]], box_ymax = sf::st_bbox(aoi)[["ymax"]],
  box_km2 = round(as.numeric(sf::st_area(aoi)) / 1e6, 2),
  box_lat = round(mean(bbox_ll[c("ymin", "ymax")]), 4),
  win_xmin = window[["xmin"]], win_ymin = window[["ymin"]],
  win_xmax = window[["xmax"]], win_ymax = window[["ymax"]]
)

utils::write.csv(meta, file.path(out_dir, "meta.csv"), row.names = FALSE)
utils::write.csv(captures, file.path(out_dir, "captures.csv"), row.names = FALSE)
utils::write.csv(picks, file.path(out_dir, "picks.csv"), row.names = FALSE)

# -- Wayback chips: each sub-metre capture, on one grid ------------------------

# Tiles are not cached and any failed tile aborts a fetch, so retry a transient
# HTTP failure; the finished chip is cached, so a retry after success is free.
fetch_retry <- function(..., tries = 3) {
  for (k in seq_len(tries)) {
    r <- tryCatch(dft_wayback_fetch(...), drift_wayback_http = function(e) e)
    if (!inherits(r, "condition")) return(r)
    message("  fetch failed (", k, "/", tries, "): ", conditionMessage(r))
  }
  stop(r)
}
chips <- lapply(seq_len(nrow(own)), function(i) {
  fetch_retry(aoi, own$release_id[i], own$zoom[i], crs = crs, res = 0.5)
})
names(chips) <- format(own$capture_date)

# -- Sentinel-2 composites for the key years ---------------------------------

s2 <- dft_stac_composite(aoi, years = years_key, months = 6:7, crs = crs)
if (length(s2) != length(years_key)) {
  stop("Composites came back for ", length(s2), " of ", length(years_key),
       " years: ", paste(names(s2), collapse = ", "))
}
# A hazy year brightens the whole scene and skews the shared stretch
s2_stats <- data.frame(
  year = years_key, window = names(s2),
  t(vapply(s2, function(r) {
    v <- terra::global(r, fun = stats::median, na.rm = TRUE)[, 1]
    stats::setNames(round(v, 4), c("red", "green", "blue"))
  }, numeric(3)))
)
utils::write.csv(s2_stats, file.path(out_dir, "s2.csv"), row.names = FALSE)

# -- Display rasters ------------------------------------------------------------

# Written so a rerun reproduces the bytes: no tempfile names in the metadata, no
# time (which makes terra write a .aux.json), no statistics sidecar. Values are
# 1-255. A lossless raster keeps 0 as nodata, as in a Wayback chip; a JPEG one
# has no nodata, because JPEG moves a dark 1 to 0, and the window and overview
# hold no empty cell (the window's cover is checked below).
write_rgb <- function(r, f, jpeg = TRUE) {
  names(r) <- c("red", "green", "blue")
  terra::time(r) <- NULL
  terra::varnames(r) <- sub("\\.tif$", "", basename(f))
  terra::longnames(r) <- ""
  opts <- if (jpeg) c("COMPRESS=JPEG", "JPEG_QUALITY=85", "PHOTOMETRIC=YCBCR")
          else "COMPRESS=DEFLATE"
  terra::writeRaster(r, f, datatype = "INT1U", overwrite = TRUE,
                     gdal = c(opts, "TFW=NO"), NAflag = if (jpeg) NA else 0)
  unlink(paste0(f, c(".aux.xml", ".aux.json")))
  invisible(f)
}

# Sentinel-2: one stretch pooled over the four years, so a change in brightness
# between panels is in the data, not in the stretch, and shared by the three
# bands (rgb_domain() stretches each band apart, which suits false colour but
# turns true-colour forest neon green and bare ground pink).
dom <- rgb_domain(s2)
dom[1, ] <- min(dom[1, ])
dom[2, ] <- max(dom[2, ])
for (i in seq_along(s2)) {
  r8 <- round(rgb_stretch(s2[[i]], dom) * 254) + 1
  write_rgb(r8, file.path(out_dir, paste0("s2_", years_key[i], ".tif")), jpeg = FALSE)
}

# One overview, of the newest capture: it images the whole box in its release.
newest <- names(chips)[length(chips)]
ov <- terra::aggregate(chips[[newest]], fact = 10, fun = "mean", na.rm = TRUE)
write_rgb(round(ov), file.path(out_dir, "wb_overview.tif"))

if (!anyNA(window)) {
  # A box fetch mosaics whatever its release draws, so a window panel is labelled
  # with its capture only if that capture is drawn over the whole window.
  win <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(window, crs = crs)))
  # read at the zoom the chip was fetched at, which is what the tiles show
  for (i in seq_len(nrow(own))) {
    cap_win <- dft_wayback_captures(win, zoom = own$zoom[i],
                                    releases = rel[rel$release_id == own$release_id[i], ])
    hit <- cap_win[cap_win$capture_date == own$capture_date[i], ]
    if (!nrow(hit) || max(hit$cover) < 0.999) {
      stop("Capture ", own$capture_date[i], " does not cover the whole window in release ",
           own$release_id[i], " (cover ", if (nrow(hit)) max(hit$cover) else 0, ")")
    }
  }
  for (d in names(chips)) {
    w <- terra::crop(chips[[d]], terra::ext(window[c("xmin", "xmax", "ymin", "ymax")]))
    write_rgb(w, file.path(out_dir, paste0("wb_", d, "_window.tif")))
  }
}

# -- Floodplain: the published Bulkley ff04 layer -------------------------------

# The functional floodplain (flood depth four times bankfull) on the coho-accessible
# network, from the stac-floodplains-bc item for the Bulkley watershed group. Its
# GeoPackage also holds ff02 and ff06, and st_read() without a layer takes ff02.
fp_url <- "https://stac-floodplains-bc.s3.us-west-2.amazonaws.com/bulk_co_ff04/floodplain.gpkg"
fp_file <- tempfile(fileext = ".gpkg")
resp <- curl::curl_fetch_disk(fp_url, fp_file)
if (resp$status_code != 200) stop("Floodplain download returned HTTP ", resp$status_code)
# Cropped to a margin around the box first, so the edge is taken from the
# floodplain's own boundary and not from the cut.
fp_near <- sf::st_read(fp_file, layer = "co_ff04", quiet = TRUE) |>
  sf::st_geometry() |>
  sf::st_transform(crs) |>
  sf::st_crop(sf::st_bbox(sf::st_buffer(aoi, 500)))
fp <- sf::st_intersection(fp_near, sf::st_geometry(aoi)) |>
  sf::st_collection_extract("POLYGON") |>
  sf::st_union()
fp_edge <- sf::st_boundary(fp_near) |>
  sf::st_intersection(sf::st_geometry(aoi)) |>
  sf::st_collection_extract("LINESTRING") |>
  sf::st_union()
fp_ha <- round(as.numeric(sf::st_area(fp)) / 1e4, 1)
utils::write.csv(data.frame(layer = "co_ff04", source = fp_url, part = c("area", "edge"),
                            area_ha = c(fp_ha, NA),
                            wkt = c(sf::st_as_text(fp, digits = 9),
                                    sf::st_as_text(fp_edge, digits = 9))),
                 file.path(out_dir, "floodplain.csv"), row.names = FALSE, na = "")

print(captures)
print(picks)
cat("DONE\n")

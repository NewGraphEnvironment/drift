# Data for the floodplain-change-dating article (drift#108): when did the
# detected floodplain change happen, and what does it look like on the ground?
#
# The area is a ~3 x 3 km box on the Bulkley watershed group's floodplain, taken
# as a rectangle in UTM zone 9 so every raster is a full rectangle. The land
# cover and the composites are on two 10 m grids a fraction of a cell apart.
#
# Every call goes to the network the first time and to drift's cache after it
# (Wayback metadata and chips, and the composites, under dft_cache_path()),
# except the STAC item, its rasters, the Wayback release list, the BC
# cutblocks and watershed group, and the topographic tiles, which are read live.
# A warm rerun must leave the committed files unchanged unless the published
# item or the cutblock layer changed. Only small display files are committed;
# the article reads them and makes no network call.
#
# The article shows the blocks between `## ---- <label>` lines as its code, so
# what it shows is what ran. Keep those blocks readable; checks go outside them.
#
# Usage (from the repo root):
#   Rscript data-raw/floodplain_change_dating.R
#
# Outputs, vignettes/articles/floodplain-change-dating/ (outside the tarball, as
# vignettes/articles is in .Rbuildignore):
#   item.csv        - the STAC item read: id, processing date, software versions
#   floodplain.csv  - the floodplain in the box, as WKT in UTM 9N: the area
#                     (part "area") and its edge cut to the box (part "edge")
#   change.tif      - per floodplain cell: 0 stable, 1 changed but never settled,
#                     2 flickered and came back, or the year of a clean switch
#                     less 2000 (18-23); 255 (nodata) outside the floodplain
#   areas.csv       - change areas: connected cells that switched cleanly in the
#                     same year, 1 ha or more, with their classes, size, the
#                     cutblock they lie in, and the views drawn of them
#   summary.csv     - floodplain hectares in the box by what happened
#   captures.csv    - the dated Wayback captures over the box
#   s2_<year>.tif   - Sentinel-2 Jun-Jul composite, 10 m, 8-bit on one stretch
#   wb_<area>_<date>.tif - sub-metre Wayback view of a change area, 0.5 m, 8-bit
#   wb_box_<date>.tif - the newest sub-metre capture over the whole box, 2 m, 8-bit
#   topo_bulk.tif   - Esri World Topographic Map over the Bulkley watershed group,
#                     zoom 9, Web Mercator, 8-bit
#   context.csv     - outlines for the context map, as simplified WKT with their
#                     CRS: the watershed group, its floodplain, the box, and BC
#   topo_credit.txt - the basemap's attribution

suppressMessages({
  library(sf)
  library(terra)
  pkgload::load_all(".", quiet = TRUE)
})

out_dir <- "vignettes/articles/floodplain-change-dating"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
unlink(list.files(out_dir, pattern = "^wb_.*\\.tif$", full.names = TRUE))

## ---- aoi
library(drift)
crs <- "EPSG:32609"
bbox <- c(xmin = -126.17545256019142, ymin = 54.36161045287439,
          xmax = -126.12615394008702, ymax = 54.38908432381547)
aoi <- sf::st_bbox(bbox, crs = 4326) |>
  sf::st_as_sfc() |>
  sf::st_transform(crs) |>
  sf::st_bbox() |>   # the box's UTM rectangle, so rasters are full rectangles
  sf::st_as_sfc() |>
  sf::st_as_sf()

## ---- stac-item
item <- rstac::stac("https://images.a11s.one") |>
  rstac::collections("stac-floodplains-bc") |>
  rstac::items("bulk_all_ff04") |>
  rstac::get_request()
href <- function(asset) item$assets[[asset]]$href

## ---- floodplain
fp <- sf::st_read(href("floodplain"), layer = "all_ff04", quiet = TRUE) |>
  sf::st_transform(crs)

## ---- context
# Where the box lies: the Bulkley watershed group over Esri's topographic map
bulk <- bcdata::bcdc_query_geodata("WHSE_BASEMAPPING.FWA_WATERSHED_GROUPS_POLY") |>
  dplyr::filter(WATERSHED_GROUP_CODE == "BULK") |>
  dplyr::collect() |>
  sf::st_transform(3857)
around <- sf::st_as_sfc(sf::st_bbox(sf::st_buffer(bulk, 4000)))
topo <- maptiles::get_tiles(around, provider = "Esri.WorldTopoMap", zoom = 9, crop = TRUE)
bc_outline <- bcmaps::bc_bound()

## ---- landcover
years <- 2017:2023
landcover <- lapply(years, function(y) {
  r <- terra::rast(paste0("/vsicurl/", href(paste0("classified_", y))))
  terra::crop(r, terra::vect(aoi))
})
names(landcover) <- years

## ---- dates
bc <- dft_rast_break_class(landcover)
category <- dft_rast_break_category(bc)
## ----

# -- Checks and the item record ------------------------------------------------

if (!identical(item$id, "bulk_all_ff04")) stop("Unexpected STAC item: ", item$id)
sw <- item$properties[["processing:software"]]
utils::write.csv(data.frame(
  collection = "stac-floodplains-bc",
  item = item$id,
  scenario = item$properties$scenario,
  processed = item$properties[["processing:datetime"]],
  drift = sw$drift, flooded = sw$flooded, link = sw$link,
  landcover = item$properties[["landcover:source"]]
), file.path(out_dir, "item.csv"), row.names = FALSE)

# -- Floodplain in the box -------------------------------------------------------

# Cropped to a margin around the box first, so the edge is taken from the
# floodplain's own boundary and not from the cut.
fp_near <- sf::st_crop(sf::st_geometry(fp), sf::st_bbox(sf::st_buffer(aoi, 500)))
fp_box <- sf::st_intersection(fp_near, sf::st_geometry(aoi)) |>
  sf::st_collection_extract("POLYGON") |>
  sf::st_union()
fp_edge <- sf::st_boundary(fp_near) |>
  sf::st_intersection(sf::st_geometry(aoi)) |>
  sf::st_collection_extract("LINESTRING") |>
  sf::st_union()
utils::write.csv(data.frame(part = c("area", "edge"),
                            area_ha = c(round(as.numeric(sf::st_area(fp_box)) / 1e4, 1), NA),
                            wkt = c(sf::st_as_text(fp_box, digits = 9),
                                    sf::st_as_text(fp_edge, digits = 9))),
                 file.path(out_dir, "floodplain.csv"), row.names = FALSE, na = "")

# -- What happened in each floodplain cell ----------------------------------------

# One layer: the year of a clean switch, or what the category says otherwise.
# break_sustained and break_endpoint are both clean switches; an endpoint one is
# a switch in the first or last year, with one year of land cover on that side.
cat_id <- category$category
levels(cat_id) <- NULL  # the codes 0-4, labels dropped (levels<- works on a copy)
yr <- bc$breaks$break_year
change <- terra::ifel(cat_id == 3, 1, terra::ifel(cat_id == 4, 2, 0))
change <- terra::ifel(cat_id == 1 | cat_id == 2, yr, change)
names(change) <- "change"
if (anyNA(terra::values(change)[!is.na(terra::values(landcover[[1]]))])) {
  stop("A floodplain cell has no category: an interior year is NA")
}

cell_ha <- prod(terra::res(change)) / 1e4
vals <- terra::values(change)[, 1]
summary <- data.frame(
  what = c("Stable", "Changed once, and stayed", "Changed, never settled",
           "Flickered and came back"),
  ha = c(sum(vals == 0, na.rm = TRUE), sum(vals >= 2017, na.rm = TRUE),
         sum(vals == 1, na.rm = TRUE), sum(vals == 2, na.rm = TRUE)) * cell_ha
)
by_year <- as.data.frame(table(year = vals[!is.na(vals) & vals >= 2017]))
utils::write.csv(rbind(summary, data.frame(what = paste("  in", by_year$year),
                                           ha = by_year$Freq * cell_ha)),
                 file.path(out_dir, "summary.csv"), row.names = FALSE)

# Change areas: 8-connected cells that switched cleanly in the same year, 1 ha
# or more (the published layer's sieve), named A, B, ... by year then size.
tr <- bc$raster
levels(tr) <- NULL
tr_code <- terra::values(tr)[, 1]
area_list <- list()
for (y in sort(unique(vals[!is.na(vals) & vals >= 2017]))) {
  p <- terra::patches(terra::ifel(change == y, 1, NA), directions = 8)
  pv <- terra::values(p)[, 1]
  for (id in sort(unique(pv[!is.na(pv)]))) {
    cells <- which(pv == id)
    if (length(cells) * cell_ha < 1) next
    code <- as.integer(names(which.max(table(tr_code[cells]))))
    poly <- terra::as.polygons(terra::ifel(p == id, 1, NA)) |> sf::st_as_sf()
    area_list[[length(area_list) + 1]] <- data.frame(
      year = y,
      from_class = code %/% 1000, to_class = code %% 1000,
      ha = length(cells) * cell_ha,
      wkt = sf::st_as_text(sf::st_geometry(poly)[[1]], digits = 9)
    )
  }
}
areas <- do.call(rbind, area_list)
if (is.null(areas)) stop("No change area of 1 ha or more in the box")
areas <- areas[order(areas$year, -areas$ha), ]
areas$id <- LETTERS[seq_len(nrow(areas))]
ct <- dft_class_table("io-lulc")
areas$from <- ct$class_name[match(areas$from_class, ct$code)]
areas$to <- ct$class_name[match(areas$to_class, ct$code)]
area_geom <- sf::st_as_sfc(areas$wkt, crs = crs)
lab <- sf::st_coordinates(sf::st_point_on_surface(area_geom))
areas$lab_x <- round(lab[, 1])
areas$lab_y <- round(lab[, 2])

# A square view around each area, at least 400 m, inside the box
box <- sf::st_bbox(aoi)
view_of <- function(g) {
  b <- sf::st_bbox(g)
  side <- max(400, b[["xmax"]] - b[["xmin"]] + 120, b[["ymax"]] - b[["ymin"]] + 120)
  cx <- min(max((b[["xmin"]] + b[["xmax"]]) / 2, box[["xmin"]] + side / 2), box[["xmax"]] - side / 2)
  cy <- min(max((b[["ymin"]] + b[["ymax"]]) / 2, box[["ymin"]] + side / 2), box[["ymax"]] - side / 2)
  round(c(xmin = cx - side / 2, xmax = cx + side / 2, ymin = cy - side / 2, ymax = cy + side / 2))
}
views <- t(vapply(seq_along(area_geom), function(i) view_of(area_geom[i]), numeric(4)))
areas <- cbind(areas, setNames(as.data.frame(views), paste0("view_", colnames(views))))

## ---- composites
s2 <- dft_stac_composite(aoi, years = years, months = 6:7, crs = crs)
## ----

if (length(s2) != length(years)) {
  stop("Composites came back for ", length(s2), " of ", length(years), " years: ",
       paste(names(s2), collapse = ", "))
}

## ---- wayback
releases <- dft_wayback_releases()
releases <- releases[releases$release_date >= as.Date("2015-01-01") &
                       releases$release_date <= as.Date("2026-10-15"), ]
captures <- dft_wayback_captures(aoi, zoom = 16:18, releases = releases)

# A polygon pick prefers the later release among equally near captures, and cover
# only breaks ties, so keep for each capture only the releases where it covers as
# much of the box as it ever does (research/esri-wayback.md, "Picking for a polygon").
best <- stats::ave(captures$cover, captures$capture_date, FUN = max)
sharp <- captures[captures$res_m < 1 & captures$cover >= best - 0.001, ]
sharp_dates <- sort(unique(sharp$capture_date))
picks <- dft_wayback_pick(sharp, as.Date(paste0(format(sharp_dates, "%Y"), "-07-01")))
## ----

# One row per capture. The provider name changes across releases (DigitalGlobe
# -> Maxar -> Vantor), so the source is taken from the newest release serving it.
captures <- captures[order(captures$capture_date, captures$release_date), ]
cap_tab <- do.call(rbind, lapply(split(captures, captures$capture_date), function(d) {
  data.frame(capture_date = d$capture_date[1], source = d$source[nrow(d)],
             res_m = min(d$res_m), cover_max = round(max(d$cover), 3),
             n_releases = length(unique(d$release_id)),
             release_first = min(d$release_date), release_last = max(d$release_date))
}))
utils::write.csv(cap_tab, file.path(out_dir, "captures.csv"), row.names = FALSE)

picks <- picks[match(sharp_dates, picks$capture_date), ]
if (anyNA(picks$capture_date)) stop("A sub-metre capture was not picked for its own year")

# Tiles are not cached and one failed tile aborts a fetch, so fetch each chip
# here first with retries on a transient HTTP failure. The finished chip is
# cached, so the block below, which the article shows, reads it from the cache.
fetch_retry <- function(..., tries = 3) {
  for (k in seq_len(tries)) {
    r <- tryCatch(dft_wayback_fetch(...), drift_wayback_http = function(e) e)
    if (!inherits(r, "condition")) return(invisible(r))
    message("  fetch failed (", k, "/", tries, "): ", conditionMessage(r))
  }
  stop(r)
}
for (i in seq_len(nrow(picks))) {
  fetch_retry(aoi, picks$release_id[i], picks$zoom[i], crs = crs, res = 0.5)
}

## ---- wayback-fetch
chips <- lapply(seq_len(nrow(picks)), function(i) {
  dft_wayback_fetch(aoi, picks$release_id[i], picks$zoom[i], crs = crs, res = 0.5)
})
names(chips) <- format(picks$capture_date)
## ----

# -- Which Wayback views each change area gets -----------------------------------

# A box fetch mosaics whatever its release draws, so a view is labelled with a
# capture only where that capture is drawn over the whole view. The "before" view
# is the newest such capture taken before the year of the change; the "after"
# view is the newest capture, if it was taken in or after that year.
covers_view <- function(i, v) {
  w <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(v, crs = crs)))
  hit <- dft_wayback_captures(w, zoom = picks$zoom[i],
                              releases = releases[releases$release_id == picks$release_id[i], ])
  hit <- hit[hit$capture_date == picks$capture_date[i], ]
  nrow(hit) > 0 && max(hit$cover) >= 0.999
}
cap_year <- as.integer(format(picks$capture_date, "%Y"))
areas$wb_before <- NA_character_
areas$wb_after <- NA_character_
for (a in seq_len(nrow(areas))) {
  v <- unlist(areas[a, paste0("view_", c("xmin", "xmax", "ymin", "ymax"))])
  names(v) <- c("xmin", "xmax", "ymin", "ymax")
  ok <- vapply(seq_len(nrow(picks)), covers_view, logical(1), v = v)
  before <- which(ok & cap_year < areas$year[a])
  after <- which(ok & cap_year >= areas$year[a])
  if (length(before)) areas$wb_before[a] <- format(picks$capture_date[max(before)])
  if (length(after)) areas$wb_after[a] <- format(picks$capture_date[max(after)])
}

# -- Cutblocks, to corroborate harvest -----------------------------------------------

# The province's harvest record, read live from the BC WFS. Each area gets the
# start year of the cutblock holding most of it, and the share of it inside.
suppressMessages(library(bcdata))
aoi_3005 <- sf::st_transform(aoi, 3005)  # bcdata cannot translate a call inside filter()
cb <- bcdata::bcdc_query_geodata("WHSE_FOREST_VEGETATION.VEG_CONSOLIDATED_CUT_BLOCKS_SP") |>
  dplyr::filter(INTERSECTS(aoi_3005)) |>
  dplyr::collect() |>
  sf::st_transform(crs)
cb$start_year <- as.numeric(cb$HARVEST_START_YEAR_CALENDAR)
areas$cutblock_year <- NA_real_
areas$cutblock_share <- 0
for (a in seq_len(nrow(areas))) {
  hit <- which(lengths(sf::st_intersects(sf::st_geometry(cb), area_geom[a])) > 0)
  if (!length(hit)) next
  ov <- vapply(hit, function(k) {
    sum(as.numeric(sf::st_area(sf::st_intersection(sf::st_geometry(cb)[k], area_geom[a]))))
  }, 1)
  if (max(ov) <= 0) next
  k <- hit[which.max(ov)]
  areas$cutblock_year[a] <- cb$start_year[k]
  areas$cutblock_share[a] <- round(max(ov) / as.numeric(sf::st_area(area_geom[a])), 2)
}

areas$ha <- round(areas$ha, 2)
utils::write.csv(areas[, c("id", "year", "from", "to", "ha", "cutblock_year", "cutblock_share",
                           "wb_before", "wb_after", "lab_x", "lab_y",
                           "view_xmin", "view_xmax", "view_ymin", "view_ymax", "wkt")],
                 file.path(out_dir, "areas.csv"), row.names = FALSE, na = "")

# -- Display rasters -------------------------------------------------------------

# Written so a rerun reproduces the bytes: no tempfile names in the metadata, no
# time (which makes terra write a .aux.json), no statistics sidecar.
write_8bit <- function(r, f, nms, jpeg = FALSE, na = 0) {
  names(r) <- nms
  terra::time(r) <- NULL
  terra::varnames(r) <- sub("\\.tif$", "", basename(f))
  terra::longnames(r) <- ""
  opts <- if (jpeg) c("COMPRESS=JPEG", "JPEG_QUALITY=85", "PHOTOMETRIC=YCBCR")
          else "COMPRESS=DEFLATE"
  terra::writeRaster(r, f, datatype = "INT1U", overwrite = TRUE,
                     gdal = c(opts, "TFW=NO"), NAflag = if (jpeg) NA else na)
  unlink(paste0(f, c(".aux.xml", ".aux.json")))
  invisible(f)
}

# change.tif: years stored as is less 2000, so it fits a byte; 255 is outside
ch8 <- terra::ifel(change >= 2017, change - 2000, change)
write_8bit(ch8, file.path(out_dir, "change.tif"), "change", na = 255)

# Sentinel-2: one stretch pooled over every year and shared by the three bands,
# so a change in brightness between panels is in the data, not in the display
# (rgb_domain() stretches each band apart, which turns true-colour forest neon).
rgb <- c("red", "green", "blue")
dom <- rgb_domain(s2)
dom[1, ] <- min(dom[1, ])
dom[2, ] <- max(dom[2, ])
for (i in seq_along(s2)) {
  r8 <- round(rgb_stretch(s2[[i]], dom) * 254) + 1
  write_8bit(r8, file.path(out_dir, paste0("s2_", years[i], ".tif")), rgb)
}

# Wayback: each view an area gets, cut from the box chip. JPEG has no nodata,
# because it moves a dark 1 to 0; a view is drawn only where its capture covers it.
for (a in seq_len(nrow(areas))) {
  for (d in stats::na.omit(c(areas$wb_before[a], areas$wb_after[a]))) {
    e <- terra::ext(unlist(areas[a, paste0("view_", c("xmin", "xmax", "ymin", "ymax"))]))
    write_8bit(terra::crop(chips[[d]], e),
               file.path(out_dir, paste0("wb_", areas$id[a], "_", d, ".tif")), rgb, jpeg = TRUE)
  }
}

# The overview: the newest sharp capture over the whole box, at 2 m. It is drawn
# as one capture, so it must cover the whole box.
newest_d <- format(max(picks$capture_date))
if (cap_tab$cover_max[format(cap_tab$capture_date) == newest_d] < 0.999) {
  stop("The newest sharp capture does not cover the whole box")
}
ov <- round(terra::aggregate(chips[[newest_d]], fact = 4, fun = "mean", na.rm = TRUE))
write_8bit(ov, file.path(out_dir, paste0("wb_box_", newest_d, ".tif")), rgb, jpeg = TRUE)

# The context map: outlines simplified for drawing at the watershed-group scale
simple <- function(x, part, tol) {
  g <- sf::st_simplify(sf::st_union(sf::st_geometry(x)), dTolerance = tol)
  data.frame(part = part, crs = paste0("EPSG:", sf::st_crs(g)$epsg), wkt = sf::st_as_text(g[[1]], digits = 7))
}
context <- rbind(
  simple(bulk, "bulk", 100),
  simple(sf::st_transform(fp, 3857), "floodplain", 120),
  simple(sf::st_transform(aoi, 3857), "box", 0),
  simple(bc_outline, "bc", 2000),
  simple(sf::st_transform(bulk, 3005), "bulk_bc", 2000)
)
utils::write.csv(context, file.path(out_dir, "context.csv"), row.names = FALSE)
write_8bit(topo[[1:3]], file.path(out_dir, "topo_bulk.tif"), rgb, jpeg = TRUE)
writeLines(maptiles::get_credit("Esri.WorldTopoMap"), file.path(out_dir, "topo_credit.txt"))

print(read.csv(file.path(out_dir, "summary.csv")))
print(areas[, c("id", "year", "from", "to", "ha", "cutblock_year", "cutblock_share",
                "wb_before", "wb_after")])
cat("DONE\n")

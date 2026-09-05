# Scale run of dft_rast_break_class() on the whole BULK floodplain (drift#9).
#
# The bundled Neexdzii Kwa tile (600 x 600) cannot reach memory or runtime
# failure modes; the BULK watershed group floodplain (386 km2 of ff04 floodplain,
# a 14651 x 11552 grid at 10 m, 169M cells, 97.7% NA) found the #44 memory bug
# that 125 green unit assertions had not. The STAC item `bulk_co_ff04` carries
# classified rasters for 2017/2020/2023 only, so the seven IO LULC years are
# fetched from Planetary Computer through dft_stac_fetch() (tiled, cached).
#
# Usage (from the repo root):
#   Rscript data-raw/benchmark_break_class_bulk.R fetch   # populate the cache only
#   Rscript data-raw/benchmark_break_class_bulk.R run     # fetch (cached) + scan + patches
#
# Sample RSS from outside while it runs:
#   ps -o rss= -p $PID >> data-raw/logs/benchmark_break_class/rss_run.txt  (every 2 s)
#
# Outputs (data-raw/logs/benchmark_break_class/; rasters/logs are gitignored,
# the CSVs are the committed evidence record):
#   summary_pixels.csv  - res$summary (from, to, status, break_year, cells, ha)
#   summary_change.csv  - endpoint-changed pixels by category
#   summary_patches.csv - per-patch temporal evidence joined to #44's geometric tags
#   timings.csv         - stage timings

suppressMessages({
  library(sf)
  library(terra)
  pkgload::load_all(".", quiet = TRUE)
})

stage <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(stage)) stage <- "run"
stopifnot(stage %in% c("fetch", "run"))

out_dir <- file.path("data-raw", "logs", "benchmark_break_class")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

t0 <- Sys.time()
timings <- list()
tick <- function(label, start) {
  el <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  message(sprintf("[%7.1fs] %s: %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs")),
                  label, el))
  timings[[label]] <<- el
  invisible(el)
}

# --- 1. BULK floodplain polygon (the `floodplain` asset of bulk_co_ff04) ----
gpkg <- file.path(out_dir, "floodplain.gpkg")
if (!file.exists(gpkg)) {
  url <- "https://stac-floodplains-bc.s3.us-west-2.amazonaws.com/bulk_co_ff04/floodplain.gpkg"
  h <- curl::new_handle(followlocation = TRUE, timeout = 300)
  resp <- curl::curl_fetch_disk(url, gpkg, handle = h)
  if (resp$status_code != 200L) {
    unlink(gpkg)
    stop("floodplain.gpkg fetch returned HTTP ", resp$status_code)
  }
}
# co_ff04 is the layer #44 measured (386.5 km2); the file also carries ff02/ff06
aoi <- sf::st_read(gpkg, layer = "co_ff04", quiet = TRUE)
aoi <- sf::st_as_sf(sf::st_union(sf::st_geometry(aoi)))
message("AOI: ", round(as.numeric(sum(sf::st_area(aoi))) / 1e6, 1), " km2, CRS ",
        sf::st_crs(aoi)$epsg)

# --- 2. Seven IO LULC years, tiled to the floodplain footprint ----
years <- 2017:2023
t1 <- Sys.time()
rasters <- dft_stac_fetch(aoi, source = "io-lulc", years = years, tile_size = 20000)
tick("fetch", t1)
message("grid: ", paste(dim(rasters[[1]])[1:2], collapse = " x "), " at ",
        paste(terra::res(rasters[[1]]), collapse = " x "), " m, ",
        terra::crs(rasters[[1]], describe = TRUE)$code)
if (stage == "fetch") {
  message("fetch stage done")
  quit(save = "no", status = 0)
}

# --- 3. Classify and scan ----
t1 <- Sys.time()
classified <- dft_rast_classify(rasters, source = "io-lulc")
tick("classify", t1)

t1 <- Sys.time()
res <- dft_rast_break_class(classified)
tick("break_class", t1)
utils::write.csv(res$summary, file.path(out_dir, "summary_pixels.csv"), row.names = FALSE)

# --- 4. Endpoint-changed pixels by temporal category ----
# 1 = clean break sustained >= 2 years each side, 2 = clean break with one
# endpoint the odd year out, 3 = flicker, 0 = stable (n_flips == 0)
t1 <- Sys.time()
cat_fun <- function(v) {
  # refuse a bare vector: terra::app() otherwise runs this once per CELL
  if (!is.matrix(v)) stop("matrix chunks only")
  nf <- v[, 4]
  out <- rep(NA_integer_, nrow(v))
  out[!is.na(nf) & nf == 0] <- 0L
  out[!is.na(nf) & nf >= 2] <- 3L
  one <- !is.na(nf) & nf == 1
  out[one] <- ifelse(pmin(v[one, 2], v[one, 3]) >= 2, 1L, 2L)
  out
}
category <- terra::app(res$breaks, fun = cat_fun, filename = tempfile(fileext = ".tif"),
                       wopt = list(datatype = "INT1U"))
codes <- terra::deepcopy(res$raster)
levels(codes) <- NULL
changed <- terra::app(codes, fun = function(v) as.integer((v %/% 1000L) != (v %% 1000L)),
                      filename = tempfile(fileext = ".tif"), wopt = list(datatype = "INT1U"))
ct <- terra::crosstab(c(changed, category), long = TRUE, useNA = TRUE)
names(ct) <- c("changed", "category", "n_cells")
ct <- ct[!is.na(ct$changed), ]
cell_ha <- prod(terra::res(res$raster)) * 1e-4
ct$area_ha <- ct$n_cells * cell_ha
ct$category_label <- c("stable", "break_sustained", "break_endpoint", "flicker")[ct$category + 1L]
ct$pct_of_changed <- NA_real_
chg <- ct$changed == 1
ct$pct_of_changed[chg] <- round(100 * ct$n_cells[chg] / sum(ct$n_cells[chg]), 2)
tick("category_crosstab", t1)
utils::write.csv(ct, file.path(out_dir, "summary_change.csv"), row.names = FALSE)
print(ct)

# --- 5. Patches: the #44 pipeline, with per-patch temporal evidence ----
t1 <- Sys.time()
patches <- dft_transition_vectors(res$raster, changes_only = TRUE)
tick("transition_vectors", t1)
message(nrow(patches), " change patches, ", round(sum(patches$area_ha), 1), " ha")

t1 <- Sys.time()
tagged <- dft_transition_artifact(patches, res$raster)
tick("transition_artifact", t1)

t1 <- Sys.time()
pid <- terra::rasterize(terra::vect(patches), res$raster, field = "patch_id",
                        filename = tempfile(fileext = ".tif"))
is_break <- terra::app(res$breaks[["n_flips"]], fun = function(v) as.integer(v == 1L),
                       filename = tempfile(fileext = ".tif"), wopt = list(datatype = "INT1U"))
z <- terra::zonal(c(is_break, res$breaks[["break_year"]], res$breaks[["n_flips"]]),
                  pid, fun = "mean", na.rm = TRUE)
names(z) <- c("patch_id", "break_frac", "break_year_mean", "n_flips_mean")
tagged <- merge(sf::st_drop_geometry(tagged), z, by = "patch_id", all.x = TRUE)
tick("patch_zonal", t1)
utils::write.csv(tagged, file.path(out_dir, "summary_patches.csv"), row.names = FALSE)

# --- 6. Headline numbers ----
tot_ha <- sum(tagged$area_ha)
brk_ha <- sum(tagged$area_ha * tagged$break_frac, na.rm = TRUE)
message(sprintf("patch-weighted: %.1f of %.1f ha (%.1f%%) of 2017->2023 change is a clean break",
                brk_ha, tot_ha, 100 * brk_ha / tot_ha))
art <- tagged$flag_sliver & (tagged$flag_boundary | tagged$flag_reciprocal)
art[is.na(art)] <- FALSE
message(sprintf("break_frac, artifact-signature patches: median %.2f; other patches: median %.2f",
                stats::median(tagged$break_frac[art], na.rm = TRUE),
                stats::median(tagged$break_frac[!art], na.rm = TRUE)))
byyr <- res$summary[res$summary$status %in% "break", ]
byyr <- stats::aggregate(area ~ break_year, byyr, sum)
print(byyr)

utils::write.csv(data.frame(stage = names(timings), seconds = unlist(timings)),
                 file.path(out_dir, "timings.csv"), row.names = FALSE)
message("ALL STAGES DONE")

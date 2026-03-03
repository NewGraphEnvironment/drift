# Generate example test data for drift package
#
# Requires:
#   - bcfishpass database on localhost:63333
#   - bcfishpass/model/habitat_lateral/data/temp/BULK/dem.tif
#   - flooded package installed
#   - gdalcubes package installed
#   - Internet access for Planetary Computer STAC
#
# Outputs:
#   inst/extdata/example_aoi.gpkg
#   inst/extdata/example_valleys.tif
#   inst/extdata/example_2017.tif
#   inst/extdata/example_2020.tif
#   inst/extdata/example_2023.tif

library(terra)
library(sf)
library(flooded)
library(rstac)
library(gdalcubes)
library(dplyr)

sf::sf_use_s2(FALSE)
gdalcubes::gdalcubes_options(parallel = parallel::detectCores())

# --- Timing helper ----
t0 <- Sys.time()
log_time <- function(label) {
  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  message(sprintf("[%6.1fs] %s", elapsed, label))
}

# --- 1. Define bbox (small Neexdzii Kwa reach) ----
bbox_wgs84 <- c(
  xmin = -126.17545256019142,
  ymin =  54.36161045287439,
  xmax = -126.12615394008702,
  ymax =  54.38908432381547
)

bbox_sf <- sf::st_bbox(bbox_wgs84, crs = 4326) |>
  sf::st_as_sfc() |>
  sf::st_transform(3005)

log_time("Bbox defined")

# --- 2. Crop DEM ----
dem_path <- file.path(
  Sys.getenv("HOME"),
  "Projects/repo/bcfishpass/model/habitat_lateral/data/temp/BULK/dem.tif"
)
stopifnot(file.exists(dem_path))

dem_full <- terra::rast(dem_path)
dem <- terra::crop(dem_full, terra::vect(bbox_sf), snap = "out")
log_time(paste0("DEM cropped: ", dim(dem)[1], "x", dim(dem)[2], " cells"))

# --- 3. Query streams from bcfishpass ----
con <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost",
  port = 63333,
  dbname = "bcfishpass",
  user = "postgres"
)

bbox_3005 <- sf::st_bbox(bbox_sf)

streams <- sf::st_read(
  con,
  query = sprintf(
    "SELECT linear_feature_id, channel_width, gradient, stream_order, geom
     FROM bcfishpass.streams
     WHERE ST_Intersects(geom, ST_MakeEnvelope(%f, %f, %f, %f, 3005))
     AND channel_width IS NOT NULL",
    bbox_3005["xmin"], bbox_3005["ymin"],
    bbox_3005["xmax"], bbox_3005["ymax"]
  )
)

DBI::dbDisconnect(con)
log_time(paste0("Streams: ", nrow(streams), " features with channel_width"))

# --- 4. Run flooded ----
valleys <- flooded::fl_valley_confine(dem, streams)
n_valley <- sum(terra::values(valleys) == 1, na.rm = TRUE)
log_time(paste0("Valleys computed: ", n_valley, " valley cells"))

aoi_poly <- flooded::fl_valley_poly(valleys)
area_km2 <- round(as.numeric(sf::st_area(aoi_poly)) / 1e6, 2)
log_time(paste0("AOI polygon: ", area_km2, " km2"))

# --- 5. Fetch IO LULC via gdalcubes ----
stac_url <- "https://planetarycomputer.microsoft.com/api/stac/v1"
collection <- "io-lulc-annual-v02"
years <- c(2017L, 2020L, 2023L)

# AOI bbox in WGS84 for STAC query
aoi_wgs84 <- sf::st_transform(aoi_poly, 4326)
bbox_query <- as.numeric(sf::st_bbox(aoi_wgs84))

# Single STAC query covering all years
log_time("Querying STAC for IO LULC...")
items <- rstac::stac(stac_url) |>
  rstac::stac_search(
    collections = collection,
    bbox = bbox_query,
    datetime = paste0(min(years), "-01-01/", max(years), "-12-31")
  ) |>
  rstac::get_request() |>
  rstac::items_sign(sign_fn = rstac::sign_planetary_computer())

log_time(paste0("STAC returned ", length(items$features), " items"))

# Build gdalcubes image collection from STAC items
col <- gdalcubes::stac_image_collection(
  items$features,
  asset_names = "data"
)

log_time("Image collection built")

# For IO LULC, each item is one year. We extract per-year by creating
# a cube view for each year, cropped to AOI extent in native CRS (EPSG:32609).
# IO LULC is 10m in UTM — we keep native resolution.
bbox_utm <- sf::st_transform(aoi_poly, 32609) |> sf::st_bbox()

fetch_lulc_year <- function(year, col, bbox_utm) {
  log_time(paste0("Fetching IO LULC ", year, " via gdalcubes..."))

  v <- gdalcubes::cube_view(
    srs = "EPSG:32609",
    extent = list(
      left   = bbox_utm["xmin"],
      right  = bbox_utm["xmax"],
      bottom = bbox_utm["ymin"],
      top    = bbox_utm["ymax"],
      t0 = paste0(year, "-01-01"),
      t1 = paste0(year, "-12-31")
    ),
    dx = 10, dy = 10,
    dt = "P1Y",
    aggregation = "first",
    resampling = "near"
  )

  cube <- gdalcubes::raster_cube(col, v)

  # Write to temp NetCDF, then read as terra SpatRaster
  nc_tmp <- tempfile(fileext = ".nc")
  gdalcubes::write_ncdf(cube, nc_tmp)
  r <- terra::rast(nc_tmp)

  # Mask to AOI polygon
  aoi_utm <- sf::st_transform(aoi_poly, 32609)
  r <- terra::mask(r, terra::vect(aoi_utm))

  log_time(paste0("  ", year, ": ", dim(r)[1], "x", dim(r)[2], " cells"))
  r
}

lulc_list <- lapply(years, fetch_lulc_year, col = col, bbox_utm = bbox_utm)
names(lulc_list) <- years

# --- 6. Save to inst/extdata/ ----
out_dir <- "inst/extdata"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

sf::st_write(aoi_wgs84, file.path(out_dir, "example_aoi.gpkg"),
             layer = "aoi", delete_dsn = TRUE, quiet = TRUE)
terra::writeRaster(valleys, file.path(out_dir, "example_valleys.tif"),
                   overwrite = TRUE)

for (yr in years) {
  terra::writeRaster(
    lulc_list[[as.character(yr)]],
    file.path(out_dir, paste0("example_", yr, ".tif")),
    overwrite = TRUE, datatype = "INT1U"
  )
}

log_time("All files saved")

cat("\nSaved to", out_dir, ":\n")
cat("  example_aoi.gpkg\n")
cat("  example_valleys.tif\n")
for (yr in years) cat("  example_", yr, ".tif\n", sep = "")

# Summary
for (yr in years) {
  r <- terra::rast(file.path(out_dir, paste0("example_", yr, ".tif")))
  f <- terra::freq(r)
  cat("\n", yr, "class distribution:\n")
  print(f)
}

log_time("Done")

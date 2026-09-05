# Extend the bundled Neexdzii Kwa example series from three IO LULC years
# (2017, 2020, 2023 — data-raw/example_aoi.R) to all seven (2017-2023), so
# examples, tests and the land-cover vignette have a real annual series for
# dft_rast_break_class() (drift#9).
#
# example_aoi.R needs a bcfishpass database and a DEM to delineate the AOI; this
# script does not. It rebuilds the cube view from the bundled 2017 tile's own
# extent, resolution and CRS, so the new years land on the identical grid, and
# re-fetches 2017 as a CONTROL: the refetched raster must equal the bundled file
# cell for cell, or the grid is not the same and nothing is written.
#
# Requires: gdalcubes, rstac, internet access to Planetary Computer.
# Usage (from the repo root): Rscript data-raw/example_years_extend.R
#
# Outputs: inst/extdata/example_2018.tif, _2019, _2021, _2022 (INT1U, ~16 KB each)

suppressMessages({
  library(terra)
  library(sf)
  library(rstac)
  library(gdalcubes)
})

out_dir <- file.path("inst", "extdata")
ref <- terra::rast(file.path(out_dir, "example_2017.tif"))
aoi <- sf::st_read(file.path(out_dir, "example_aoi.gpkg"), quiet = TRUE)
aoi_utm <- sf::st_transform(aoi, terra::crs(ref))
epsg <- terra::crs(ref, describe = TRUE)$code
stopifnot(epsg == "32609", all(terra::res(ref) == 10))

years_new <- c(2018L, 2019L, 2021L, 2022L)
years_all <- c(2017L, years_new)   # 2017 is the control, fetched first

stac_url <- "https://planetarycomputer.microsoft.com/api/stac/v1"
collection <- "io-lulc-annual-v02"

items <- rstac::stac(stac_url) |>
  rstac::stac_search(
    collections = collection,
    bbox = as.numeric(sf::st_bbox(sf::st_transform(aoi, 4326))),
    datetime = "2017-01-01/2023-12-31",
    limit = 100
  ) |>
  rstac::get_request() |>
  rstac::items_sign(sign_fn = rstac::sign_planetary_computer())
message("STAC returned ", length(items$features), " items")
col <- gdalcubes::stac_image_collection(items$features, asset_names = "data")

e <- terra::ext(ref)
fetch_year <- function(year) {
  v <- gdalcubes::cube_view(
    srs = paste0("EPSG:", epsg),
    extent = list(left = e$xmin, right = e$xmax, bottom = e$ymin, top = e$ymax,
                  t0 = paste0(year, "-01-01"), t1 = paste0(year, "-12-31")),
    dx = 10, dy = 10, dt = "P1Y", aggregation = "first", resampling = "near"
  )
  nc <- tempfile(fileext = ".nc")
  gdalcubes::write_ncdf(gdalcubes::raster_cube(col, v), nc)
  r <- terra::rast(nc)
  r <- terra::mask(r, terra::vect(aoi_utm))
  stopifnot(terra::compareGeom(r, ref))
  r
}

# --- control: 2017 must reproduce the bundled file exactly ----
ctrl <- fetch_year(2017L)
same <- terra::compare(ctrl, ref, "==", falseNA = FALSE)
n_diff <- sum(terra::values(same)[, 1] == 0, na.rm = TRUE)
n_na_mismatch <- sum(is.na(terra::values(ctrl)[, 1]) != is.na(terra::values(ref)[, 1]))
message("2017 control: ", n_diff, " differing cells, ", n_na_mismatch, " NA mismatches")
if (n_diff > 0 || n_na_mismatch > 0) {
  stop("refetched 2017 does not reproduce inst/extdata/example_2017.tif; not writing")
}

# --- the four new years ----
for (yr in years_new) {
  r <- fetch_year(yr)
  out <- file.path(out_dir, paste0("example_", yr, ".tif"))
  terra::writeRaster(r, out, overwrite = TRUE, datatype = "INT1U")
  f <- terra::freq(terra::rast(out))
  message(yr, ": wrote ", out, " (", file.size(out), " bytes); classes ",
          paste(f$value, f$count, sep = "=", collapse = " "))
}
message("done")

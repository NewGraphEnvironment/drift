# Generate the committed artifact for vignettes/trajectory-break-detection.Rmd.
#
# NOT part of the package build. Requires network (Microsoft Planetary
# Computer), `gdalcubes`, and `bfast`. Follows drift's data-raw pattern: do the
# network + bfast work here, save a small artifact to inst/testdata/, and let
# the vignette load that artifact so every chunk runs live under pkgdown with no
# network or bfast dependency.
#
# Window (2017-2023) and reach match the land-cover vignette. The artifact
# carries the two continuous reductions (abrupt break, gradual trend), the LULC
# Trees->* transition polygons (for the interactive map + overlap check), and one
# real harvested patch's trajectory. The Sentinel-2 fetch is ~10-15 min (once;
# cached); the reductions are seconds.
#   Rscript data-raw/vignette_data_break.R

library(drift)

aoi <- sf::st_read(
  system.file("extdata", "example_aoi.gpkg", package = "drift"),
  quiet = TRUE
)
cache <- file.path("data-raw", ".break_cache")

cube <- dft_stac_cube(
  aoi, source = "sentinel-2-l2a", index = "kndvi",
  datetime = "2017-01-01/2023-12-31", dt = "P1M", months = 6:9,
  cloud_cover_max = 60, cache_dir = cache
)

breaks <- dft_rast_break(cube, start = c(2022, 1), order = 1)  # abrupt: the cuts
trend  <- dft_rast_trend(cube)                                 # gradual: which way

# ---- LULC Trees -> * transition polygons (the categorical "harvest" signal)
l17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
l23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
classified <- dft_rast_classify(list("2017" = l17, "2023" = l23), source = "io-lulc")
tt <- dft_rast_transition(classified, from = "2017", to = "2023")
tv <- dft_transition_vectors(tt$raster)
# just the actual loss transition (exclude stable "Trees -> Trees")
tree_trans <- tv[tv$transition == "Trees -> Rangeland", ]

aoi_v <- terra::vect(sf::st_transform(aoi, terra::crs(breaks)))

dir.create("inst/testdata", recursive = TRUE, showWarnings = FALSE)
saveRDS(
  list(trend_r = terra::wrap(terra::mask(trend, aoi_v)),
       break_r = terra::wrap(terra::mask(breaks[["break_mag"]], aoi_v)),
       tree_trans = tree_trans, aoi = aoi),
  "inst/testdata/neexdzii_break.rds"
)

message("Wrote inst/testdata/neexdzii_break.rds")
message("  Trees->* transition polygons: ", nrow(tree_trans))

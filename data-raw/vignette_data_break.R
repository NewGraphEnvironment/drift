# Generate the committed artifact for vignettes/trajectory-break-detection.Rmd.
#
# NOT part of the package build. Requires network (Microsoft Planetary
# Computer), `gdalcubes`, and `bfast`. Follows drift's data-raw pattern: do the
# network + bfast work here, save a small artifact to inst/testdata/, and let
# the vignette load that artifact so every chunk runs live under pkgdown with no
# network or bfast dependency.
#
# The Sentinel-2 fetch streams ~6 years of growing-season COGs and takes
# ~15 min; the bfast reduction is fast (~10 s). Run from the repo root after
# installing:
#   Rscript data-raw/vignette_data_break.R

library(drift)

aoi <- sf::st_read(
  system.file("extdata", "example_aoi.gpkg", package = "drift"),
  quiet = TRUE
)

cache <- file.path("data-raw", ".break_cache")

# Growing-season (June-September) monthly kNDVI, 2018-2023. Restricting to the
# growing season drops snow / low-sun winter noise at this latitude and cuts the
# scenes streamed ~3x; the longer window keeps enough summer history (2018-2021)
# to fit a stable BFAST baseline before the 2022 monitoring start. dft_stac_cube
# splits items at the 2022-01-25 offset boundary and corrects each side, so the
# 2018-2021 history and 2022+ monitoring are on the same reflectance scale.
cube <- dft_stac_cube(
  aoi,
  source   = "sentinel-2-l2a",
  index    = "kndvi",
  datetime = "2018-01-01/2023-12-31",
  dt       = "P1M",
  months   = 6:9,
  cloud_cover_max = 60,
  cache_dir = cache
)

# order = 1: the growing-season-only series samples a narrow part of the annual
# cycle, so a low harmonic order avoids overfitting sparse seasonal coverage
breaks <- dft_rast_break(cube, start = c(2022, 1), order = 1)

# the cube spans the AOI bounding box; clip both to the floodplain polygon for a
# tight vignette map (see dft_stac_cube() docs)
aoi_v  <- terra::vect(sf::st_transform(aoi, terra::crs(breaks)))
breaks <- terra::mask(breaks, aoi_v)
kndvi  <- terra::mask(cube, aoi_v)
dates  <- terra::time(kndvi)

# Keep the artifact small: ship the 2-band break raster plus a few representative
# pixel trajectories (strongest drop + a stable pixel), not the whole stack.
bd <- terra::values(breaks[["break_date"]])[, 1]
bm <- terra::values(breaks[["break_mag"]])[, 1]
kvals   <- terra::values(kndvi)
has_obs <- rowSums(!is.na(kvals)) >= 6          # pixels with a usable series
worst   <- which.min(bm)                        # strongest index drop
stable  <- which(is.na(bd) & has_obs)[1]        # a pixel with data but no break
sample_cells <- c(scour = worst, stable = stable)

traj <- do.call(rbind, lapply(names(sample_cells), function(lab) {
  cell <- sample_cells[[lab]]
  data.frame(
    label = lab, date = dates,
    kndvi = kvals[cell, ],
    break_date = bd[cell]
  )
}))

dir.create("inst/testdata", recursive = TRUE, showWarnings = FALSE)
saveRDS(
  list(breaks = terra::wrap(breaks), traj = traj, aoi = aoi),
  "inst/testdata/neexdzii_break.rds"
)

message("Wrote inst/testdata/neexdzii_break.rds")
message("  break layers: ", paste(names(breaks), collapse = ", "))
message("  AOI pixels with a break: ", sum(is.finite(bd)))

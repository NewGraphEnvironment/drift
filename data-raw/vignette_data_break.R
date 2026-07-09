# Generate the committed artifact for vignettes/trajectory-break-detection.Rmd.
#
# NOT part of the package build. Requires network (Microsoft Planetary
# Computer), `gdalcubes`, and `bfast`. Follows drift's data-raw pattern: do the
# network + bfast work here, save a small artifact to inst/testdata/, and let
# the vignette load that artifact so every chunk runs live under pkgdown with no
# network or bfast dependency.
#
# The window (2017-2023) matches the land-cover vignette so the two are
# comparable, and the artifact carries a LULC "tree-loss" grouping so the
# vignette can show the trajectory method agreeing with (and dating) the
# categorical change. The Sentinel-2 fetch is ~10-15 min (once; cached after);
# the bfast reduction is seconds. Run from the repo root after installing:
#   Rscript data-raw/vignette_data_break.R

library(drift)

aoi <- sf::st_read(
  system.file("extdata", "example_aoi.gpkg", package = "drift"),
  quiet = TRUE
)
cache <- file.path("data-raw", ".break_cache")

# Growing-season (June-September) monthly kNDVI, 2017-2023 -- same reach and
# window as the land-cover vignette. dft_stac_cube splits items at the 2022-01-25
# offset boundary so the 2017-2021 history and 2022+ monitoring share one scale.
cube <- dft_stac_cube(
  aoi, source = "sentinel-2-l2a", index = "kndvi",
  datetime = "2017-01-01/2023-12-31", dt = "P1M", months = 6:9,
  cloud_cover_max = 60, cache_dir = cache
)

# order = 1 for the narrow growing-season cycle; monitor from 2022 with 2017-2021
# as the stable history (long baseline -> fewer false breaks).
breaks <- dft_rast_break(cube, start = c(2022, 1), order = 1)

# ---- LULC ground truth (shipped IO LULC rasters; codes 2=Trees, 8=Bare, 11=Rangeland)
l17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
l20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
l23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
treeloss <- ((l17 == 2) | (l20 == 2)) & (l23 == 8 | l23 == 11)  # Trees -> Rangeland/Bare
intact   <- (l20 == 2) & (l23 == 2)                            # Trees -> Trees
tl <- terra::project(treeloss, breaks, method = "near")
it <- terra::project(intact,   breaks, method = "near")

bd <- terra::values(breaks[["break_date"]])[, 1]
bm <- terra::values(breaks[["break_mag"]])[, 1]
tlv <- terra::values(tl)[, 1]
itv <- terra::values(it)[, 1]
is_tl <- !is.na(tlv) & tlv == 1
is_it <- !is.na(itv) & itv == 1
is_bg <- is.finite(bm) & !is_tl & !is_it

# summary stats stated in the vignette
stats <- list(
  n_treeloss   = sum(is_tl),
  rate_treeloss = mean(is.finite(bd[is_tl])),
  rate_background = mean(is.finite(bd[is_bg])),
  mag_treeloss = stats::median(bm[is_tl], na.rm = TRUE),
  mag_background = stats::median(bm[is_bg], na.rm = TRUE),
  date_treeloss = stats::median(bd[is_tl & is.finite(bd)], na.rm = TRUE)
)

# grouped mean-kNDVI trajectories (tree-loss / intact forest / background)
kv <- terra::values(cube)
dates <- terra::time(cube)
grp_traj <- function(sel, lab) {
  data.frame(date = dates, kndvi = colMeans(kv[sel, , drop = FALSE], na.rm = TRUE),
             group = lab)
}
traj <- rbind(grp_traj(is_tl, "tree-loss (LULC)"),
              grp_traj(is_it, "intact forest"),
              grp_traj(is_bg, "background"))

# clip the shipped rasters to the AOI polygon for tight vignette maps
aoi_v <- terra::vect(sf::st_transform(aoi, terra::crs(breaks)))
breaks_c <- terra::mask(breaks, aoi_v)
tl_c <- terra::mask(tl, aoi_v)

dir.create("inst/testdata", recursive = TRUE, showWarnings = FALSE)
saveRDS(
  list(breaks = terra::wrap(breaks_c), treeloss = terra::wrap(tl_c),
       traj = traj, stats = stats, aoi = aoi),
  "inst/testdata/neexdzii_break.rds"
)

message("Wrote inst/testdata/neexdzii_break.rds")
message(sprintf("  tree-loss break rate %.0f%% vs background %.0f%%; median mag %.3f vs %.3f; median date %.2f",
                100 * stats$rate_treeloss, 100 * stats$rate_background,
                stats$mag_treeloss, stats$mag_background, stats$date_treeloss))

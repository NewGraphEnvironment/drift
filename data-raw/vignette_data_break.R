# Generate the committed artifact for vignettes/trajectory-break-detection.Rmd.
#
# NOT part of the package build. Requires network (Microsoft Planetary
# Computer), `gdalcubes`, and `bfast`. Follows drift's data-raw pattern: do the
# network + bfast work here, save a small artifact to inst/testdata/, and let
# the vignette load that artifact so every chunk runs live under pkgdown with no
# network or bfast dependency.
#
# Window (2017-2023) and reach match the land-cover vignette. The artifact
# carries both continuous reductions -- abrupt breaks (dft_rast_break) and a
# monotonic trend (dft_rast_trend) -- plus a LULC "tree-loss" grouping so the
# vignette can use the trajectory as a QA layer on the categorical change.
# The Sentinel-2 fetch is ~10-15 min (once; cached); the reductions are seconds.
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

breaks <- dft_rast_break(cube, start = c(2022, 1), order = 1)  # abrupt: when
trend  <- dft_rast_trend(cube)                                 # gradual: which way

# ---- LULC ground truth (shipped IO LULC; codes 2=Trees, 8=Bare, 11=Rangeland)
l17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
l20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
l23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
treeloss <- ((l17 == 2) | (l20 == 2)) & (l23 == 8 | l23 == 11)  # Trees -> Rangeland/Bare
intact   <- (l20 == 2) & (l23 == 2)                            # Trees -> Trees
tl <- terra::project(treeloss, breaks, method = "near")
it <- terra::project(intact,   breaks, method = "near")

# restrict the comparison to the floodplain AOI (groups + background all inside)
aoi_v <- terra::vect(sf::st_transform(aoi, terra::crs(breaks)))
in_aoi <- !is.na(terra::values(terra::rasterize(aoi_v, breaks[[1]]))[, 1])

sl <- terra::values(trend[["trend"]])[, 1]
pv <- terra::values(trend[["trend_p"]])[, 1]
bd <- terra::values(breaks[["break_date"]])[, 1]
is_tl <- in_aoi & !is.na(terra::values(tl)[, 1]) & terra::values(tl)[, 1] == 1
is_it <- in_aoi & !is.na(terra::values(it)[, 1]) & terra::values(it)[, 1] == 1
is_bg <- in_aoi & is.finite(sl) & !is_tl & !is_it

# QA table: does the continuous signal back up the categorical "tree loss"?
qa_row <- function(sel, lab) {
  data.frame(
    group = lab, n = sum(sel),
    median_trend = stats::median(sl[sel], na.rm = TRUE),
    pct_declining = mean(pv[sel] < 0.05 & sl[sel] < 0, na.rm = TRUE),
    pct_recovering = mean(pv[sel] < 0.05 & sl[sel] > 0, na.rm = TRUE),
    break_rate = mean(is.finite(bd[sel]))
  )
}
qa <- rbind(qa_row(is_tl, "tree-loss (LULC)"),
            qa_row(is_it, "intact forest"),
            qa_row(is_bg, "background"))

# grouped mean-kNDVI trajectories
kv <- terra::values(cube)
dates <- terra::time(cube)
grp_traj <- function(sel, lab) {
  data.frame(
    date = dates, kndvi = colMeans(kv[sel, , drop = FALSE], na.rm = TRUE),
    group = lab
  )
}
traj <- rbind(grp_traj(is_tl, "tree-loss (LULC)"),
              grp_traj(is_it, "intact forest"),
              grp_traj(is_bg, "background"))

# clip rasters to the AOI polygon for tight vignette maps (aoi_v defined above)
dir.create("inst/testdata", recursive = TRUE, showWarnings = FALSE)
saveRDS(
  list(break_r = terra::wrap(terra::mask(breaks, aoi_v)),
       trend_r = terra::wrap(terra::mask(trend, aoi_v)),
       treeloss = terra::wrap(terra::mask(tl, aoi_v)),
       traj = traj, qa = qa, aoi = aoi),
  "inst/testdata/neexdzii_break.rds"
)

message("Wrote inst/testdata/neexdzii_break.rds")
print(qa)

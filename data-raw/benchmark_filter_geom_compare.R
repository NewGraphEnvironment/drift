# Equivalence check for the drift#47 benchmark arms.
#
# The speed table says which arm is cheapest; this says whether the cheap arms
# return the SAME cube. A read-bound that is fast because it dropped pixels is
# not a win, and the all-NA mode filter_geom used to exhibit would look like a
# spectacular speedup in the timing table alone.
#
# Comparison is deliberately NOT pixel-for-pixel. gdalcubes enlarges a cube_view
# extent symmetrically to align with dx/dy, so a padded extent (which the
# filter_geom arms need -- the polygon must be strictly interior) can land on a
# sub-pixel-offset grid from the unpadded baseline. #38 measured the same effect
# for tiling and settled on bilinear-aligning one onto the other and checking
# correlation + per-layer means. Same method here.
#
# Usage: Rscript data-raw/benchmark_filter_geom_compare.R

suppressMessages({
  library(terra)
  library(sf)
  pkgload::load_all(".", quiet = TRUE)
})

out_dir <- file.path("data-raw", "logs", "benchmark_filter_geom")
ref_arm <- "A_bbox_mask"

tifs <- Sys.glob(file.path(out_dir, "*.tif"))
if (!length(tifs)) stop("no arm rasters in ", out_dir, " -- run the benchmark first")

ref_tif <- file.path(out_dir, paste0(ref_arm, ".tif"))
if (!file.exists(ref_tif)) stop("baseline arm missing: ", ref_tif)
ref <- terra::rast(ref_tif)

aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"),
                   quiet = TRUE)
aoi_t <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", auto_utm_epsg(aoi))))

rows <- lapply(tifs, function(tif) {
  arm <- tools::file_path_sans_ext(basename(tif))
  r <- terra::rast(tif)

  same_grid <- isTRUE(all.equal(as.vector(terra::ext(r)), as.vector(terra::ext(ref)))) &&
    identical(dim(r)[1:2], dim(ref)[1:2])

  # align onto the baseline grid before comparing anything
  r_al <- if (same_grid) r else terra::resample(r, ref, method = "bilinear")

  a <- terra::values(ref)
  b <- terra::values(r_al)
  both <- !is.na(a) & !is.na(b)

  # in-polygon coverage: the assertion that an all-NA cube cannot survive
  inpoly <- terra::mask(r_al, terra::vect(aoi_t))

  data.frame(
    arm          = arm,
    same_grid    = same_grid,
    nlyr         = terra::nlyr(r),
    ncell        = terra::ncell(r),
    n_nonna      = sum(!is.na(terra::values(r))),
    n_nonna_poly = sum(!is.na(terra::values(inpoly))),
    # of the baseline's valid pixels, how many does this arm also have?
    recall       = round(sum(both) / max(1L, sum(!is.na(a))), 4),
    cor          = if (sum(both) > 2) round(stats::cor(a[both], b[both]), 5) else NA_real_,
    max_abs_diff = if (any(both)) round(max(abs(a[both] - b[both])), 6) else NA_real_,
    mean_diff    = if (any(both)) round(mean(a[both] - b[both]), 8) else NA_real_,
    stringsAsFactors = FALSE
  )
})

tab <- do.call(rbind, rows)
tab <- tab[order(tab$arm), ]
print(tab, row.names = FALSE)
write.csv(tab, file.path(out_dir, "equivalence.csv"), row.names = FALSE)
message("\nwrote ", file.path(out_dir, "equivalence.csv"))

# Explicit verdicts, so a reader does not have to infer them from the columns.
message("\n-- verdicts --")
for (i in seq_len(nrow(tab))) {
  a <- tab[i, ]
  if (a$arm == ref_arm) next
  verdict <- if (a$n_nonna_poly == 0) {
    "FAIL: no in-polygon data at all (the all-NA mode)"
  } else if (is.na(a$cor) || a$cor < 0.99) {
    sprintf("FAIL: correlation %.5f against the baseline", a$cor)
  } else if (a$recall < 0.95) {
    sprintf("WARN: recovers only %.1f%% of the baseline's valid pixels", 100 * a$recall)
  } else {
    sprintf("ok: cor %.5f, recall %.1f%%, max|diff| %.4g",
            a$cor, 100 * a$recall, a$max_abs_diff)
  }
  message(sprintf("  %-14s %s", a$arm, verdict))
}

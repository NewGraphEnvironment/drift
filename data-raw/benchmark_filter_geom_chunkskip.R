# Predicted chunk-skip fraction for the packaged AOI (drift#47).
#
# filter_geom skips a chunk only when the chunk does not intersect the polygon at
# all, so the achievable read reduction is computable from geometry alone. This
# is committed as the EVIDENCE for the "skips 26.7% of the ground at 64 px
# chunking" claim in NEWS.md and inst/notes/gdalcubes-pc-gotchas.md -- otherwise
# it would be the one number in that set with nothing behind it.
#
# It is a PREDICTION, not a measurement: the observed cost is in
# data-raw/logs/benchmark_filter_geom/summary.csv, and the two disagree, which is
# the point. The arithmetic says 64 px chunking should cut requests by ~26.7%; the
# wire says requests went UP 50%, because a 64 px chunk sits inside one 512x512
# COG block and the same bytes are refetched per chunk. Keep both: the gap
# between them is the finding.
#
# Usage: Rscript data-raw/benchmark_filter_geom_chunkskip.R
suppressMessages({ library(sf) })

aoi <- sf::st_read("inst/extdata/example_aoi.gpkg", quiet = TRUE)
cen <- sf::st_coordinates(sf::st_centroid(sf::st_union(sf::st_transform(aoi, 4326))))
epsg <- (if (cen[1, "Y"] >= 0) 32600 else 32700) + floor((cen[1, "X"] + 180) / 6) + 1
at <- sf::st_transform(aoi, epsg)
u <- sf::st_union(sf::st_geometry(at))

res <- 10
for (pad_px in c(0, 2)) {
  b <- sf::st_bbox(at)
  pad <- pad_px * res
  b[["xmin"]] <- b[["xmin"]] - pad; b[["xmax"]] <- b[["xmax"]] + pad
  b[["ymin"]] <- b[["ymin"]] - pad; b[["ymax"]] <- b[["ymax"]] + pad
  nx <- ceiling((b[["xmax"]] - b[["xmin"]]) / res)
  ny <- ceiling((b[["ymax"]] - b[["ymin"]]) / res)
  cat(sprintf("\n== pad %d px : cube %d x %d px ==\n", pad_px, nx, ny))

  for (cpx in c(1024, 256, 128, 64)) {
    cell <- cpx * res
    grid <- sf::st_make_grid(sf::st_as_sfc(b), cellsize = cell,
                             offset = c(b[["xmin"]], b[["ymin"]]))
    hit <- lengths(sf::st_intersects(grid, u)) > 0
    cat(sprintf("chunk %4d px (%5.0f m): %3d chunks, %3d intersect -> read %5.1f%% (skip %5.1f%%)\n",
                cpx, cell, length(grid), sum(hit),
                100 * sum(hit) / length(grid), 100 * (1 - sum(hit) / length(grid))))
  }
}

cat("\nAOI / bbox area ratio:",
    round(as.numeric(sum(sf::st_area(at))) /
          as.numeric(diff(sf::st_bbox(at)[c(1, 3)]) * diff(sf::st_bbox(at)[c(2, 4)])), 4), "\n")

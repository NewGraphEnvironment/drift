# Scale test for dft_stac_composite() on the BULK floodplain (drift#79).
#
# The bundled Neexdzii Kwa reach cannot reach memory or runtime failure modes,
# so the CLAUDE.md convention is to run new raster functions on the BULK
# floodplain (bulk_co_ff04, 386.5 km2 inside a ~146 x 115 km bbox) before the PR.
#
# Two stages, because #79 serves two paths:
#   chips       100 sample points in the floodplain, each buffered 300 m and
#               composited on its own: the floodplains#93 review path.
#   floodplain  one floodplain-wide true-colour composite, tiled: the COG path
#               for titiler browsing.
#
#   Rscript data-raw/benchmark_composite_bulk.R chips
#   Rscript data-raw/benchmark_composite_bulk.R floodplain
#
# Run through data-raw/benchmark_composite_bulk-run.sh, which samples RSS every
# 2 s from outside the process and records the wall clock.

# Load the SOURCE tree, never the installed package (code-check-r.md).
pkgload::load_all(quiet = TRUE)

stage <- commandArgs(trailingOnly = TRUE)[1]
stopifnot(stage %in% c("chips", "floodplain"))

out_dir <- file.path("data-raw", "logs", "benchmark_composite_bulk")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cache <- file.path(tempdir(), "drift_composite_bulk")

# --- BULK floodplain polygon (the `floodplain` asset of bulk_co_ff04) -------
gpkg <- file.path(out_dir, "floodplain.gpkg")
if (!file.exists(gpkg)) {
  url <- "https://stac-floodplains-bc.s3.us-west-2.amazonaws.com/bulk_co_ff04/floodplain.gpkg"
  tmp <- tempfile(fileext = ".gpkg")
  resp <- curl::curl_fetch_disk(url, tmp)
  if (resp$status_code != 200) stop("floodplain.gpkg fetch returned HTTP ", resp$status_code)
  stopifnot(file.copy(tmp, gpkg))
}
# co_ff04 explicitly: the file also carries ff02/ff06 and st_read() takes ff02
aoi <- sf::st_read(gpkg, layer = "co_ff04", quiet = TRUE)

timings <- list()
tick <- function(label, expr) {
  t0 <- Sys.time()
  force(expr)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  timings[[label]] <<- secs
  message(sprintf("%s: %.1f s", label, secs))
  invisible(secs)
}

if (stage == "chips") {
  set.seed(79)
  pts <- sf::st_as_sf(sf::st_sample(sf::st_union(aoi), 100))
  buf <- sf::st_buffer(pts, 300)
  per_chip <- numeric(nrow(buf))
  cells <- numeric(nrow(buf))
  tick("wall", {
    for (i in seq_len(nrow(buf))) {
      t0 <- Sys.time()
      chip <- suppressMessages(
        dft_stac_composite(buf[i, ], years = 2023, months = 7:8, cache_dir = cache)
      )
      per_chip[i] <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
      cells[i] <- terra::ncell(chip[[1]])
    }
  })
  utils::write.csv(data.frame(chip = seq_along(per_chip), secs = per_chip,
                              cells = cells),
                   file.path(out_dir, "chips_per_chip.csv"), row.names = FALSE)
  cache_mb <- sum(file.size(list.files(cache, recursive = TRUE,
                                       full.names = TRUE))) / 2^20
  message(sprintf("chips: %d, median %.1f s, max %.1f s, cells/chip %d, cache %.1f MB",
                  length(per_chip), stats::median(per_chip), max(per_chip),
                  as.integer(stats::median(cells)), cache_mb))
}

if (stage == "floodplain") {
  # On failure, inventory R's temp files BEFORE the session deletes them: run 4
  # (2026-09-28) read all 30 tiles, then terra::mask() could not read the merged
  # mosaic's spat_*.tif, and the evidence went with the tempdir (#88).
  # tick() returns the seconds, so the composite is assigned inside the block
  withCallingHandlers(
    tick("wall", {
      fp <- dft_stac_composite(aoi, years = 2023, months = 7:8, clip = TRUE,
                               tile_size = 20000, cache_dir = cache)
    }),
    error = function(e) {
      message("FAILED: ", conditionMessage(e))
      tmp <- list.files(tempdir(), full.names = TRUE)
      info <- file.info(tmp)
      message("tempdir: ", tempdir(), " (", length(tmp), " files, ",
              round(sum(info$size, na.rm = TRUE) / 2^30, 2), " GiB)")
      for (f in tmp[grepl("^spat_", basename(tmp))]) {
        message("--- ", basename(f), " ", info[f, "size"], " bytes, mtime ",
                format(info[f, "mtime"]))
        message(paste(tryCatch(system2("gdalinfo", c("-checksum", f), stdout = TRUE,
                                        stderr = TRUE), error = function(x) "gdalinfo failed"),
                      collapse = "\n"))
      }
    }
  )
  r <- fp[[1]]
  f <- list.files(cache, pattern = "^composite_.*\\.tif$", recursive = TRUE,
                  full.names = TRUE)
  message(sprintf("floodplain: %d x %d x %d, notNA %.1f%%, COG %.1f MB",
                  terra::nrow(r), terra::ncol(r), terra::nlyr(r),
                  100 * terra::global(r[[1]], "notNA")[1, 1] / terra::ncell(r),
                  file.size(f[1]) / 2^20))
}

utils::write.csv(data.frame(stage = stage, what = names(timings),
                            secs = unlist(timings)),
                 file.path(out_dir, paste0("timings_", stage, ".csv")),
                 row.names = FALSE)
message("ALL STAGES DONE")

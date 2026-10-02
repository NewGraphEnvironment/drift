# Live acceptance for drift#87: a read whose signed URLs are bad aborts and
# caches nothing, and a normal read is unaffected.
#
# Every asset is signed and then has its SAS `sig` replaced, through a `sign_fn`
# that wraps rstac's Planetary Computer signer. stac_features_resign() calls the
# same `sign_fn` before each extent, so re-signing cannot repair the token: the
# image fails to open, as it does when a token has expired. This is the #79
# failure (every chunk of 15 of 30 tiles), which drift used to cache.
#
#   Rscript data-raw/probe_chunk_status_live.R
#
# Writes data-raw/logs/probe_chunk_status_live/<UTC stamp>.txt (committed: .log
# is gitignored under data-raw/logs). Packaged AOI,
# a few minutes of network reads.

# Load the SOURCE tree, never the installed package (code-check-r.md).
pkgload::load_all(quiet = TRUE)

out_dir <- file.path("data-raw", "logs", "probe_chunk_status_live")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
log_file <- file.path(out_dir, paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ",
                                             tz = "UTC"), ".txt"))
say <- function(...) {
  line <- paste0(format(Sys.time(), "%H:%M:%SZ", tz = "UTC"), " ", ...)
  cat(line, "\n")
  cat(line, "\n", file = log_file, append = TRUE)
}

aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"),
                   quiet = TRUE)

# Sign, then spoil the token, on every call: query time and every re-sign.
pc <- rstac::sign_planetary_computer()
sign_bad <- function(item) {
  item <- pc(item)
  item$assets <- lapply(item$assets, function(a) {
    a$href <- sub("sig=[^&]+", "sig=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                  a$href)
    a
  })
  item
}

# Run one call; record the outcome class, the cache files left and the time.
probe <- function(label, expect, fn) {
  cache <- tempfile("drift87_")
  t0 <- Sys.time()
  res <- tryCatch(
    {
      out <- suppressMessages(fn(cache))
      list(outcome = "returned", detail = class(out)[1])
    },
    drift_incomplete_cube = function(e) {
      list(outcome = "drift_incomplete_cube",
           detail = gsub("\\s+", " ", conditionMessage(e)))
    },
    error = function(e) {
      list(outcome = paste0("error:", class(e)[1]),
           detail = gsub("\\s+", " ", conditionMessage(e)))
    }
  )
  files <- list.files(cache, recursive = TRUE)
  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))
  ok <- identical(res$outcome, expect) &&
    (expect == "returned" || length(files) == 0L)
  say(sprintf("%s | %s | expect %s | got %s | cache files %d | %d s | gdalcubes parallel after %s",
              if (ok) "PASS" else "FAIL", label, expect, res$outcome,
              length(files), secs, gdalcubes::gdalcubes_options()$parallel))
  say("    ", substr(res$detail, 1, 300))
  unlink(cache, recursive = TRUE)
  ok
}

say("drift ", as.character(utils::packageVersion("drift")), " (source tree), gdalcubes ",
    as.character(utils::packageVersion("gdalcubes")), ", cores ",
    parallel::detectCores(), ", auto parallel ", drift:::cube_parallel_check(NULL))

results <- c(
  # composite: parallel = NULL, the auto default
  probe("composite untiled, bad tokens", "drift_incomplete_cube", function(cache)
    dft_stac_composite(aoi, years = 2023, months = 7, bands = "red",
                       cache_dir = cache, sign_fn = sign_bad)),
  probe("composite tiled 1000 m, bad tokens", "drift_incomplete_cube", function(cache)
    dft_stac_composite(aoi, years = 2023, months = 7, bands = "red",
                       tile_size = 1000, cache_dir = cache, sign_fn = sign_bad)),
  probe("cube untiled, bad tokens", "drift_incomplete_cube", function(cache)
    dft_stac_cube(aoi, index = "ndvi", datetime = "2023-07-01/2023-07-31",
                  cache_dir = cache, sign_fn = sign_bad)),
  # fetch reads at the session worker count, which gdalcubes ships as 1
  probe("fetch untiled, bad tokens, session parallel", "drift_incomplete_cube",
        function(cache)
          dft_stac_fetch(aoi, years = 2023, cache_dir = cache, sign_fn = sign_bad)),
  probe("fetch tiled 1000 m, bad tokens, session parallel", "drift_incomplete_cube",
        function(cache)
          dft_stac_fetch(aoi, years = 2023, tile_size = 1000, cache_dir = cache,
                         sign_fn = sign_bad)),
  # false-abort controls with good tokens: empty months and cloud-masked chunks
  # are the normal reads that leave chunks unvisited
  probe("control: cube months 6:9, 2023, parallel 4", "returned", function(cache)
    dft_stac_cube(aoi, index = "ndvi", datetime = "2023-01-01/2023-12-31",
                  months = 6:9, parallel = 4, cache_dir = cache)),
  probe("control: composite 2023 July, tiled 1000 m, parallel 4", "returned",
        function(cache)
          dft_stac_composite(aoi, years = 2023, months = 7, bands = "red",
                             tile_size = 1000, parallel = 4, cache_dir = cache)),
  probe("control: fetch 2023 untiled", "returned", function(cache)
    dft_stac_fetch(aoi, years = 2023, cache_dir = cache))
)
say(sum(results), " of ", length(results), " as expected")

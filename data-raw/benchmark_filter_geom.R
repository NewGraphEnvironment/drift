# Benchmark: does gdalcubes::filter_geom() actually bound the read? (drift#47)
#
# #47 proposes replacing dft_stac_cube()'s bbox read + output-side terra::mask()
# with gdalcubes::filter_geom(), claiming ~10x from AOI/bbox = 0.105 on the
# packaged AOI. Reading the fork's filter_geom.cpp shows the skip happens at
# CHUNK granularity -- read_chunk() returns an empty chunk without calling
# _in_cube->read_chunk(id) -- and gdalcubes' default_chunksize() targets only
# 2 * parallel spatial chunks, which on this AOI is a 2x2 grid. So the claim is
# unestablished and this script measures it instead of inferring it.
#
# Cost is OBSERVED, not derived from chunk arithmetic: each arm runs in its own
# subprocess with CPL_CURL_VERBOSE=YES and stderr to its own file, and we count
# the HTTP range requests GDAL actually issued.
#
# Usage:
#   Rscript data-raw/benchmark_filter_geom.R           # drive every arm
#   Rscript data-raw/benchmark_filter_geom.R <arm>     # run one arm (internal)
#
# Requires network + the fixed gdalcubes
# (NewGraphEnvironment/gdalcubes@newgraph; CRAN 0.7.4 segfaults on filter_geom).

suppressMessages({
  library(sf)
  library(terra)
  # load_all() unconditionally, and call drift's own helpers unqualified: a
  # `drift::`/`drift:::` here would reach the INSTALLED namespace, which is a
  # different copy of the package from the one being benchmarked.
  pkgload::load_all(".", quiet = TRUE)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- arm definitions ------------------------------------------------------
# pad_px: filter_geom's constructor throws "Polygon must be located completely
# within the data cube" when the polygon touches the cube edge, which drift's
# extent (= st_bbox(aoi)) always does. Measured offline: 0 px throws, 1 px works.
ARMS <- list(
  A_bbox_mask   = list(filter_geom = FALSE, chunking = NULL,          tile_size = NULL, pad_px = 0),
  B_fg_default  = list(filter_geom = TRUE,  chunking = NULL,          tile_size = NULL, pad_px = 2),
  C_fg_64       = list(filter_geom = TRUE,  chunking = c(1, 64, 64),  tile_size = NULL, pad_px = 2),
  C_fg_128      = list(filter_geom = TRUE,  chunking = c(1, 128, 128), tile_size = NULL, pad_px = 2),
  D_tile_640    = list(filter_geom = FALSE, chunking = NULL,          tile_size = 640,  pad_px = 0),
  # The rival hypothesis, and it is untested: drift never calls
  # gdalcubes_options() (grep -rn gdalcubes_options R/ -> 0 hits), so every
  # fetch is single-threaded AND gets coarse chunks, because default_chunksize()
  # reads .pkgenv$parallel. Raising it gives concurrent reads and finer chunks
  # for free. If this beats every filter_geom arm, #47 is moot and the answer is
  # one line -- no fork, no probe, no cache question.
  E_par4        = list(filter_geom = FALSE, chunking = NULL,          tile_size = NULL, pad_px = 0, parallel = 4),
  E_par8        = list(filter_geom = FALSE, chunking = NULL,          tile_size = NULL, pad_px = 0, parallel = 8)
)

# a short but real read: one growing season, monthly
SOURCE   <- "sentinel-2-l2a"
INDEX    <- "kndvi"
DATETIME <- "2019-01-01/2019-12-31"
MONTHS   <- 6:9
RES      <- 10

out_dir <- file.path("data-raw", "logs", "benchmark_filter_geom")

# ---------------------------------------------------------------------------
# One arm. Replicates dft_stac_cube()'s gdalcubes chain directly rather than
# calling it, because (a) arms B/C need a filter_geom the package does not yet
# have, and (b) going through dft_stac_cube() would hit its cache.
# ---------------------------------------------------------------------------
run_arm <- function(arm_name) {
  suppressMessages(library(gdalcubes))
  arm <- ARMS[[arm_name]]
  if (is.null(arm)) stop("unknown arm: ", arm_name)
  if (!is.null(arm$parallel)) {
    gdalcubes::gdalcubes_options(parallel = arm$parallel)
    message("  parallel: ", arm$parallel)
  }

  aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"),
                     quiet = TRUE)
  cfg <- dft_stac_config(SOURCE)

  target_crs <- auto_utm_epsg(aoi)
  aoi_wgs84  <- sf::st_transform(aoi, 4326)
  aoi_target <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))
  bbox       <- sf::st_bbox(aoi_target)

  roles_needed <- index_roles(INDEX)
  band_assets  <- unlist(cfg$roles[roles_needed], use.names = FALSE)
  mask_asset   <- cfg$roles$mask

  items <- rstac::stac(cfg$stac_url) |>
    rstac::stac_search(
      collections = cfg$collection,
      intersects  = sf::st_geometry(sf::st_union(aoi_wgs84))[[1]],
      datetime    = DATETIME,
      limit       = 500
    ) |>
    rstac::ext_filter(`eo:cloud_cover` <= 60) |>
    rstac::post_request() |>
    rstac::items_fetch() |>
    rstac::items_sign(sign_fn = rstac::sign_planetary_computer())

  item_dt <- vapply(items$features,
                    function(f) f$properties$datetime %||% NA_character_, "")
  item_mo <- as.integer(format(as.Date(substr(item_dt, 1, 10)), "%m"))
  items$features <- items$features[!is.na(item_mo) & item_mo %in% MONTHS]
  message("  items: ", length(items$features))

  # 2019 is entirely pre-boundary (S2 +1000 DN flips 2022-01-25), so a single
  # offset applies and there is no pre/post cover() split to confound the read.
  offset_use <- cfg$offset_before %||% 0

  build <- function(ext) {
    v <- gdalcubes::cube_view(
      srs    = target_crs,
      extent = list(left = ext$left, right = ext$right,
                    bottom = ext$bottom, top = ext$top,
                    t0 = "2019-01-01", t1 = "2019-12-31"),
      dx = RES, dy = RES, dt = "P1M",
      aggregation = "median", resampling = "bilinear"
    )
    ic <- gdalcubes::stac_image_collection(
      items$features, asset_names = c(band_assets, mask_asset)
    )
    rc_args <- list(ic, v,
                    mask = gdalcubes::image_mask(mask_asset,
                                                 values = cfg$mask_values))
    if (!is.null(arm$chunking)) rc_args$chunking <- arm$chunking
    cube <- do.call(gdalcubes::raster_cube, rc_args)

    if (isTRUE(arm$filter_geom)) {
      cube <- gdalcubes::filter_geom(
        cube,
        sf::st_union(sf::st_geometry(aoi_target)),
        srs = target_crs
      )
    }
    idx <- dft_index_expr(cube, index = INDEX, source = SOURCE,
                                 roles = cfg$roles, scale = cfg$scale %||% 1,
                                 offset = offset_use)
    tmp <- tempfile(fileext = ".nc")
    gdalcubes::write_ncdf(idx, tmp, overwrite = TRUE)
    terra::rast(tmp)
  }

  pad <- arm$pad_px * RES
  t_start <- Sys.time()
  if (is.null(arm$tile_size)) {
    stk <- build(list(left = bbox[["xmin"]] - pad, right  = bbox[["xmax"]] + pad,
                      bottom = bbox[["ymin"]] - pad, top   = bbox[["ymax"]] + pad))
  } else {
    tiles <- tile_grid(aoi_target, arm$tile_size, RES)
    message("  tiles: ", length(tiles))
    stk <- mosaic_stacks(lapply(tiles, build))
  }
  # Arms that do not push the polygon into the read still owe the output clip.
  #
  # NOTE these two clips are NOT the same rule, and the difference is a finding
  # rather than a flaw in the harness: terra::mask() defaults to
  # `touches = TRUE` (every cell the polygon touches) while filter_geom()
  # rasterizes at CELL CENTRE. Measured here: 49,244 non-NA cells on the mask
  # arms against 41,608 on the filter_geom arms -- a 15.5% difference in the
  # analysed footprint with no bearing on the read. So `n_nonna` is comparable
  # WITHIN a clip rule and not across, while `requests`/`elapsed_s` -- what this
  # benchmark exists to measure -- are comparable throughout.
  #
  # To equalise them, buffer the filter_geom polygon by >= res*sqrt(2)/2 and
  # mask unconditionally; that is the shape the package should adopt if it ever
  # takes this path, precisely so the footprint does not move.
  if (!isTRUE(arm$filter_geom)) stk <- terra::mask(stk, terra::vect(aoi_target))
  elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))

  out_tif <- file.path(out_dir, paste0(arm_name, ".tif"))
  terra::writeRaster(stk, out_tif, overwrite = TRUE)

  saveRDS(
    list(arm = arm_name, elapsed_s = elapsed,
         nlyr = terra::nlyr(stk), ncell = terra::ncell(stk),
         n_nonna = sum(!is.na(terra::values(stk))),
         ext = as.vector(terra::ext(stk)), tif = out_tif),
    file.path(out_dir, paste0(arm_name, ".rds"))
  )
  message("  done in ", round(elapsed, 1), "s")
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Driver: one subprocess per arm, stderr to its own file so GDAL's curl verbose
# (and any worker-process crash) is captured without corrupting stdout. Never
# merge the two -- a chatty stderr lands mid-line in stdout and breaks parsing.
# ---------------------------------------------------------------------------
count_requests <- function(err_file) {
  if (!file.exists(err_file)) return(NA_integer_)
  lines <- readLines(err_file, warn = FALSE)
  # curl verbose echoes each outgoing request header; a COG read is a ranged GET,
  # so one "Range: bytes=" line is one range request. Matched unanchored because
  # GDAL prefixes it differently across versions ("> " from raw curl, a "HTTP: "
  # prefix when routed through CPLDebug) -- an anchored pattern that silently
  # matches nothing would report 0 requests, which reads as a clean result.
  sum(grepl("Range: bytes=", lines, fixed = TRUE))
}

count_bytes <- function(err_file) {
  if (!file.exists(err_file)) return(NA_real_)
  l <- readLines(err_file, warn = FALSE)
  m <- regmatches(l, regexpr("Range: bytes=[0-9]+-[0-9]+", l))
  if (!length(m)) return(0)
  ab <- do.call(rbind, lapply(strsplit(sub("Range: bytes=", "", m), "-"), as.numeric))
  sum(ab[, 2] - ab[, 1] + 1)
}

arm_row <- function(arm_name, status, res, err) {
  data.frame(
    arm       = arm_name,
    status    = status,
    ok        = !is.null(res),
    elapsed_s = if (is.null(res)) NA_real_ else round(res$elapsed_s, 1),
    requests  = count_requests(err),
    mb        = round(count_bytes(err) / 1024^2, 1),
    nlyr      = if (is.null(res)) NA_real_ else res$nlyr,
    ncell     = if (is.null(res)) NA_real_ else res$ncell,
    n_nonna   = if (is.null(res)) NA_real_ else res$n_nonna,
    stringsAsFactors = FALSE
  )
}

drive <- function() {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  rscript <- file.path(R.home("bin"), "Rscript")
  self <- file.path("data-raw", "benchmark_filter_geom.R")

  rows <- lapply(names(ARMS), function(arm_name) {
    err <- file.path(out_dir, paste0(arm_name, ".stderr.log"))
    out <- file.path(out_dir, paste0(arm_name, ".stdout.log"))
    rds_done <- file.path(out_dir, paste0(arm_name, ".rds"))
    if (file.exists(rds_done) && !identical(Sys.getenv("BENCH_FORCE"), "true")) {
      message("=== ", arm_name, " (cached) ===")
      return(arm_row(arm_name, 0L, readRDS(rds_done), err))
    }
    message("=== ", arm_name, " ===")
    status <- system2(
      rscript, c(shQuote(self), shQuote(arm_name)),
      stdout = out, stderr = err,
      # MULTIPLEX=NO (drift's own tuning sets YES) so each range request is one
      # legible curl transaction. Applied to every arm, so the comparison holds
      # even though the absolute numbers are not production's.
      env = c("CPL_CURL_VERBOSE=YES", "GDAL_HTTP_MULTIPLEX=NO")
    )
    rds <- file.path(out_dir, paste0(arm_name, ".rds"))
    # a wrapper's exit 0 is not the work completing, and a crashed worker leaves
    # no rds -- gate on the artifact, not on the status alone
    res <- if (status == 0L && file.exists(rds)) readRDS(rds) else NULL
    arm_row(arm_name, status, res, err)
  })

  tab <- do.call(rbind, rows)
  base <- tab$requests[tab$arm == "A_bbox_mask"]
  # a 0 baseline means the counter or the run is broken, not that the read was
  # free -- reporting it as an NA column reads as "no data" rather than "the
  # instrument failed"
  if (length(base) != 1 || is.na(base) || base == 0) {
    stop("baseline arm counted ", base, " range requests -- the instrument or ",
         "the run is broken, not a result")
  }
  tab$req_vs_A <- round(tab$requests / base, 3)
  tab$mb_vs_A <- round(tab$mb / tab$mb[tab$arm == "A_bbox_mask"], 3)
  print(tab, row.names = FALSE)
  write.csv(tab, file.path(out_dir, "summary.csv"), row.names = FALSE)
  message("\nwrote ", file.path(out_dir, "summary.csv"))
  invisible(tab)
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 1L) run_arm(args[[1]]) else drive()

#' Fetch a masked spectral-index cube from a STAC catalog
#'
#' Sibling of [dft_stac_fetch()] for continuous change detection. Where
#' [dft_stac_fetch()] materializes one categorical raster per year, this builds
#' a sub-annual reflectance cube, masks clouds, computes a spectral index over
#' band roles, and returns the index time series as a `SpatRaster` (one layer
#' per time step) — the input to [dft_rast_break()] for per-pixel trajectory
#' breakpoint detection.
#'
#' The index stack is materialized once to a GeoTIFF under [dft_cache_path()]
#' as `<source>/cube_<key>.tif`, keyed by a hash of the AOI geometry and every
#' cube-affecting parameter (including `clip` and `tile_size`, so a tiled read
#' keys apart from an untiled one). Because it is invariant to [dft_rast_break()]'s
#' parameters, caching it here makes bfast parameter sweeps cheap — they re-read
#' the local raster instead of re-streaming COGs.
#'
#' Three STAC-query specifics distinguish cube mode from [dft_stac_fetch()]:
#' pagination via [rstac::items_fetch()] is mandatory (a monthly multi-year query
#' returns hundreds of items; a single page silently truncates); the query uses
#' `intersects` with the AOI geometry, not a bounding box (floodplain polygons
#' are highly non-rectangular); and a scene-level `eo:cloud_cover` pre-filter
#' shrinks the collection before any pixel is read, complementing per-pixel mask
#' filtering.
#'
#' @param aoi An `sf` polygon defining the area of interest.
#' @param source Character. A cube source name for [dft_stac_config()] (default
#'   `"sentinel-2-l2a"`). Must be a source with `cube = TRUE`.
#' @param index Character. Spectral index from [dft_index_table()] (default
#'   `"kndvi"`). Determines which band roles (and thus assets) are fetched.
#' @param datetime Character. ISO 8601 interval `"start/end"`. When `NULL`, uses
#'   `available_datetime` from [dft_stac_config()].
#' @param res Numeric. Output pixel size in CRS units (default 10).
#' @param crs Character. Target CRS as an EPSG string. When `NULL`, auto-detected
#'   from the AOI centroid's UTM zone.
#' @param dt Character. ISO 8601 duration for the temporal aggregation window
#'   (default `"P1M"`, monthly). The cadence [dft_rast_break()]'s `frequency`
#'   must agree with.
#' @param aggregation Character. Temporal aggregation for multiple scenes in one
#'   `dt` window (default `"median"`).
#' @param resampling Character. Spatial resampling (default `"bilinear"`).
#' @param clip Logical. When `TRUE` (default), clip the returned stack to the AOI
#'   polygon with `terra::mask()`, so
#'   [dft_rast_break()] / [dft_rast_trend()] reduce only in-polygon pixels. The
#'   clip keeps every cell the polygon **touches** — `terra::mask()` defaults to
#'   `touches = TRUE` — so it is inclusive at the boundary by up to one cell,
#'   deliberately, so a thin corridor is not eroded. Cells the polygon does not
#'   touch become `NA` on every layer. That is a *different* rule from a
#'   cell-centre clip, and worth 15.5% of the analysed footprint on the packaged
#'   AOI (#47), so it matters to anything reporting boundary hectares. Set
#'   `FALSE` to keep the wider extent (e.g. for surrounding context, or to mask
#'   later with a different polygon). This clips the *output* — with the default
#'   `tile_size = NULL` the full bbox of COGs is still streamed either way, so
#'   `clip = FALSE` returns the full bounding box. When `tile_size` is set the read
#'   is tiled, so `clip = FALSE` returns the **AOI-intersecting tile union** (a
#'   stair-stepped superset of the polygon with `NA` where empty tiles were
#'   skipped), not a gap-free bounding box.
#' @param cloud_cover_max Numeric. Scene-level `eo:cloud_cover` maximum percent
#'   for the STAC pre-filter (default 60).
#' @param months Integer vector of calendar months (1-12) to keep, or `NULL`
#'   (default) for all. Restricting to the growing season (e.g. `6:9`) both
#'   sharpens the vegetation signal — snow and low-sun winter scenes carry no
#'   vegetation information — and cuts the number of scenes streamed. Months with
#'   no retained scenes become `NA` in the monthly cube, so the per-pixel series
#'   stays regular at `frequency = 12` for [dft_rast_break()]. Prefer a longer
#'   `datetime` window when using this, so enough growing-season history remains
#'   to fit a stable BFAST baseline.
#' @param mask_values Integer vector of mask-band classes to exclude. When
#'   `NULL`, uses `mask_values` from [dft_stac_config()] (e.g. Sentinel-2 SCL
#'   cloud / shadow / cirrus classes).
#' @param tile_size Numeric or `NULL` (default). Edge length, in CRS units
#'   (metres for the default UTM CRS), of the read-tiling grid (#38). When `NULL`,
#'   one cube is streamed over the whole AOI bounding box (the read scales with the
#'   bbox, not the AOI). When set, the bbox is split into a grid of `tile_size`-square
#'   tiles and only tiles that intersect the AOI polygon are streamed, then mosaicked
#'   — so a thin, diagonal AOI (e.g. a floodplain corridor) reads close to its
#'   footprint. Snapped to a multiple of `res`. Smaller tiles waste less bbox but
#'   cost more per-tile round trips; there is no auto-tuning. The cube always caches
#'   a `.tif` either way; a tiled read keys distinctly (see the caching note above),
#'   so untiled caches are untouched and `tile_size = NULL` is byte-for-byte the
#'   previous behavior. This is the continuous-path twin of [dft_stac_fetch()]'s
#'   `tile_size`. Benchmarked against the alternatives on the packaged AOI
#'   (drift#47) it is the **slowest** option — 1263.6 s and 3213 range requests
#'   against an untiled 236.8 s / 462, because every tile rebuilds the image
#'   collection and reopens the COGs — so prefer `parallel` for speed and reach
#'   for `tile_size` only when peak memory, not wall clock, is the constraint.
#'   Because the
#'   cube resamples with bilinear, a tiled cube faithfully reproduces the untiled
#'   cube (the per-pixel reducers are unaffected) but lands on a bbox-anchored grid
#'   that is sub-pixel-offset from — not pixel-identical to — the untiled cube.
#' @param parallel Integer, or `NULL` (default) to auto-detect as
#'   `min(4, cores - 1)`, flooring to 1 where the core count is undetectable.
#'   Number of gdalcubes worker processes used for the read. The COG stream is the
#'   dominant cost and it parallelizes well: measured on the packaged AOI, a
#'   4-month monthly kNDVI cube took 236.8 s at `parallel = 1`, 115.8 s at 4 and
#'   96.0 s at 8 — and the output is **byte-identical** at every setting
#'   (correlation 1.000, max absolute difference 0), so this is a pure cost knob
#'   and does not enter the cache key. Capped at 4 by default rather than the
#'   full core count because each worker holds chunks in memory; raise it on a
#'   machine with headroom, or set `1` for the previous single-threaded
#'   behaviour. Prior to v0.9.0 drift never called
#'   [gdalcubes::gdalcubes_options()] at all, so every fetch ran single-threaded
#'   (drift#47). gdalcubes also derives its default chunk size from this value,
#'   so raising it makes chunks finer as a side effect — measured in isolation on
#'   this AOI that is a *cost* (343.7 s / 693 requests at 128 px against 236.9 s
#'   / 462 at the default), so the speedup is attributable to concurrency. When
#'   `NULL` and a session-level [gdalcubes::gdalcubes_options()] `parallel` above
#'   1 is already set, that value is honoured rather than overridden.
#' @param cache_dir Character. Cache directory. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-fetch even if cached, replacing the cached raster
#'   (default `FALSE`). The replacement is atomic, so an interrupted forced
#'   re-fetch leaves the previous entry intact rather than destroying it — which
#'   matters here, where rebuilding is a multi-hour stream.
#' @param sign_fn A signing function for STAC assets. Default is
#'   [rstac::sign_planetary_computer()].
#'
#' @return A [terra::SpatRaster] index stack — one layer per time step, with a
#'   time value per layer — cached as a GeoTIFF. By default (`clip = TRUE`) the
#'   stack is clipped to the AOI polygon (cloud-masked; every cell the polygon
#'   touches is kept, cells it does not touch are `NA` — see `clip`), so the
#'   reduced raster from [dft_rast_break()] is already polygon-tight;
#'   pass `clip = FALSE` for the full AOI **bounding box** (or, with `tile_size`
#'   set, the AOI-intersecting tile union). For sources with a
#'   reflectance-offset baseline boundary (Sentinel-2), items are split at the
#'   boundary and offset-corrected per side, so a series crossing it carries no
#'   artificial index step.
#'
#' @seealso [dft_rast_break()] (the reducer that consumes this cube),
#'   [dft_index_expr()] (the index applied), [dft_stac_fetch()] (categorical
#'   sibling).
#'
#' @examples
#' \dontrun{
#' # Monthly kNDVI cube for a floodplain reach (requires network + gdalcubes)
#' aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
#' cube <- dft_stac_cube(
#'   aoi,
#'   source   = "sentinel-2-l2a",
#'   index    = "kndvi",
#'   datetime = "2019-01-01/2023-12-31",
#'   dt       = "P1M"
#' )
#' breaks <- dft_rast_break(cube, start = c(2022, 1))
#' }
#'
#' @export
dft_stac_cube <- function(aoi,
                          source = "sentinel-2-l2a",
                          index = "kndvi",
                          datetime = NULL,
                          res = 10,
                          crs = NULL,
                          dt = "P1M",
                          aggregation = "median",
                          resampling = "bilinear",
                          clip = TRUE,
                          cloud_cover_max = 60,
                          months = NULL,
                          mask_values = NULL,
                          tile_size = NULL,
                          parallel = NULL,
                          cache_dir = NULL,
                          force = FALSE,
                          sign_fn = rstac::sign_planetary_computer()) {
  check_gdalcubes("to fetch STAC cubes")
  aggregation <- aggregation_check(aggregation)

  # gdalcubes worker count and GDAL /vsicurl tuning, both restored on exit so
  # the caller's session is untouched (see stac_cube_session()).
  restore_session <- stac_cube_session(parallel)
  on.exit(restore_session(), add = TRUE)

  cfg <- dft_stac_config(source)
  if (!isTRUE(cfg$cube)) {
    cli::cli_abort(c(
      "Source {.val {source}} is not a cube source.",
      "i" = "Use {.fn dft_stac_fetch} for categorical rasters."
    ))
  }
  datetime <- datetime %||% cfg$available_datetime
  mask_values <- mask_values %||% cfg$mask_values
  scale <- cfg$scale %||% 1
  offset <- cfg$offset %||% 0
  # sources whose reflectance offset changes at a processing-baseline boundary
  # (e.g. Sentinel-2 +1000 DN from 2022-01-25) carry the boundary date and the
  # pre-boundary offset; the fetch splits items at the boundary and corrects
  # each side, so a series crossing it has no artificial index step.
  offset_before <- cfg$offset_before %||% 0
  # normalize clip to a single scalar so the mask gate and the cache key agree: a
  # truthy-but-non-TRUE clip (e.g. 1 or "TRUE") must not skip the mask yet key as
  # TRUE, which would let a later clip=TRUE read the unclipped cube (#32).
  clip <- isTRUE(as.logical(clip))
  # normalize tile_size ONCE (snap to a multiple of res) so the path gate
  # (is.null) and the cache-key append derive from the same scalar (#36/#38).
  # tile_size_check() is the shared download-tiling helper from #36.
  if (!is.null(tile_size)) tile_size <- tile_size_check(tile_size, res)

  # Ensure aoi is sf
  if (inherits(aoi, "SpatVector")) aoi <- sf::st_as_sf(aoi)
  stopifnot(inherits(aoi, c("sf", "sfc")))

  target_crs <- if (is.null(crs)) auto_utm_epsg(aoi) else crs
  aoi_wgs84 <- sf::st_transform(aoi, 4326)
  aoi_target <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))

  # Assets: the index's required roles + the mask role (index_roles errors on
  # an unknown index before any network call)
  roles_needed <- index_roles(index)
  band_assets <- unlist(cfg$roles[roles_needed], use.names = FALSE)

  # datetime interval -> cube_view time bounds
  dr <- strsplit(datetime, "/", fixed = TRUE)[[1]]
  if (length(dr) != 2) {
    cli::cli_abort("`datetime` must be an ISO 8601 interval {.val start/end}.")
  }

  # Cache
  # <base>/<scheme>/<source> (#48); recursive = TRUE required for the extra level
  cache_source_dir <- cache_scheme_dir(cache_dir, source)
  dir.create(cache_source_dir, recursive = TRUE, showWarnings = FALSE)
  cache_key <- stac_cube_cache_key(
    aoi_target, res, target_crs, dt, aggregation, resampling,
    cfg$stac_url, cfg$collection, band_assets, datetime, index,
    cloud_cover_max, mask_values, scale, offset, months, offset_before, clip,
    tile_size
  )
  cache_file <- file.path(cache_source_dir, paste0("cube_", cache_key, ".tif"))

  # monthly layer times, derived from the datetime window start
  month_times <- function(n) {
    seq(as.Date(paste0(substr(dr[1], 1, 7), "-01")), by = "month", length.out = n)
  }

  # Presence is not trust (#41). Validity is checked BEFORE cube_check_nonempty()
  # so a truncated file that happens to read all-NA is reported as corrupt rather
  # than as "your AOI does not overlap the collection" — the two have opposite
  # remedies, which is also why they stay separate functions: an empty cube
  # aborts (re-fetching will not fix a genuine AOI/datetime mismatch), a corrupt
  # one re-fetches.
  if (!force && file.exists(cache_file) && cache_hit_ok(cache_file, "cube")) {
    r <- stac_cube_cache_read(cache_file, cfg$collection, datetime)
    if (!is.null(r)) {
      message("  cube: cached")
      terra::time(r) <- month_times(terra::nlyr(r))
      return(r)
    }
  }

  fetched <- stac_cube_items(cfg, aoi_wgs84, datetime, cloud_cover_max,
                             months, sign_fn)

  # The index is applied per offset side: the pixel function receives the
  # offset for the item subset it is building (see stac_cube_assemble()).
  pixel_fn <- function(cube, offset_use) {
    dft_index_expr(cube, index = index, source = source,
                   roles = cfg$roles, scale = scale, offset = offset_use)
  }
  stk <- stac_cube_assemble(
    fetched, cfg, aoi_target, target_crs, t0 = dr[1], t1 = dr[2], res = res,
    dt = dt, aggregation = aggregation, resampling = resampling,
    band_assets = band_assets, mask_values = mask_values,
    offset = offset, offset_before = offset_before, pixel_fn = pixel_fn,
    tile_size = tile_size
  )

  # Restore the AOI-polygon clip removed in #30: mask the assembled stack. Cells
  # the polygon does not touch become NA on every layer (terra::mask() defaults
  # to touches = TRUE, so the boundary is inclusive by up to one cell), so
  # dft_rast_break()/dft_rast_trend() skip them via their
  # `rowSums(!is.na) >= min_obs` gate. `mask` preserves nlyr and time is set
  # below, so the cached tif — and the cache-read path — need no other change.
  if (isTRUE(clip)) stk <- stac_cube_clip(stk, aoi_target)

  # Post-condition before anything is cached: a cube with no data at all is the
  # gdalcubes all-NA failure mode (#32/#47), and it is SILENT — nothing upstream
  # raises, and a cached empty cube is then served for every later call with the
  # same key. Cheap to check, and the only place it can be caught on the real
  # network path rather than in a fixture.
  #
  # The whole stack, NOT layer 1: an individual layer being empty is DOCUMENTED
  # behaviour, not a fault. `months` keeps the series regular by leaving months
  # with no retained scenes as NA, so the packaged `months = 6:9` example has
  # eight all-NA layers and January first. Checking layer 1 would abort the
  # vignette's own call after the full COG stream.
  cube_check_nonempty(stk, cfg$collection, datetime, cached = FALSE)

  terra::time(stk) <- month_times(terra::nlyr(stk))
  names(stk) <- rep(index, terra::nlyr(stk))
  # Atomic publish (#41). Losing this cache to an interrupted write is far more
  # expensive here than in dft_stac_fetch() — it is a multi-hour Sentinel-2
  # stream rather than a small annual raster.
  cache_write_atomic(cache_file, function(out) {
    terra::writeRaster(stk, out, overwrite = TRUE)
  })
  stk
}


# The aggregations drift passes to gdalcubes::cube_view(). gdalcubes 0.7.5
# lower-cases the string and maps anything it does not know to "none" without
# error, which is how "count" came back as reflectance (#92). Measured by
# round-tripping each value through cube_view()$aggregation: the six below
# survive. It also honours "count_values" and "count_images", which are held back
# on purpose: they count items, so overlapping MGRS tiles double-count one
# acquisition, and every caller here would then apply a reflectance scale or an
# index expression to a count. "none" is the silent fallback itself.
.cube_view_aggregations <- c("min", "max", "mean", "median", "first", "last")

#' Refuse an `aggregation` outside `allowed`, before any network call
#'
#' Shared by [dft_stac_fetch()], [dft_stac_cube()] and [dft_stac_composite()],
#' the three callers of `gdalcubes::cube_view()`. An unsupported value is not
#' refused downstream, so it has to be refused here (#92). Matching ignores case,
#' as gdalcubes does, and the value is returned lower-cased so `"Median"` and
#' `"median"` share a cache key.
#' @noRd
aggregation_check <- function(aggregation, allowed = .cube_view_aggregations) {
  if (!is.character(aggregation) || length(aggregation) != 1L ||
        is.na(aggregation) || !tolower(aggregation) %in% allowed) {
    cli::cli_abort(c(
      "{.arg aggregation} must be one of {.or {.val {allowed}}}.",
      "x" = if (is.character(aggregation) && length(aggregation) == 1L &&
                  !is.na(aggregation)) {
        "Got {.val {aggregation}}. gdalcubes reads a value it does not know as \\
         {.val none} without an error, so drift passes only these."
      } else {
        "Got {.obj_type_friendly {aggregation}}."
      }
    ), class = "drift_bad_aggregation")
  }
  tolower(aggregation)
}


#' Set the gdalcubes worker count and GDAL cloud-read tuning for a cube read
#'
#' Shared by [dft_stac_cube()] and [dft_stac_composite()]. Returns a function
#' that restores the caller's session, which the caller registers with
#' `on.exit(restore(), add = TRUE)`: an `on.exit()` here would fire when this
#' helper returns, not when the read finishes.
#'
#' gdalcubes worker processes: drift never set this before v0.9.0, so every
#' fetch ran single-threaded — not a considered choice, just the consequence of
#' never calling gdalcubes_options(). Measured 2.05x at 4 and 2.47x at 8 on the
#' packaged AOI, with byte-identical output at every setting (drift#47), so it
#' is a pure cost knob and stays out of the cache key. The gain is CONCURRENCY,
#' not the finer chunking it also causes: arms that isolate chunk size at
#' parallel = 1 measured finer chunks 45% SLOWER.
#'
#' GDAL cloud-read tuning for /vsicurl COG streaming (biggest win:
#' DISABLE_READDIR_ON_OPEN avoids a remote directory listing on every open).
#' @noRd
stac_cube_session <- function(parallel) {
  old_parallel <- gdalcubes::gdalcubes_options()$parallel
  parallel <- cube_parallel_check(parallel, session = old_parallel)
  gdalcubes::gdalcubes_options(parallel = parallel)

  gdal_cfg <- c(
    GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR",
    GDAL_HTTP_MULTIPLEX = "YES",
    GDAL_HTTP_VERSION = "2",
    VSI_CACHE = "TRUE",
    CPL_VSIL_CURL_ALLOWED_EXTENSIONS = ".tif"
  )
  old_cfg <- Sys.getenv(names(gdal_cfg), unset = NA)
  do.call(Sys.setenv, as.list(gdal_cfg))

  function() {
    gdalcubes::gdalcubes_options(parallel = old_parallel)
    set_again <- old_cfg[!is.na(old_cfg)]
    if (length(set_again)) do.call(Sys.setenv, as.list(set_again))
    unset <- names(old_cfg)[is.na(old_cfg)]
    if (length(unset)) Sys.unsetenv(unset)
    invisible()
  }
}


#' Read a cached cube-family raster, or return NULL if its pixels are unreadable
#'
#' The cache-read half of [dft_stac_cube()] and [dft_stac_composite()], called
#' after `cache_hit_ok()` has passed. Guards the READ path too, not only the
#' write. A cube written by an earlier version could be all-NA — drift's
#' end-to-end test passed on exactly that (#47) — and the cache key is
#' unchanged, so upgrading does not invalidate it. Without this the empty cube
#' is served silently and, under `force = FALSE`, permanently.
#'
#' The warning handler makes this a WHOLE-FILE read probe at zero added cost:
#' cube_check_nonempty() already scans every pixel via terra::global(), and a
#' GDAL read failure surfaces as a warning while global() happily returns a
#' number computed from whatever it got. That is strictly stronger than the
#' last-row probe cache_hit_ok() just ran, and the cube is the path where it
#' matters most — its cache is a multi-hour stream, not an annual raster.
#'
#' An all-`NA` cache still ABORTS (via cube_check_nonempty()); only an unclean
#' read returns `NULL`, which the caller treats as a miss and re-fetches.
#' @noRd
stac_cube_cache_read <- function(cache_file, collection, datetime,
                                 label = "cube") {
  r <- terra::rast(cache_file)
  read_dirty <- FALSE
  withCallingHandlers(
    cube_check_nonempty(r, collection, datetime, cached = TRUE),
    warning = function(w) {
      read_dirty <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  if (!read_dirty) return(r)
  cli::cli_warn(c(
    "The cached {label}'s pixel data could not be read cleanly; re-fetching.",
    "i" = "{.file {cache_file}}"
  ))
  NULL
}


#' Query the STAC items for a cube read and split them at the offset boundary
#'
#' Shared by [dft_stac_cube()] and [dft_stac_composite()]. Three STAC-query
#' specifics: pagination via [rstac::items_fetch()] is mandatory (a monthly
#' multi-year query returns hundreds of items; a single page silently
#' truncates); the query uses `intersects` with the AOI geometry, not a bounding
#' box; and a scene-level `eo:cloud_cover` pre-filter shrinks the collection
#' before any pixel is read.
#'
#' @return A list with `features` (the signed, month-filtered STAC features),
#'   `is_pre` (logical, one per feature: acquired before `cfg$offset_boundary`),
#'   and `items` and `sign_fn`, which stac_cube_assemble() uses to re-sign the
#'   features before each read extent (see there).
#' @noRd
stac_cube_items <- function(cfg, aoi_wgs84, datetime, cloud_cover_max, months,
                            sign_fn) {
  message("Querying STAC: ", cfg$collection, " (", datetime, ")...")
  items <- rstac::stac(cfg$stac_url) |>
    rstac::stac_search(
      collections = cfg$collection,
      # union so a multi-feature AOI queries its whole footprint, matching the
      # cube extent and the terra::mask() clip (a single first-feature geometry
      # would leave silent NoData holes over the other features)
      intersects = stac_query_geometry(aoi_wgs84),
      datetime = datetime,
      limit = 500
    ) |>
    rstac::ext_filter(`eo:cloud_cover` <= {{cloud_cover_max}}) |>
    rstac::post_request() |>
    rstac::items_fetch() |>
    rstac::items_sign(sign_fn = sign_fn)

  # Restrict to growing-season (or any) calendar months. Fetching fewer, better
  # months both sharpens the vegetation signal (drops snow/low-sun winter noise)
  # and cuts the number of scenes streamed. Months with no scenes become NA in
  # the monthly cube, so the ts() stays regular at frequency 12.
  if (!is.null(months)) {
    item_dt <- vapply(items$features, function(f) f$properties$datetime %||% NA_character_, "")
    item_mo <- as.integer(format(as.Date(substr(item_dt, 1, 10)), "%m"))
    items$features <- items$features[!is.na(item_mo) & item_mo %in% months]
  }

  n_items <- length(items$features)
  message("  ", n_items, " items returned")
  if (n_items == 0) {
    # Classed so a multi-year caller can skip an empty year; the message is the
    # one this has always raised.
    rlang::abort(paste0("No STAC items found for ", cfg$collection),
                 class = "drift_no_items")
  }

  # Baseline-conditional offset: split items at the boundary so each side is
  # corrected with its own offset. The split is by item date, so it is the same
  # for every read extent — compute it (and announce it) once, before
  # assembling any cube.
  is_pre <- rep(FALSE, length(items$features))
  if (!is.null(cfg$offset_boundary)) {
    item_date <- as.Date(substr(
      vapply(items$features, function(f) f$properties$datetime %||% NA_character_, ""),
      1, 10
    ))
    is_pre <- !is.na(item_date) & item_date < as.Date(cfg$offset_boundary)
  }
  if (any(is_pre) && !all(is_pre)) {
    message("  offset split at ", cfg$offset_boundary, ": ",
            sum(is_pre), " pre / ", sum(!is_pre), " post")
  }
  list(features = items$features, is_pre = is_pre, items = items,
       sign_fn = sign_fn)
}


#' Re-sign STAC features just before they are read
#'
#' Planetary Computer SAS tokens last about 45 minutes (measured 2026-09-28:
#' a token issued at 17:16:55Z expired at 18:01:55Z), and signing happens once,
#' at query time. A tiled read over a floodplain outlasts that: on BULK (#79)
#' 15 of 30 tiles came back with every chunk failed. rstac's signer refreshes an
#' expired token and replaces the `sig` parameter of an already-signed href, so
#' re-signing before each extent keeps every read inside a live token (verified
#' live: features with a corrupted `sig` read 102,364 cells after re-signing, 0
#' without). A single extent whose read outlives one token is still exposed, and
#' gdalcubes reports a failed chunk only on the worker's stderr, which R cannot
#' reliably capture (#87). A `fetched` without `sign_fn` (a test stub) passes
#' through unchanged.
#' @noRd
stac_features_resign <- function(fetched, feats) {
  if (is.null(fetched$sign_fn) || is.null(fetched$items) || !length(feats)) {
    return(feats)
  }
  it <- fetched$items
  it$features <- feats
  rstac::items_sign(it, sign_fn = fetched$sign_fn)$features
}



#' The geometry sent as a STAC `intersects` query: the AOI union, or its hull
#'
#' Planetary Computer rejects a search whose POST body is over about 1 MiB with
#' HTTP 413 (measured 2026-09-28, #79: accepted at 21,348 vertices / 860 KB of
#' GeoJSON, rejected at 26,508 / 1.07 MB). A floodplain polygon crosses that
#' easily; BULK's is 104,584 vertices (4.2 MB), so neither dft_stac_cube() nor
#' dft_stac_composite() could query it at all. Above `max_vertices` the query
#' uses the convex hull instead. That is a superset, so no scene over the AOI is
#' lost; the extra scenes it admits lie outside the AOI, gdalcubes reads only
#' images overlapping the view, and the output is clipped, so pixels over the AOI
#' are unchanged. At or below the threshold the query is exactly the union, as
#' before, so any AOI that could be queried until now gets the same item set.
#' @noRd
stac_query_geometry <- function(aoi_wgs84, max_vertices = 20000L) {
  u <- sf::st_union(aoi_wgs84)
  n <- nrow(sf::st_coordinates(u))
  if (n > max_vertices) {
    message("  AOI has ", n, " vertices; querying its convex hull (STAC body limit)")
    u <- sf::st_convex_hull(u)
  }
  sf::st_geometry(u)[[1]]
}

#' Assemble a masked cube stack over the AOI, tiled or not
#'
#' Shared by [dft_stac_cube()] and [dft_stac_composite()]; the two differ only in
#' `pixel_fn`, which turns the masked reflectance cube for one item subset into
#' the bands to keep (an index for the cube, scaled reflectance for the
#' composite). `pixel_fn(cube, offset_use)` receives the offset for the subset
#' it is building, so each side of the offset boundary is corrected with its own.
#'
#' The cube spans the view's extent; the AOI clip happens on the output via
#' terra::mask() (stac_cube_clip, #32), as dft_stac_fetch() does — not
#' gdalcubes::filter_geom(). That is now a MEASURED choice rather than a
#' workaround (#47). The segfault was fixed in NewGraphEnvironment/gdalcubes@newgraph,
#' so filter_geom is available; it is simply not worth using. It skips whole
#' CHUNKS, and gdalcubes clamps a chunk edge to `[64, 1024]` px — coarse enough to
#' skip nothing at the default, and fine enough to break alignment with the
#' COGs' 512x512 blocks when forced down. Benchmarked on the packaged AOI:
#' default chunking 462 requests / 236.9 s against the bbox baseline's 462 /
#' 236.8 s, and 64 px chunking 693 / 348.2 s — 1.5x the requests to save 26.7%
#' of the ground. It also clips at CELL CENTRE where terra::mask() is touches =
#' TRUE, so swapping them would silently shrink the analysed footprint by 15.5%.
#' See data-raw/benchmark_filter_geom.R and inst/notes/gdalcubes-pc-gotchas.md.
#'
#' Untiled (tile_size = NULL): one cube over the AOI bounding box. Tiled (#38):
#' stream only the res-aligned tiles that intersect the AOI polygon and mosaic
#' them, so a sparse corridor reads near its footprint instead of the full bbox.
#' tile_grid()/tile_size_check() are the shared download-tiling helpers from #36
#' (defined in dft_stac_fetch.R).
#' @noRd
stac_cube_assemble <- function(fetched, cfg, aoi_target, target_crs, t0, t1,
                               res, dt, aggregation, resampling, band_assets,
                               mask_values, offset, offset_before, pixel_fn,
                               tile_size = NULL) {
  # the last point before cube_view(): an aggregation it does not honour is
  # read as "none" and returns plausible pixels (#92)
  aggregation_check(aggregation)
  mask_asset <- cfg$roles$mask
  features <- fetched$features
  is_pre <- fetched$is_pre

  # Build the masked cube for one item subset with one offset over a given
  # cube_view, materialize it, and read it back as a terra stack.
  build_stack <- function(feats, offset_use, v) {
    img_col <- gdalcubes::stac_image_collection(
      feats, asset_names = c(band_assets, mask_asset)
    )
    cube <- gdalcubes::raster_cube(
      img_col, v, mask = gdalcubes::image_mask(mask_asset, values = mask_values)
    )
    out <- pixel_fn(cube, offset_use)
    tmp <- tempfile(fileext = ".nc")
    gdalcubes::write_ncdf(out, tmp, overwrite = TRUE)
    terra::rast(tmp)
  }

  # Assemble the full masked stack for one space extent: build the cube_view
  # over that extent (same t0/t1/dt for every extent, so every tile yields the
  # same nlyr), run the offset split, and coalesce the pre/post subcubes with
  # terra::cover (both built over the same view so their layers align).
  assemble_extent <- function(extent) {
    v <- gdalcubes::cube_view(
      srs = target_crs,
      extent = list(
        left = extent$left, right = extent$right,
        bottom = extent$bottom, top = extent$top,
        t0 = t0, t1 = t1
      ),
      dx = res, dy = res, dt = dt,
      aggregation = aggregation, resampling = resampling
    )
    # re-sign here, per extent, so no read outlives its token
    feats <- stac_features_resign(fetched, features)
    if (any(is_pre) && !all(is_pre)) {
      terra::cover(
        build_stack(feats[is_pre], offset_before, v),
        build_stack(feats[!is_pre], offset, v)
      )
    } else {
      build_stack(feats, if (all(is_pre)) offset_before else offset, v)
    }
  }

  bbox_target <- sf::st_bbox(aoi_target)
  bbox_ext <- list(
    left = bbox_target[["xmin"]], right = bbox_target[["xmax"]],
    bottom = bbox_target[["ymin"]], top = bbox_target[["ymax"]]
  )
  if (is.null(tile_size)) return(assemble_extent(bbox_ext))

  tiles <- tile_grid(aoi_target, tile_size, res)
  message("  tiling read into ", length(tiles), " tile(s) intersecting the AOI")
  tile_stacks <- lapply(tiles, assemble_extent)
  # every tile shares t0/t1/dt so nlyr is uniform; guard so a future per-tile
  # time bound fails legibly here rather than deep inside terra::merge.
  # terra::nlyr() returns a double, so the vapply template is numeric(1).
  stopifnot(length(unique(vapply(tile_stacks, terra::nlyr, numeric(1)))) == 1L)
  mosaic_stacks(tile_stacks)
}


#' Abort on a cube with no data anywhere
#'
#' The gdalcubes all-`NA` failure mode (#32/#47) is SILENT — nothing upstream
#' raises. Applied on BOTH the write path and the cache-read path: a cube
#' written by an earlier version can be all-`NA`, and the cache key is unchanged,
#' so nothing would ever regenerate it under `force = FALSE`.
#'
#' Tests the whole stack, never a single layer: an individual layer being empty
#' is documented `months` behaviour (months with no retained scenes stay `NA` so
#' the series remains regular for bfast), so a per-layer test would abort the
#' packaged `months = 6:9` example.
#'
#' `terra::global()` reduces chunk-wise, so this does not materialise the stack —
#' the same reason `dft_rast_transition()` avoids `terra::values()` (#34).
#' @noRd
cube_check_nonempty <- function(stk, collection, datetime, cached) {
  if (sum(terra::global(stk, "notNA")$notNA) > 0) return(invisible(stk))
  cli::cli_abort(class = "drift_empty_cube", c(
    "The {if (cached) 'cached' else 'assembled'} cube has no data on any layer.",
    "i" = "Every cell is {.val NA} on all {terra::nlyr(stk)} layers. This is \\
           either the gdalcubes all-{.val NA} failure mode, or the AOI does \\
           not overlap {.val {collection}} for {.val {datetime}}.",
    "i" = if (cached) {
      "Delete the cached {.file .tif} under {.fn dft_cache_path}, or re-run with \\
       {.code force = TRUE}, to rebuild it."
    } else {
      "Nothing was cached. Check the AOI, {.arg datetime} and {.arg months}."
    }
  ))
}


#' Resolve the gdalcubes worker count for a cube read
#'
#' `NULL` means auto: `min(4, cores - 1)`, capped at 4 rather than the full core
#' count because each gdalcubes worker holds chunks in memory and drift has hit
#' OOM on large AOIs before (#27, #34). Measured on the packaged AOI, 4 workers
#' gave 2.05x and 8 gave 2.47x, so the last 20% costs double the memory.
#'
#' `parallel::detectCores()` returns `NA` when it cannot determine the count
#' (documented behaviour, seen in some containers), so the auto path floors to 1
#' rather than propagating `NA` into `gdalcubes_options()` — an auto default that
#' errors on an unusual machine is worse than a slow one.
#' @noRd
cube_parallel_check <- function(parallel, session = 1L) {
  if (is.null(parallel)) {
    # A caller who ran gdalcubes_options(parallel = 8) meant it. gdalcubes ships
    # 1, so anything above that is a deliberate choice and outranks our cap —
    # otherwise the auto default silently halves throughput they asked for.
    if (is.numeric(session) && length(session) == 1L && !is.na(session) &&
          session > 1) {
      return(as.integer(session))
    }
    cores <- parallel::detectCores()
    return(if (is.na(cores)) 1L else max(1L, min(4L, as.integer(cores) - 1L)))
  }
  # Shape and missingness first, so a bare NA — which is LOGICAL in R, and would
  # otherwise be reported as a flag — is named for what it is. Length is tested
  # before is.na() so a length-2 input cannot reach `||` with a length-2 test.
  if (length(parallel) != 1L || is.na(parallel)) {
    cli::cli_abort(c(
      "{.arg parallel} must be a single whole number >= 1, or {.code NULL} to auto-detect.",
      "x" = "Got {.obj_type_friendly {parallel}}."
    ))
  }
  # Reject logical explicitly. gdalcubes' own idiom elsewhere is `parallel =
  # TRUE` meaning "use all cores", and as.integer(TRUE) is 1 — so coercing it
  # would hand a caller who asked for every core the single-threaded path, the
  # exact opposite of the request, silently.
  if (is.logical(parallel)) {
    cli::cli_abort(c(
      "{.arg parallel} must be a number of worker processes, not a flag.",
      "x" = "Got {.obj_type_friendly {parallel}}.",
      "i" = "Use {.code NULL} to auto-detect, or an integer such as {.val {4L}}."
    ))
  }
  # `is.finite` and the integer ceiling BEFORE as.integer(): `trunc(Inf) == Inf`
  # and `Inf < 1` is FALSE, so Inf and anything >= 2^31 would clear a
  # whole-number test and then coerce to NA_integer_ — turning a validator into
  # a source of NA. That NA reaches gdalcubes_options() and dies as
  # "parallel >= 1 is not TRUE", naming neither this argument nor the caller.
  if (!is.numeric(parallel) || !is.finite(parallel) ||
        parallel < 1 || parallel > .Machine$integer.max ||
        parallel != trunc(parallel)) {
    cli::cli_abort(c(
      "{.arg parallel} must be a single whole number >= 1, or {.code NULL} to auto-detect.",
      "x" = "Got {.obj_type_friendly {parallel}}."
    ))
  }
  n <- as.integer(parallel)
  cores <- parallel::detectCores()
  # oversubscribing is legitimate on a network-bound read, so warn rather than
  # cap — but a typo'd 1e6 would fork the machine into the ground
  if (!is.na(cores) && n > 4L * cores) {
    cli::cli_warn(c(
      "{.arg parallel} = {n} is more than 4x the {cores} detected core{?s}.",
      "i" = "Each gdalcubes worker holds chunks in memory."
    ))
  }
  n
}


#' Clip an index stack to the AOI polygon (client-side terra mask)
#'
#' Restores AOI-polygon-tight output without `gdalcubes::filter_geom()` (see
#' `inst/notes/gdalcubes-pc-gotchas.md`, drift#32 and drift#47).
#'
#' Every cell the polygon **touches** is kept: `terra::mask()` defaults to
#' `touches = TRUE`, so the clip is inclusive at the boundary by up to one cell
#' — deliberately, so a thin corridor is not eroded. Cells the polygon does not
#' touch at all become `NA` on every layer, so [dft_rast_break()] /
#' [dft_rast_trend()] skip them via their `rowSums(!is.na) >= min_obs` gate.
#'
#' This is a *different* rule from `gdalcubes::filter_geom()`, which rasterizes
#' at cell centre and so returns a strictly smaller footprint — measured at
#' **−15.5%** on the packaged AOI (drift#47). Anything reasoning about boundary
#' hectares needs to know which rule produced the number.
#'
#' A multi-feature `aoi` masks to the union. Mirrors the post-read mask in
#' [dft_stac_fetch()]; `aoi` is already in the stack's CRS.
#' @noRd
stac_cube_clip <- function(stk, aoi) {
  terra::mask(stk, terra::vect(aoi))
}


#' Mosaic per-tile index stacks into one raster (in-memory, multi-layer)
#'
#' The reassembly step of the tiled read path (#38): each AOI-intersecting tile
#' is streamed and reduced to its own multi-layer monthly index stack, and this
#' merges them into one. Tiles are `res`-aligned and non-overlapping (see
#' `tile_grid()`), so `terra::merge()` reassembles without resampling; it merges
#' layer-by-layer positionally, so all `nlyr` layers are preserved in order
#' (layer names/time are set by the caller after the merge). Unlike the fetch
#' sibling's file-based `mosaic_tiles()`, this takes in-memory `SpatRaster`
#' stacks (a tile may be the `terra::cover()` of a pre/post offset split) and
#' returns the merged stack for the caller to clip and write. Skipped-tile gaps
#' become `NA`, so the mosaic is the tile union, not a gap-free bounding box.
#' @noRd
mosaic_stacks <- function(stacks) {
  terra::merge(terra::sprc(stacks))
}


#' Cache key for one STAC index-cube parameter set
#'
#' Cube-mode analogue of `stac_cache_key()` (kept separate so the fetch key
#' stays byte-for-byte stable). Hashes the AOI geometry as WKB plus every
#' parameter that changes the written index cube. `res` is coerced to double so
#' `10L` and `10` key alike; `mask_values` is sorted so order does not matter.
#' `scale`/`offset` are included because they change pixel values. `clip` is
#' included because it changes the written extent (polygon vs bbox), so a
#' `clip = FALSE` request must not read a clipped cube (or vice versa).
#' `tile_size` (the download-tiling grid, #38) is appended to the hash ONLY when
#' non-NULL, so an untiled cube keeps the exact legacy 18-element hash (existing
#' `cube_<key>.tif` stay valid) while a tiled read keys distinctly. It must
#' arrive already snapped by the caller (see `tile_size_check()`).
#' @noRd
stac_cube_cache_key <- function(aoi_target, res, target_crs, dt, aggregation,
                                resampling, stac_url, collection, band_assets,
                                datetime, index, cloud_cover_max, mask_values,
                                scale, offset, months = NULL,
                                offset_before = 0, clip = TRUE,
                                tile_size = NULL) {
  geom_wkb <- sf::st_as_binary(sf::st_geometry(aoi_target), endian = "little")
  parts <- list(
    geom_wkb, as.numeric(res), target_crs, dt, aggregation, resampling,
    stac_url, collection, band_assets, datetime, index,
    as.numeric(cloud_cover_max), sort(as.numeric(mask_values)),
    as.numeric(scale), as.numeric(offset), sort(as.numeric(months)),
    as.numeric(offset_before), as.logical(clip)
  )
  # A tiled read caches the same .tif shape but over the AOI-intersecting tile
  # union; keying it apart stops a tiled cube being served for an untiled request
  # (or vice versa). Appending only when non-NULL preserves the legacy key.
  if (!is.null(tile_size)) parts <- c(parts, list(as.numeric(tile_size)))
  # Shared with stac_cache_key(); see cache_key_hash() for why this is no longer
  # rlang::hash() (#48) and why the key is now 16 characters.
  cache_key_hash(parts)
}

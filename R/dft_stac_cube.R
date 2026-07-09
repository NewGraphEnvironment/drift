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
#' cube-affecting parameter. Because it is invariant to [dft_rast_break()]'s
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
#' @param cache_dir Character. Cache directory. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-fetch even if cached, overwriting the cached raster
#'   (default `FALSE`).
#' @param sign_fn A signing function for STAC assets. Default is
#'   [rstac::sign_planetary_computer()].
#'
#' @return A [terra::SpatRaster] index stack — one layer per time step, with a
#'   time value per layer — cached as a GeoTIFF. The stack spans the AOI
#'   **bounding box** (cloud-masked but not clipped to the AOI polygon); clip the
#'   reduced raster from [dft_rast_break()] with `terra::mask()` if a tight AOI is
#'   needed. For sources with a reflectance-offset baseline boundary (Sentinel-2),
#'   items are split at the boundary and offset-corrected per side, so a series
#'   crossing it carries no artificial index step.
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
                          cloud_cover_max = 60,
                          months = NULL,
                          mask_values = NULL,
                          cache_dir = NULL,
                          force = FALSE,
                          sign_fn = rstac::sign_planetary_computer()) {
  rlang::check_installed("gdalcubes", reason = "to fetch STAC cubes")

  # GDAL cloud-read tuning for /vsicurl COG streaming (biggest win:
  # DISABLE_READDIR_ON_OPEN avoids a remote directory listing on every open).
  # Restored on exit so we don't mutate the caller's session.
  gdal_cfg <- c(
    GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR",
    GDAL_HTTP_MULTIPLEX = "YES",
    GDAL_HTTP_VERSION = "2",
    VSI_CACHE = "TRUE",
    CPL_VSIL_CURL_ALLOWED_EXTENSIONS = ".tif"
  )
  old_cfg <- Sys.getenv(names(gdal_cfg), unset = NA)
  do.call(Sys.setenv, as.list(gdal_cfg))
  on.exit({
    set_again <- old_cfg[!is.na(old_cfg)]
    if (length(set_again)) do.call(Sys.setenv, as.list(set_again))
    unset <- names(old_cfg)[is.na(old_cfg)]
    if (length(unset)) Sys.unsetenv(unset)
  }, add = TRUE)

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
  offset_boundary <- cfg$offset_boundary
  offset_before <- cfg$offset_before %||% 0

  # Ensure aoi is sf
  if (inherits(aoi, "SpatVector")) aoi <- sf::st_as_sf(aoi)
  stopifnot(inherits(aoi, c("sf", "sfc")))

  target_crs <- if (is.null(crs)) auto_utm_epsg(aoi) else crs
  aoi_wgs84 <- sf::st_transform(aoi, 4326)
  aoi_target <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))
  bbox_target <- sf::st_bbox(aoi_target)

  # Assets: the index's required roles + the mask role (index_roles errors on
  # an unknown index before any network call)
  roles_needed <- index_roles(index)
  band_assets <- unlist(cfg$roles[roles_needed], use.names = FALSE)
  mask_asset <- cfg$roles$mask

  # datetime interval -> cube_view time bounds
  dr <- strsplit(datetime, "/", fixed = TRUE)[[1]]
  if (length(dr) != 2) {
    cli::cli_abort("`datetime` must be an ISO 8601 interval {.val start/end}.")
  }
  t0 <- dr[1]
  t1 <- dr[2]

  # Cache
  cache_base <- dft_cache_path(cache_dir)
  cache_source_dir <- file.path(cache_base, source)
  dir.create(cache_source_dir, recursive = TRUE, showWarnings = FALSE)
  cache_key <- stac_cube_cache_key(
    aoi_target, res, target_crs, dt, aggregation, resampling,
    cfg$stac_url, cfg$collection, band_assets, datetime, index,
    cloud_cover_max, mask_values, scale, offset, months, offset_before
  )
  cache_file <- file.path(cache_source_dir, paste0("cube_", cache_key, ".tif"))

  # monthly layer times, derived from the datetime window start
  month_times <- function(n) {
    seq(as.Date(paste0(substr(dr[1], 1, 7), "-01")), by = "month", length.out = n)
  }

  if (!force && file.exists(cache_file)) {
    message("  cube: cached")
    r <- terra::rast(cache_file)
    terra::time(r) <- month_times(terra::nlyr(r))
    return(r)
  }

  # STAC query: intersects (not bbox) + scene cloud pre-filter + pagination
  message("Querying STAC: ", cfg$collection, " (", datetime, ")...")
  items <- rstac::stac(cfg$stac_url) |>
    rstac::stac_search(
      collections = cfg$collection,
      # union so a multi-feature AOI queries its whole footprint, matching the
      # cube extent and filter_geom clip (a single first-feature geometry would
      # leave silent NoData holes over the other features)
      intersects = sf::st_geometry(sf::st_union(aoi_wgs84))[[1]],
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
  if (n_items == 0) stop("No STAC items found for ", cfg$collection)

  v <- gdalcubes::cube_view(
    srs = target_crs,
    extent = list(
      left = bbox_target[["xmin"]], right = bbox_target[["xmax"]],
      bottom = bbox_target[["ymin"]], top = bbox_target[["ymax"]],
      t0 = t0, t1 = t1
    ),
    dx = res, dy = res, dt = dt,
    aggregation = aggregation, resampling = resampling
  )

  # Build the index cube for one item subset with one offset, materialize it, and
  # read it back as a terra stack. The cube spans the AOI bounding box:
  # gdalcubes::filter_geom() to clip to the polygon yields an all-NA cube (and can
  # crash the compute worker) on the pinned build, so we mask clouds here and
  # leave polygon clipping to the caller, as the sibling dft_stac_fetch() does.
  build_index_stack <- function(features, offset_use) {
    img_col <- gdalcubes::stac_image_collection(
      features, asset_names = c(band_assets, mask_asset)
    )
    cube <- gdalcubes::raster_cube(
      img_col, v, mask = gdalcubes::image_mask(mask_asset, values = mask_values)
    )
    idx <- dft_index_expr(cube, index = index, source = source,
                          roles = cfg$roles, scale = scale, offset = offset_use)
    tmp <- tempfile(fileext = ".nc")
    gdalcubes::write_ncdf(idx, tmp, overwrite = TRUE)
    terra::rast(tmp)
  }

  # Baseline-conditional offset: split items at the boundary and correct each
  # side with its own offset, then coalesce onto the shared monthly grid. Both
  # subcubes are built over the full view so their layers align for terra::cover.
  is_pre <- rep(FALSE, length(items$features))
  if (!is.null(offset_boundary)) {
    item_date <- as.Date(substr(
      vapply(items$features, function(f) f$properties$datetime %||% NA_character_, ""),
      1, 10
    ))
    is_pre <- !is.na(item_date) & item_date < as.Date(offset_boundary)
  }

  if (any(is_pre) && !all(is_pre)) {
    message("  offset split at ", offset_boundary, ": ",
            sum(is_pre), " pre / ", sum(!is_pre), " post")
    stk <- terra::cover(
      build_index_stack(items$features[is_pre], offset_before),
      build_index_stack(items$features[!is_pre], offset)
    )
  } else {
    stk <- build_index_stack(items$features, if (all(is_pre)) offset_before else offset)
  }

  terra::time(stk) <- month_times(terra::nlyr(stk))
  names(stk) <- rep(index, terra::nlyr(stk))
  terra::writeRaster(stk, cache_file, overwrite = TRUE)
  stk
}


#' Cache key for one STAC index-cube parameter set
#'
#' Cube-mode analogue of `stac_cache_key()` (kept separate so the fetch key
#' stays byte-for-byte stable). Hashes the AOI geometry as WKB plus every
#' parameter that changes the written index cube. `res` is coerced to double so
#' `10L` and `10` key alike; `mask_values` is sorted so order does not matter.
#' `scale`/`offset` are included because they change pixel values.
#' @noRd
stac_cube_cache_key <- function(aoi_target, res, target_crs, dt, aggregation,
                                resampling, stac_url, collection, band_assets,
                                datetime, index, cloud_cover_max, mask_values,
                                scale, offset, months = NULL,
                                offset_before = 0) {
  geom_wkb <- sf::st_as_binary(sf::st_geometry(aoi_target), endian = "little")
  substr(
    rlang::hash(list(
      geom_wkb, as.numeric(res), target_crs, dt, aggregation, resampling,
      stac_url, collection, band_assets, datetime, index,
      as.numeric(cloud_cover_max), sort(as.numeric(mask_values)),
      as.numeric(scale), as.numeric(offset), sort(as.numeric(months)),
      as.numeric(offset_before)
    )),
    1, 12
  )
}

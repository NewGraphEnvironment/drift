#' Fetch a masked spectral-index cube from a STAC catalog
#'
#' Sibling of [dft_stac_fetch()] for continuous change detection. Where
#' [dft_stac_fetch()] materializes one categorical raster per year, this builds
#' a multi-band, sub-annual reflectance cube, masks clouds, computes a spectral
#' index over band roles, and returns the lazy single-band index cube — the
#' input to [dft_rast_break()] for per-pixel trajectory breakpoint detection.
#'
#' The index cube is materialized once to a NetCDF file under [dft_cache_path()]
#' as `<source>/cube_<key>.nc` (the full time axis, one band), keyed by a hash of
#' the AOI geometry and every cube-affecting parameter. Because the cube is
#' invariant to [dft_rast_break()]'s parameters (`history`/`start`/`level`),
#' caching it here makes bfast parameter sweeps cheap — they re-read the local
#' `.nc` instead of re-streaming COGs.
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
#' @param mask_values Integer vector of mask-band classes to exclude. When
#'   `NULL`, uses `mask_values` from [dft_stac_config()] (e.g. Sentinel-2 SCL
#'   cloud / shadow / cirrus classes).
#' @param cache_dir Character. Cache directory. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-fetch even if cached, overwriting the cached `.nc`
#'   (default `FALSE`).
#' @param sign_fn A signing function for STAC assets. Default is
#'   [rstac::sign_planetary_computer()].
#'
#' @return A `gdalcubes` data cube with a single band named `index`, backed by
#'   the cached NetCDF file. The cube spans the AOI **bounding box** (cloud-masked
#'   but not clipped to the AOI polygon); clip the reduced raster from
#'   [dft_rast_break()] with `terra::mask()` if a tight AOI is needed.
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
                          mask_values = NULL,
                          cache_dir = NULL,
                          force = FALSE,
                          sign_fn = rstac::sign_planetary_computer()) {
  rlang::check_installed("gdalcubes", reason = "to fetch STAC cubes")

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
    cloud_cover_max, mask_values, scale, offset
  )
  cache_file <- file.path(cache_source_dir, paste0("cube_", cache_key, ".nc"))

  if (!force && file.exists(cache_file)) {
    message("  cube: cached")
    return(gdalcubes::ncdf_cube(cache_file))
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

  n_items <- length(items$features)
  message("  ", n_items, " items returned")
  if (n_items == 0) stop("No STAC items found for ", cfg$collection)

  # image_mask masks the categorical mask band at read time, before the
  # cube_view resampling touches reflectance bands
  col <- gdalcubes::stac_image_collection(
    items$features, asset_names = c(band_assets, mask_asset)
  )

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

  # The cube spans the AOI bounding box. Clipping to the AOI polygon with
  # gdalcubes::filter_geom() inside the pipeline yields an all-NA cube (and can
  # crash the compute worker) on the pinned gdalcubes build, so we mask clouds
  # here and leave polygon clipping to the caller (terra::mask() on the reduced
  # raster), matching how the categorical sibling dft_stac_fetch() masks.
  cube <- gdalcubes::raster_cube(
    col, v,
    mask = gdalcubes::image_mask(mask_asset, values = mask_values)
  )

  idx <- dft_index_expr(cube, index = index, source = source,
                        roles = cfg$roles, scale = scale, offset = offset)

  gdalcubes::write_ncdf(idx, cache_file, overwrite = TRUE)
  gdalcubes::ncdf_cube(cache_file)
}


#' Cache key for one STAC index-cube parameter set
#'
#' Cube-mode analogue of [stac_cache_key()] (kept separate so the fetch key
#' stays byte-for-byte stable). Hashes the AOI geometry as WKB plus every
#' parameter that changes the written index cube. `res` is coerced to double so
#' `10L` and `10` key alike; `mask_values` is sorted so order does not matter.
#' `scale`/`offset` are included because they change pixel values.
#' @noRd
stac_cube_cache_key <- function(aoi_target, res, target_crs, dt, aggregation,
                                resampling, stac_url, collection, band_assets,
                                datetime, index, cloud_cover_max, mask_values,
                                scale, offset) {
  geom_wkb <- sf::st_as_binary(sf::st_geometry(aoi_target), endian = "little")
  substr(
    rlang::hash(list(
      geom_wkb, as.numeric(res), target_crs, dt, aggregation, resampling,
      stac_url, collection, band_assets, datetime, index,
      as.numeric(cloud_cover_max), sort(as.numeric(mask_values)),
      as.numeric(scale), as.numeric(offset)
    )),
    1, 12
  )
}

#' Fetch STAC-hosted rasters via gdalcubes
#'
#' Query a STAC catalog, build a gdalcubes image collection, and extract
#' per-year rasters cropped and masked to the AOI. Works with any STAC
#' collection hosting single-band classified rasters (IO LULC, ESA WorldCover,
#' custom COGs).
#'
#' Fetched rasters are cached under [dft_cache_path()] as
#' `<source>/<year>_<key>.nc`, where `key` is a hash of the AOI geometry and
#' every fetch parameter that affects the output (`res`, `crs`, `dt`,
#' `aggregation`, `resampling`, `stac_url`, `collection`, `asset`). Repeat
#' calls with the same AOI and parameters reuse the cache; changing any of
#' them re-fetches.
#'
#' @param aoi An `sf` polygon defining the area of interest.
#' @param source Character. A known source name passed to [dft_stac_config()].
#'   Ignored when `stac_url`, `collection`, and `asset` are all provided.
#' @param years Integer vector of years to fetch. When `NULL`, uses
#'   `available_years` from [dft_stac_config()].
#' @param stac_url Character. STAC API endpoint URL. Overrides `source`.
#' @param collection Character. STAC collection ID. Overrides `source`.
#' @param asset Character. Asset name within each STAC item. Overrides `source`.
#' @param res Numeric. Output pixel size in CRS units (default 10).
#' @param crs Character. Target CRS as an EPSG string (e.g. `"EPSG:32609"`).
#'   When `NULL`, auto-detected from the AOI centroid's UTM zone.
#' @param dt Character. ISO 8601 duration for the temporal aggregation window
#'   (default `"P1Y"`).
#' @param aggregation Character. Temporal aggregation method (default
#'   `"first"`). Use `"median"` for multi-scene composites.
#' @param resampling Character. Spatial resampling method (default `"near"`
#'   for categorical data).
#' @param cache_dir Character. Cache directory path. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-fetch even if cached, overwriting the cached file
#'   (default `FALSE`). A raster returned by an earlier call with the same
#'   parameters is backed by that file and may silently pick up the rewritten
#'   contents.
#' @param sign_fn A signing function for STAC assets. Default is
#'   [rstac::sign_planetary_computer()].
#'
#' @return A named list of [terra::SpatRaster] objects, one per year. The STAC
#'   items are attached as `attr(, "stac_items")` for use with
#'   [dft_stac_classes()].
#' @export
dft_stac_fetch <- function(aoi,
                           source = "io-lulc",
                           years = NULL,
                           stac_url = NULL,
                           collection = NULL,
                           asset = NULL,
                           res = 10,
                           crs = NULL,
                           dt = "P1Y",
                           aggregation = "first",
                           resampling = "near",
                           cache_dir = NULL,
                           force = FALSE,
                           sign_fn = rstac::sign_planetary_computer()) {
  rlang::check_installed("gdalcubes", reason = "to fetch STAC rasters")

  # Resolve config
  if (is.null(stac_url) || is.null(collection) || is.null(asset)) {
    cfg <- dft_stac_config(source)
    if (isTRUE(cfg$cube)) {
      cli::cli_abort(c(
        "Source {.val {source}} is a cube source, not a categorical raster.",
        "i" = "Use {.fn dft_stac_cube} for continuous index-trajectory sources."
      ))
    }
    stac_url <- stac_url %||% cfg$stac_url
    collection <- collection %||% cfg$collection
    asset <- asset %||% cfg$asset
    if (is.null(years)) years <- cfg$available_years
  }
  stopifnot(!is.null(years), length(years) > 0)

  # Ensure aoi is sf

  if (inherits(aoi, "SpatVector")) aoi <- sf::st_as_sf(aoi)
  stopifnot(inherits(aoi, c("sf", "sfc")))

  # Resolve CRS
  target_crs <- if (is.null(crs)) auto_utm_epsg(aoi) else crs

  # AOI in WGS84 for STAC query
  aoi_wgs84 <- sf::st_transform(aoi, 4326)
  bbox_query <- as.numeric(sf::st_bbox(aoi_wgs84))

  # AOI in target CRS for cube extent and masking
  aoi_target <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))
  bbox_target <- sf::st_bbox(aoi_target)

  # STAC query
  message("Querying STAC: ", collection, " (", min(years), "-", max(years), ")...")
  items <- rstac::stac(stac_url) |>
    rstac::stac_search(
      collections = collection,
      bbox = bbox_query,
      datetime = paste0(min(years), "-01-01/", max(years), "-12-31")
    ) |>
    rstac::get_request() |>
    rstac::items_sign(sign_fn = sign_fn)

  n_items <- length(items$features)
  message("  ", n_items, " items returned")
  if (n_items == 0) stop("No STAC items found for ", collection)

  # Build gdalcubes image collection
  col <- gdalcubes::stac_image_collection(items$features, asset_names = asset)

  # Cache setup
  cache_base <- dft_cache_path(cache_dir)
  source_label <- if (!is.null(source)) source else "custom"
  cache_source_dir <- file.path(cache_base, source_label)
  dir.create(cache_source_dir, recursive = TRUE, showWarnings = FALSE)
  cache_key <- stac_cache_key(
    aoi_target, res, target_crs, dt, aggregation, resampling,
    stac_url, collection, asset
  )

  # Fetch per year
  result <- lapply(years, function(yr) {
    cache_file <- file.path(cache_source_dir, paste0(yr, "_", cache_key, ".nc"))

    if (!force && file.exists(cache_file)) {
      message("  ", yr, ": cached")
      r <- terra::rast(cache_file)
    } else {
      message("  ", yr, ": fetching...")
      ext <- list(
        left = bbox_target[["xmin"]], right = bbox_target[["xmax"]],
        bottom = bbox_target[["ymin"]], top = bbox_target[["ymax"]]
      )
      fetch_extent_to(col, ext, paste0(yr, "-01-01"), paste0(yr, "-12-31"),
                      target_crs, res, dt, aggregation, resampling, cache_file)
      r <- terra::rast(cache_file)
    }

    terra::mask(r, terra::vect(aoi_target))
  })

  names(result) <- as.character(years)
  attr(result, "stac_items") <- items
  result
}


#' Cache key for one STAC fetch parameter set
#'
#' Hashes everything that changes the written raster except year, which stays
#' as the readable filename prefix (all years of one call share a key). The
#' geometry is hashed as WKB so sf attribute columns and PROJ-version CRS
#' representation differences can't change the key; the CRS enters separately
#' as `target_crs`. `res` is coerced to double so `10L` and `10` key alike.
#' Callers must pass post-resolution `stac_url`/`collection`/`asset`, never
#' the raw possibly-NULL arguments. `tile_size` (the download-tiling grid, #36)
#' is appended to the hash ONLY when non-NULL, so an untiled fetch keeps the
#' exact legacy 9-element hash (existing caches stay valid) while a tiled fetch
#' keys distinctly. It must arrive already snapped by the caller.
#' @noRd
stac_cache_key <- function(aoi_target, res, target_crs, dt, aggregation,
                           resampling, stac_url, collection, asset,
                           tile_size = NULL) {
  geom_wkb <- sf::st_as_binary(sf::st_geometry(aoi_target), endian = "little")
  parts <- list(
    geom_wkb, as.numeric(res), target_crs, dt, aggregation,
    resampling, stac_url, collection, asset
  )
  # A tiled fetch caches a terra .tif mosaic; an untiled fetch caches a
  # gdalcubes .nc. Keying them apart stops one being served as the other.
  if (!is.null(tile_size)) parts <- c(parts, list(as.numeric(tile_size)))
  substr(rlang::hash(parts), 1, 12)
}


#' Validate and snap a download `tile_size` to the pixel grid
#'
#' `tile_size` (CRS units) controls the download-tiling grid (#36). It is
#' snapped to a multiple of `res` so every tile's pixel grid aligns to the same
#' `res`-lattice — a prerequisite for a seam-free `terra::merge()` of the tiles.
#' Caller only invokes this for a non-NULL `tile_size`; `NULL` gates the whole
#' tiled path upstream. Returns the snapped size (a single positive numeric).
#' @noRd
tile_size_check <- function(tile_size, res) {
  if (!is.numeric(tile_size) || length(tile_size) != 1L ||
        !is.finite(tile_size) || tile_size <= 0) {
    cli::cli_abort(c(
      "{.arg tile_size} must be a single positive finite number (CRS units) \\
       or {.code NULL}.",
      "x" = "Got {.obj_type_friendly {tile_size}}."
    ))
  }
  snapped <- round(tile_size / res) * res
  if (snapped < res) {
    cli::cli_abort(c(
      "{.arg tile_size} ({tile_size}) snaps to {snapped}, smaller than \\
       {.arg res} ({res}).",
      "i" = "Choose a {.arg tile_size} at least as large as {.arg res}."
    ))
  }
  if (!isTRUE(all.equal(snapped, tile_size))) {
    cli::cli_inform(
      "{.arg tile_size} snapped from {tile_size} to {snapped} \\
       (a multiple of {.arg res} = {res})."
    )
  }
  snapped
}


#' Build the res-aligned download tiles that intersect the AOI
#'
#' Splits the AOI bounding box into a grid of `tile_size`-square cells anchored
#' at the bbox lower-left (the same origin as the single-cube extent), and keeps
#' only cells that intersect the AOI polygon — so a thin corridor fetches near
#' its footprint, not its full bbox (#36). Boundary cells are left un-trimmed
#' past the bbox: trimming the max edge would break `res`-alignment, and the
#' `< tile_size` overhang is dropped by the final `terra::mask()` anyway.
#' `tile_size` must already be snapped (see [tile_size_check()]).
#' @return A list of `list(left, right, bottom, top)` extents for [gdalcubes::cube_view()].
#' @noRd
tile_grid <- function(aoi_target, tile_size, res) {
  bbox <- sf::st_bbox(aoi_target)
  grid <- sf::st_make_grid(
    sf::st_as_sfc(bbox),
    cellsize = tile_size,
    offset = c(bbox[["xmin"]], bbox[["ymin"]])
  )
  aoi_union <- sf::st_union(sf::st_geometry(aoi_target))
  grid <- grid[lengths(sf::st_intersects(grid, aoi_union)) > 0]
  if (length(grid) == 0) {
    cli::cli_abort("No download tiles intersect the AOI \\
                    (is the AOI geometry valid and non-empty?).")
  }
  lapply(grid, function(cell) {
    b <- sf::st_bbox(cell)
    list(left = b[["xmin"]], right = b[["xmax"]],
         bottom = b[["ymin"]], top = b[["ymax"]])
  })
}


#' Fetch one gdalcubes cube over a single space+time extent to a NetCDF file
#'
#' The `cube_view` + `raster_cube` + `write_ncdf` block shared by the untiled
#' fetch (one call over the AOI bbox) and the tiled fetch (one call per tile,
#' #36). Sharing this primitive is what guarantees a tile fetches identically to
#' the corresponding slice of the untiled cube. `ext` is a list with
#' `left`/`right`/`bottom`/`top`; `t0`/`t1` bound the year. Writes to `out_nc`
#' and returns it (the caller reads it back with [terra::rast()]).
#' @noRd
fetch_extent_to <- function(col, ext, t0, t1, target_crs, res, dt,
                            aggregation, resampling, out_nc) {
  v <- gdalcubes::cube_view(
    srs = target_crs,
    extent = list(
      left = ext$left, right = ext$right,
      bottom = ext$bottom, top = ext$top,
      t0 = t0, t1 = t1
    ),
    dx = res, dy = res, dt = dt,
    aggregation = aggregation, resampling = resampling
  )
  cube <- gdalcubes::raster_cube(col, v)
  gdalcubes::write_ncdf(cube, out_nc, overwrite = TRUE)
  out_nc
}


#' Auto-detect UTM EPSG code from sf geometry
#' @noRd
auto_utm_epsg <- function(x) {
  centroid <- sf::st_coordinates(
    sf::st_centroid(sf::st_union(sf::st_transform(x, 4326)))
  )
  zone <- floor((centroid[1, "X"] + 180) / 6) + 1
  hemisphere <- if (centroid[1, "Y"] >= 0) 32600L else 32700L
  paste0("EPSG:", hemisphere + zone)
}

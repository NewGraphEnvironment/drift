#' Fetch STAC-hosted rasters via gdalcubes
#'
#' Query a STAC catalog, build a gdalcubes image collection, and extract
#' per-year rasters cropped and masked to the AOI. Works with any STAC
#' collection hosting single-band classified rasters (IO LULC, ESA WorldCover,
#' custom COGs).
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
#' @param force Logical. Re-fetch even if cached (default `FALSE`).
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
      v <- gdalcubes::cube_view(
        srs = target_crs,
        extent = list(
          left   = bbox_target["xmin"],
          right  = bbox_target["xmax"],
          bottom = bbox_target["ymin"],
          top    = bbox_target["ymax"],
          t0 = paste0(yr, "-01-01"),
          t1 = paste0(yr, "-12-31")
        ),
        dx = res, dy = res,
        dt = dt,
        aggregation = aggregation,
        resampling = resampling
      )
      cube <- gdalcubes::raster_cube(col, v)
      gdalcubes::write_ncdf(cube, cache_file)
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
#' the raw possibly-NULL arguments.
#' @noRd
stac_cache_key <- function(aoi_target, res, target_crs, dt, aggregation,
                           resampling, stac_url, collection, asset) {
  geom_wkb <- sf::st_as_binary(sf::st_geometry(aoi_target), endian = "little")
  substr(
    rlang::hash(list(
      geom_wkb, as.numeric(res), target_crs, dt, aggregation,
      resampling, stac_url, collection, asset
    )),
    1, 12
  )
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

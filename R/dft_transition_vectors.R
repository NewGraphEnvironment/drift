#' Vectorize transition raster into individual change patches
#'
#' Convert a transition `SpatRaster` (from [dft_rast_transition()]) into `sf`
#' polygons — one row per connected patch of pixels sharing the same
#' transition type. Useful for QA in GIS, spatial attribution to management
#' zones, and patch-level reporting.
#'
#' @param x A factor `SpatRaster` from [dft_rast_transition()] (the `$raster`
#'   element). Must have a projected CRS.
#' @param zones Optional `sf` polygon layer for spatial attribution. Any
#'   partitioning: sub-basins, parcels, climate regions, management units.
#' @param zone_col Character. Column name in `zones` identifying each zone.
#'   Required when `zones` is supplied.
#' @param patch_area_min Numeric or `NULL`. Minimum patch area in m². Patches
#'   smaller than this are dropped before returning. `NULL` (default) keeps all.
#'
#' @return An `sf` data frame (polygon geometry) with columns:
#'   - `patch_id` (integer) — connected component ID
#'   - `transition` (character) — transition label (e.g. "Trees -> Rangeland")
#'   - `area_ha` (numeric) — patch area in hectares
#'   - Zone column (if `zones` supplied) — from spatial intersection
#'
#' @export
#' @examples
#' r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
#' r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
#' classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
#' result <- dft_rast_transition(classified, from = "2017", to = "2020")
#'
#' # Vectorize all transition patches
#' patches <- dft_transition_vectors(result$raster)
#' head(patches)
#'
#' # Filter to large patches only
#' patches_large <- dft_transition_vectors(result$raster, patch_area_min = 1000)
#' head(patches_large)
dft_transition_vectors <- function(x,
                                   zones = NULL,
                                   zone_col = NULL,
                                   patch_area_min = NULL) {
  if (!inherits(x, "SpatRaster")) {
    stop("`x` must be a SpatRaster (e.g. from dft_rast_transition()$raster).",
         call. = FALSE)
  }
  dft_check_crs(x, "dft_transition_vectors")

  if (!terra::is.factor(x)) {
    stop("`x` must be a factor SpatRaster with transition labels.", call. = FALSE)
  }

  if (!is.null(zones)) {
    if (!inherits(zones, "sf")) {
      stop("`zones` must be an sf object.", call. = FALSE)
    }
    if (is.null(zone_col) || !zone_col %in% names(zones)) {
      stop("`zone_col` must name a column in `zones`.", call. = FALSE)
    }
  }

  if (!is.null(patch_area_min)) {
    if (!is.numeric(patch_area_min) || length(patch_area_min) != 1 ||
          is.na(patch_area_min) || patch_area_min < 0) {
      stop("`patch_area_min` must be a single non-negative number or NULL.",
           call. = FALSE)
    }
  }

  # Single pass: 8-connected components of same-valued cells.
  # Requires terra >= 1.8-10 (earlier versions falsely connect patches
  # across the left/right raster edges with values = TRUE).
  p <- terra::patches(x, directions = 8, values = TRUE)
  names(p) <- "pid"
  polys_sf <- sf::st_as_sf(terra::as.polygons(p))

  if (nrow(polys_sf) == 0) {
    return(sf::st_sf(
      patch_id = integer(0), transition = character(0),
      area_ha = numeric(0), geometry = sf::st_sfc(crs = sf::st_crs(x))
    ))
  }

  # Map each patch to its transition label, touching only the non-NA cells
  cell_idx <- terra::cells(p)
  pid_at <- terra::extract(p, cell_idx)[, 1]
  lab_at <- as.character(terra::extract(x, cell_idx)[, 1])
  first <- !duplicated(pid_at)
  lab_map <- stats::setNames(lab_at[first], pid_at[first])

  polys_sf$transition <- unname(lab_map[as.character(polys_sf$pid)])
  # Cell values with no cats() entry have no label — drop their patches
  polys_sf <- polys_sf[!is.na(polys_sf$transition), ]
  polys_sf$patch_id <- seq_len(nrow(polys_sf))
  polys_sf$area_ha <- as.numeric(sf::st_area(polys_sf)) * 1e-4
  polys_sf$pid <- NULL

  # Filter by minimum area
  if (!is.null(patch_area_min) && patch_area_min > 0) {
    area_m2 <- as.numeric(sf::st_area(polys_sf))
    polys_sf <- polys_sf[area_m2 >= patch_area_min, ]
  }

  # Select and order columns
  out <- polys_sf[c("patch_id", "transition", "area_ha")]

  # Zone attribution

  if (!is.null(zones)) {
    zones_proj <- sf::st_transform(zones[zone_col], sf::st_crs(out))
    out <- suppressWarnings(sf::st_intersection(out, zones_proj))
  }

  out
}

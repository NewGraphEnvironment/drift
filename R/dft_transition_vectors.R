#' Vectorize transition raster into individual change patches
#'
#' Convert a transition `SpatRaster` (from [dft_rast_transition()]) into `sf`
#' polygons — one row per connected patch of pixels sharing the same
#' transition type. Useful for QA in GIS, spatial attribution to management
#' zones, and patch-level reporting.
#'
#' Patches are 8-connected components of same-valued cells, computed in a
#' single pass over the grid, so large sparse rasters vectorize without
#' per-class memory cost.
#'
#' @param x A factor `SpatRaster` from [dft_rast_transition()] (the `$raster`
#'   element). Must have a projected CRS.
#' @param zones Optional `sf` polygon layer for spatial attribution. Any
#'   partitioning: sub-basins, parcels, climate regions, management units.
#' @param zone_col Character. Column name in `zones` identifying each zone.
#'   Required when `zones` is supplied.
#' @param patch_area_min Numeric or `NULL`. Minimum patch area in m². Patches
#'   smaller than this are dropped before returning. `NULL` (default) keeps all.
#' @param changes_only Logical. When `TRUE`, drop stable (`from == to`)
#'   transitions before polygonizing, so only actual change patches are
#'   vectorized. On a floodplain the stable mosaic is most of the grid, so this
#'   is the main memory lever for large AOIs. Default `FALSE` keeps every patch
#'   (including stable ones).
#'
#' @return An `sf` data frame (polygon geometry) with columns:
#'   - `patch_id` (integer) — connected component ID, numbered in raster
#'     scan order over the returned patches
#'   - `transition` (character) — transition label (e.g. "Trees -> Rangeland")
#'   - `area_ha` (numeric) — patch area in hectares
#'   - Zone column (if `zones` supplied) — from spatial intersection
#'
#'   When `patch_area_min` or `changes_only` drop patches, `patch_id` is numbered
#'   over the surviving patches (dense `1..n`), not the pre-filter grid.
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
#'
#' # Only actual changes (drop stable from == to patches before polygonizing)
#' changes <- dft_transition_vectors(result$raster, changes_only = TRUE)
#' head(changes)
dft_transition_vectors <- function(x,
                                   zones = NULL,
                                   zone_col = NULL,
                                   patch_area_min = NULL,
                                   changes_only = FALSE) {
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

  if (!is.logical(changes_only) || length(changes_only) != 1 ||
        is.na(changes_only)) {
    stop("`changes_only` must be a single logical (TRUE or FALSE).", call. = FALSE)
  }

  # Optionally drop stable (from == to) transitions before polygonizing, so
  # as.polygons() only builds geometry for actual change patches. Stable codes
  # are those where from_code == to_code (id %/% 1000 == id %% 1000). On a
  # floodplain the stable mosaic is most of the grid, so this caps the working
  # set to what callers actually keep.
  if (isTRUE(changes_only)) {
    ct <- terra::cats(x)[[1]]
    stable_ids <- ct$id[(ct$id %/% 1000L) == (ct$id %% 1000L)]
    if (length(stable_ids) > 0) {
      # NA at stable cells, 1 at change cells; mask keeps x's factor levels
      change_mask <- terra::subst(x * 1L, stable_ids, NA, others = 1L)
      x <- terra::mask(x, change_mask)
    }
  }

  # Single pass: 8-connected components of same-valued cells.
  # Requires terra >= 1.8-10 (earlier versions falsely connect patches
  # across the left/right raster edges with values = TRUE).
  p <- terra::patches(x, directions = 8, values = TRUE)
  names(p) <- "pid"

  # When filtering by area, drop small patches at the raster level BEFORE
  # polygonizing (as.polygons is the patch-count-driven hotspot). For axis-
  # aligned raster polygons st_area == count * cell_area, so this drops a strict
  # subset of what the trailing st_area filter removes -> identical output.
  if (!is.null(patch_area_min) && patch_area_min > 0) {
    fp <- tryCatch(terra::freq(p), error = function(e) NULL)
    if (!is.null(fp)) {
      cell_area_m2 <- prod(terra::res(p))
      small <- fp$value[!is.na(fp$value) & fp$count * cell_area_m2 < patch_area_min]
      if (length(small) > 0) p <- terra::subst(p, small, NA)
    }
  }

  polys_sf <- sf::st_as_sf(terra::as.polygons(p))

  if (nrow(polys_sf) == 0) {
    out <- sf::st_sf(
      patch_id = integer(0), transition = character(0),
      area_ha = numeric(0), geometry = sf::st_sfc(crs = sf::st_crs(x))
    )
    # match the zone-attributed schema so per-zone results bind cleanly when a
    # zone has no (or, under changes_only, no change) patches
    if (!is.null(zones)) out[[zone_col]] <- zones[[zone_col]][0]
    return(out)
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

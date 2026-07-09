#' Detect land cover transitions between two time steps
#'
#' Compare two classified rasters cell-by-cell and return a transition raster
#' and summary table. Each pixel is encoded with its from→to class pair.
#'
#' @param x A named list of classified `SpatRaster`s (e.g. from
#'   [dft_rast_classify()]). Names identify each time step (typically years).
#' @param from Character. Name of the "before" layer in `x`.
#' @param to Character. Name of the "after" layer in `x`.
#' @param class_table A tibble with columns `code`, `class_name`, `color`.
#'   When `NULL`, loaded via [dft_class_table()] using `source`.
#' @param source Character. Used to load a shipped class table when
#'   `class_table` is `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.
#' @param from_class Character vector of class names to include as "from"
#'   classes. When `NULL` (default), all classes are included.
#' @param to_class Character vector of class names to include as "to"
#'   classes. When `NULL` (default), all classes are included.
#' @param unit Character. Area unit for the summary. One of `"ha"`
#'   (default), `"km2"`, or `"m2"`.
#' @param patch_area_min Numeric or `NULL`. Minimum area in m² for a connected
#'   patch of changed pixels to be retained. Patches smaller than this threshold
#'   are set to `NA`. Uses 8-connected adjacency. `NULL` (default) skips
#'   filtering.
#'
#' @return A list with three elements:
#'   - `raster`: A `SpatRaster` with factor levels labelled
#'     `"from_class -> to_class"`. Filtered-out transitions are set to `NA`.
#'   - `summary`: A tibble with columns `from_class`, `to_class`,
#'     `n_cells`, `area`, `pct`.
#'   - `removed`: A `SpatRaster` of transitions removed by `patch_area_min`
#'     filtering, or `NULL` when no filtering is applied. Same factor
#'     encoding as `raster`.
#'
#' @details
#' The transition raster, filters, and patch removal are computed with streamed
#' `terra` operations (`ifel`, `patches`, `freq`) on the underlying class codes —
#' no full-grid vectors are pulled into R — so peak memory scales with the number
#' of distinct transitions and patches, not the grid size.
#' @export
#' @examples
#' r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
#' r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
#' classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
#'
#' # All transitions
#' result <- dft_rast_transition(classified, from = "2017", to = "2020")
#' result$summary
#'
#' # Only tree loss to agriculture
#' tree_loss <- dft_rast_transition(classified, from = "2017", to = "2020",
#'                                  from_class = "Trees",
#'                                  to_class = c("Crops", "Rangeland", "Bare Ground"))
#' tree_loss$summary
#'
#' # Filter small patches (< 500 m² = 5 pixels at 10m)
#' filtered <- dft_rast_transition(classified, from = "2017", to = "2020",
#'                                 patch_area_min = 500)
#' filtered$summary
dft_rast_transition <- function(x,
                                from,
                                to,
                                class_table = NULL,
                                source = "io-lulc",
                                from_class = NULL,
                                to_class = NULL,
                                unit = "ha",
                                patch_area_min = NULL) {
  unit <- match.arg(unit, c("ha", "km2", "m2"))

  if (!is.null(patch_area_min)) {
    if (!is.numeric(patch_area_min) || length(patch_area_min) != 1 ||
          is.na(patch_area_min) || patch_area_min < 0) {
      stop("`patch_area_min` must be a single non-negative number or NULL.")
    }
  }

  if (!is.list(x) || inherits(x, "SpatRaster")) {
    stop("`x` must be a named list of SpatRasters, not a single SpatRaster.")
  }
  if (!from %in% names(x)) stop("Layer '", from, "' not found in `x`.")
  if (!to %in% names(x)) stop("Layer '", to, "' not found in `x`.")

  if (is.null(class_table)) {
    class_table <- dft_class_table(source)
  }

  r_from <- x[[from]]
  r_to <- x[[to]]
  dft_check_crs(r_from, "dft_rast_transition")
  dft_check_crs(r_to, "dft_rast_transition")

  # code -> class name lookup (small; used only for factor labels + summary)
  code_lookup <- stats::setNames(class_table$class_name, class_table$code)

  # Strip factor to raw integer codes as streamed rasters. `* 1L` returns a new
  # non-factor raster of codes, preserves NA, and does NOT mutate the inputs
  # (they are references into the caller's list). Encode each transition as
  # from_code * 1000 + to_code; NA propagates wherever either input is NA. No
  # full-grid R vector is materialized.
  code_from <- r_from * 1L
  code_to <- r_to * 1L
  r_trans <- code_from * 1000L + code_to

  # from_class / to_class filters as integer code-set membership (streamed)
  r_trans <- apply_codeset(r_trans, code_from, from_class, class_table)
  r_trans <- apply_codeset(r_trans, code_to, to_class, class_table)

  cell_area_m2 <- prod(terra::res(r_from))

  # Filter small patches of *changed* pixels (streamed; no rep()/values())
  r_removed <- NULL
  if (!is.null(patch_area_min) && patch_area_min > 0) {
    r_changed <- terra::ifel(!is.na(r_trans) & (code_from != code_to), 1L, NA)
    p <- terra::patches(r_changed, directions = 8)
    f <- tryCatch(terra::freq(p), error = function(e) NULL)   # NULL when no changes
    if (!is.null(f)) {
      f <- f[!is.na(f$value), , drop = FALSE]
      small_ids <- f$value[f$count * cell_area_m2 < patch_area_min]
      if (length(small_ids) > 0) {
        # 1 at small-patch cells, NA elsewhere (incl. p == NA / stable cells).
        # subst() is exact-match and scales; SpatRaster `%in%` is not dispatched
        # when terra is imported (not attached).
        sm <- terra::subst(p, small_ids, 1L, others = NA)
        r_removed <- terra::ifel(!is.na(sm), r_trans, NA)   # capture removed codes first
        r_trans <- terra::ifel(!is.na(sm), NA, r_trans)     # then drop them
      }
    }
  }

  # Observed transition codes + counts from a single native freq (value == code,
  # NA excluded). freq() errors on an all-NA raster -> treat as no transitions.
  freq_tbl <- tryCatch(terra::freq(r_trans), error = function(e) NULL)
  if (!is.null(freq_tbl)) {
    freq_tbl <- freq_tbl[!is.na(freq_tbl$value), , drop = FALSE]
  }

  m2_to_unit <- switch(unit, "m2" = 1, "ha" = 1e-4, "km2" = 1e-6)
  cell_area <- cell_area_m2 * m2_to_unit

  if (is.null(freq_tbl) || nrow(freq_tbl) == 0) {
    terra::set.cats(r_trans, layer = 1,
                    value = data.frame(id = integer(0), transition = character(0)))
    summary_tbl <- tibble::tibble(
      from_class = character(0), to_class = character(0),
      n_cells = integer(0), area = numeric(0), pct = numeric(0)
    )
    return(list(raster = r_trans, summary = summary_tbl, removed = NULL))
  }

  freq_tbl <- freq_tbl[order(freq_tbl$value), , drop = FALSE]
  codes <- freq_tbl$value
  from_codes <- codes %/% 1000L
  to_codes <- codes %% 1000L
  labels <- paste0(
    code_lookup[as.character(from_codes)], " -> ",
    code_lookup[as.character(to_codes)]
  )
  terra::set.cats(r_trans, layer = 1,
                  value = data.frame(id = codes, transition = labels))

  # Summary table
  total_valid <- sum(freq_tbl$count)
  summary_tbl <- tibble::tibble(
    from_class = code_lookup[as.character(from_codes)],
    to_class = code_lookup[as.character(to_codes)],
    n_cells = as.integer(freq_tbl$count),
    area = freq_tbl$count * cell_area,
    pct = round(freq_tbl$count / total_valid * 100, 2)
  )
  summary_tbl <- summary_tbl[order(summary_tbl$n_cells, decreasing = TRUE), ]

  # Factor levels for the removed raster (only when patch filtering removed cells)
  if (!is.null(r_removed)) {
    rf <- terra::freq(r_removed)
    rf <- rf[!is.na(rf$value), , drop = FALSE]
    rf <- rf[order(rf$value), , drop = FALSE]
    terra::set.cats(r_removed, layer = 1, value = data.frame(
      id = rf$value,
      transition = paste0(code_lookup[as.character(rf$value %/% 1000L)], " -> ",
                          code_lookup[as.character(rf$value %% 1000L)])
    ))
  }

  list(raster = r_trans, summary = summary_tbl, removed = r_removed)
}

#' Mask a transition raster to a from/to class set (streamed)
#'
#' Reproduces the old full-grid `name %in% from_class` filter using integer
#' code-set membership on a code raster, so no full-grid character vector is
#' built. `code_r %in% keep_codes` is FALSE (not NA) at NA cells, matching the
#' base-R string filter's NA handling. `NULL` selection is a no-op; an empty
#' selection (no class name matched) masks everything to NA.
#' @noRd
apply_codeset <- function(r_trans, code_r, names_sel, class_table) {
  if (is.null(names_sel)) return(r_trans)
  keep_codes <- class_table$code[class_table$class_name %in% names_sel]
  if (length(keep_codes) == 0L) return(r_trans * NA)   # impossible filter -> all NA
  # subst(): 1 at in-set codes, NA at out-of-set and NA cells. Avoids SpatRaster
  # `%in%`, which is not dispatched when terra is imported (not attached).
  keep_mask <- terra::subst(code_r, keep_codes, 1L, others = NA)
  terra::ifel(!is.na(keep_mask), r_trans, NA)
}

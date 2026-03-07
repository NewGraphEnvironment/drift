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
#'
#' @return A list with two elements:
#'   - `raster`: A `SpatRaster` with factor levels labelled
#'     `"from_class -> to_class"`. Filtered-out transitions are set to `NA`.
#'   - `summary`: A tibble with columns `from_class`, `to_class`,
#'     `n_cells`, `area`, `pct`.
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
dft_rast_transition <- function(x,
                                from,
                                to,
                                class_table = NULL,
                                source = "io-lulc",
                                from_class = NULL,
                                to_class = NULL,
                                unit = "ha") {
  unit <- match.arg(unit, c("ha", "km2", "m2"))

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

  # Resolve class names to codes
  code_lookup <- stats::setNames(class_table$class_name, class_table$code)

  # Get raw integer values (strip factor)
  v_from <- terra::values(r_from)[, 1]
  v_to <- terra::values(r_to)[, 1]

  # Map codes to class names
  name_from <- code_lookup[as.character(v_from)]
  name_to <- code_lookup[as.character(v_to)]

  # Encode transitions: from_code * 1000 + to_code (supports up to 999 classes)
  trans_code <- v_from * 1000L + v_to

  # Build mask for filters

  keep <- rep(TRUE, length(trans_code))
  if (!is.null(from_class)) keep <- keep & (name_from %in% from_class)
  if (!is.null(to_class)) keep <- keep & (name_to %in% to_class)

  # Also mask where either raster is NA
  keep <- keep & !is.na(v_from) & !is.na(v_to)

  trans_code[!keep] <- NA_integer_


  # Build transition raster
  r_trans <- terra::rast(r_from)
  terra::values(r_trans) <- trans_code

  # Build factor table from observed transitions
  valid <- !is.na(trans_code)
  unique_codes <- sort(unique(trans_code[valid]))

  if (length(unique_codes) == 0) {
    # No transitions found — return empty
    terra::set.cats(r_trans, layer = 1,
                    value = data.frame(id = integer(0), transition = character(0)))
    summary_tbl <- tibble::tibble(
      from_class = character(0), to_class = character(0),
      n_cells = integer(0), area = numeric(0), pct = numeric(0)
    )
    return(list(raster = r_trans, summary = summary_tbl))
  }

  from_codes <- unique_codes %/% 1000L
  to_codes <- unique_codes %% 1000L
  labels <- paste0(
    code_lookup[as.character(from_codes)], " -> ",
    code_lookup[as.character(to_codes)]
  )

  lvl_df <- data.frame(id = unique_codes, transition = labels)
  terra::set.cats(r_trans, layer = 1, value = lvl_df)

  # Summary table
  m2_to_unit <- switch(unit, "m2" = 1, "ha" = 1e-4, "km2" = 1e-6)
  res <- terra::res(r_from)
  cell_area <- res[1] * res[2] * m2_to_unit

  freq_tbl <- terra::freq(r_trans)
  freq_tbl <- freq_tbl[!is.na(freq_tbl$value), ]
  total_valid <- sum(keep)

  # freq on a factor raster returns labels in $value — map back to codes
  label_to_code <- stats::setNames(lvl_df$id, lvl_df$transition)
  freq_codes <- label_to_code[as.character(freq_tbl$value)]

  summary_tbl <- tibble::tibble(
    from_class = code_lookup[as.character(freq_codes %/% 1000L)],
    to_class = code_lookup[as.character(freq_codes %% 1000L)],
    n_cells = as.integer(freq_tbl$count),
    area = freq_tbl$count * cell_area,
    pct = round(freq_tbl$count / total_valid * 100, 2)
  )

  summary_tbl <- summary_tbl[order(summary_tbl$n_cells, decreasing = TRUE), ]

  list(raster = r_trans, summary = summary_tbl)
}

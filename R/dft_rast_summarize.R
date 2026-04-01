#' Summarize area by class
#'
#' Compute area and percentage by class for a categorical raster, optionally
#' across multiple years.
#'
#' @param x A [terra::SpatRaster] or a named list of `SpatRaster`s. When a
#'   named list, each name is used as the `year` column in the output.
#' @param class_table A tibble with columns `code`, `class_name`, `color`.
#'   When `NULL`, loaded via [dft_class_table()] using `source`.
#' @param source Character. Used to load a shipped class table when
#'   `class_table` is `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.
#' @param unit Character. Area unit for the `area` column. One of `"ha"`
#'   (default), `"km2"`, or `"m2"`.
#'
#' @return A tibble with columns:
#'   - `year` (character, only when `x` is a named list)
#'   - `code` (integer)
#'   - `class_name` (character)
#'   - `color` (character, hex)
#'   - `n_cells` (integer)
#'   - `area` (numeric, in requested `unit`)
#'   - `pct` (numeric, percentage of total non-NA cells)
#' @export
#' @examples
#' r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
#' dft_rast_summarize(r, source = "io-lulc", unit = "ha")
dft_rast_summarize <- function(x,
                               class_table = NULL,
                               source = "io-lulc",
                               unit = "ha") {
  unit <- match.arg(unit, c("ha", "km2", "m2"))
  if (is.null(class_table)) {
    class_table <- dft_class_table(source)
  }

  m2_to_unit <- switch(unit, "m2" = 1, "ha" = 1e-4, "km2" = 1e-6)

  if (is.list(x) && !inherits(x, "SpatRaster")) {
    results <- lapply(names(x), function(nm) {
      summarize_one(x[[nm]], class_table, m2_to_unit, year_label = nm)
    })
    out <- dplyr::bind_rows(results)
  } else {
    out <- summarize_one(x, class_table, m2_to_unit, year_label = NULL)
  }

  attr(out, "unit") <- unit
  out
}


#' Summarize a single SpatRaster
#' @noRd
summarize_one <- function(r, class_table, m2_to_unit, year_label = NULL) {
  dft_check_crs(r, "dft_rast_summarize")
  freq_tbl <- terra::freq(r)
  res <- terra::res(r)
  cell_area_m2 <- res[1] * res[2]
  total_cells <- sum(freq_tbl$count)

  if (terra::is.factor(r)) {
    # Factor raster: freq returns class names in value column
    result <- tibble::tibble(
      class_name = as.character(freq_tbl$value),
      n_cells = as.integer(freq_tbl$count)
    )
    # Join code and color from class_table
    ct_join <- class_table[c("code", "class_name", "color")]
    result <- dplyr::left_join(result, ct_join, by = "class_name")
  } else {
    # Raw integer raster: freq returns codes in value column
    result <- tibble::tibble(
      code = as.integer(freq_tbl$value),
      n_cells = as.integer(freq_tbl$count)
    )
    ct_join <- class_table[c("code", "class_name", "color")]
    result <- dplyr::left_join(result, ct_join, by = "code")
  }

  # Fill unknown codes/classes
  result$class_name[is.na(result$class_name)] <- paste0("Unknown_", result$code[is.na(result$class_name)])
  result$color[is.na(result$color)] <- "#cccccc"
  if (is.null(result$code) || any(is.na(result$code))) {
    # Reverse-lookup codes for classes not in class_table
    missing <- is.na(result$code)
    if (any(missing)) {
      code_lookup <- stats::setNames(class_table$code, class_table$class_name)
      result$code[missing] <- as.integer(code_lookup[result$class_name[missing]])
    }
  }

  result$area <- result$n_cells * cell_area_m2 * m2_to_unit
  result$pct <- round(result$n_cells / total_cells * 100, 2)

  if (!is.null(year_label)) {
    result <- tibble::tibble(year = year_label, result)
  }

  result[c(if (!is.null(year_label)) "year", "code", "class_name", "color", "n_cells", "area", "pct")]
}

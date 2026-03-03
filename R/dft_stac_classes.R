#' Extract class table from STAC item metadata
#'
#' Parses the `classification:classes` extension from STAC item properties
#' to build a class lookup table with codes, names, and colors.
#'
#' Falls back to a shipped CSV if STAC metadata is missing or incomplete.
#'
#' @param items An `rstac` items collection returned by [rstac::get_request()]
#'   or [rstac::items_sign()]. Uses the first item's properties.
#' @param source Character. Source name for CSV fallback lookup.
#'   One of `"io-lulc"` or `"esa-worldcover"`. Only used when STAC
#'   metadata lacks classification info.
#'
#' @return A tibble with columns `code` (integer), `class_name` (character),
#'   `color` (character, hex), and `description` (character, may be NA).
#'
#' @export
dft_stac_classes <- function(items = NULL, source = "io-lulc") {
  class_table <- NULL

  if (!is.null(items)) {
    class_table <- stac_classes_from_items(items)
  }

  if (is.null(class_table) || nrow(class_table) == 0) {
    class_table <- dft_class_table(source)
  }

  class_table
}

#' Load shipped class lookup table
#'
#' Reads a CSV class table bundled with the package for a known source.
#'
#' @param source Character. One of `"io-lulc"` or `"esa-worldcover"`.
#'
#' @return A tibble with columns `code`, `class_name`, `color`, `description`.
#'
#' @examples
#' dft_class_table("io-lulc")
#'
#' @export
dft_class_table <- function(source = c("io-lulc", "esa-worldcover")) {
  source <- match.arg(source)
  csv_name <- switch(source,
    "io-lulc" = "io_lulc_v02.csv",
    "esa-worldcover" = "esa_worldcover.csv"
  )
  path <- system.file("lulc_classes", csv_name, package = "drift", mustWork = TRUE)
  tibble::as_tibble(utils::read.csv(path, stringsAsFactors = FALSE))
}

#' Parse classification:classes from STAC items (internal)
#'
#' @param items rstac items collection
#' @return tibble or NULL
#' @noRd
stac_classes_from_items <- function(items) {
  if (length(items$features) == 0) return(NULL)

  props <- items$features[[1]]$properties
  # Check for classification extension
  classes <- props[["classification:classes"]]
  if (is.null(classes)) return(NULL)

  rows <- lapply(classes, function(cls) {
    tibble::tibble(
      code = as.integer(cls$value %||% cls$code %||% NA),
      class_name = cls$description %||% cls$name %||% NA_character_,
      color = format_color(cls$`color-hint` %||% cls$color %||% NA_character_),
      description = cls$description %||% NA_character_
    )
  })

  dplyr::bind_rows(rows)
}

#' Format color value to hex (internal)
#' @param x character color value
#' @return hex string or NA
#' @noRd
format_color <- function(x) {
  if (is.na(x) || is.null(x)) return(NA_character_)
  if (grepl("^#", x)) return(x)
  # Try to interpret as hex without #

  if (grepl("^[0-9a-fA-F]{6}$", x)) return(paste0("#", x))
  x
}

#' Null-coalescing operator (internal)
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Classify a raster with factor levels and colors
#'
#' Apply class names and a color table to a categorical `SpatRaster`, optionally
#' remapping (collapsing) classes into broader groups.
#'
#' @param x A [terra::SpatRaster] or a named list of `SpatRaster`s (e.g. from
#'   [dft_stac_fetch()]).
#' @param class_table A tibble with columns `code`, `class_name`, `color`
#'   (hex). When `NULL`, loaded via [dft_class_table()] using `source`.
#' @param source Character. Used to load a shipped class table when
#'   `class_table` is `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.
#' @param remap A named list for collapsing classes. Names are the new class
#'   names, values are character vectors of original `class_name`s to merge.
#'   For example, `list(Vegetation = c("Trees", "Rangeland"))`. When `NULL`,
#'   no remapping is applied.
#'
#' @return Same structure as `x` — a `SpatRaster` or named list — with
#'   [terra::levels()] and [terra::coltab()] set.
#' @export
#' @examples
#' r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
#' classified <- dft_rast_classify(r, source = "io-lulc")
#' terra::is.factor(classified)
dft_rast_classify <- function(x,
                              class_table = NULL,
                              source = "io-lulc",
                              remap = NULL) {
  if (is.null(class_table)) {
    class_table <- dft_class_table(source)
  }

  if (is.list(x) && !inherits(x, "SpatRaster")) {
    return(lapply(x, dft_rast_classify,
                  class_table = class_table, source = source, remap = remap))
  }

  if (!is.null(remap)) {
    remapped <- apply_remap(x, class_table, remap)
    x <- remapped$rast
    class_table <- remapped$class_table
  }

  # Filter class_table to codes actually present in raster
  present_codes <- terra::unique(x)[, 1]
  ct <- class_table[class_table$code %in% present_codes, ]

  # The order is load-bearing (#89). `x` is the caller's own raster, and
  # set.cats() works in place, so it must only ever reach a copy. `coltab<-`
  # deep-copies before setting (the fact strip_copy() in dft_rast_break_class.R
  # also relies on), so colours first and levels on that copy: one copy, where
  # an explicit deepcopy() before `coltab<-` would make two. Should terra make
  # `coltab<-` in place, the caller-unmodified test goes red.
  coltab_df <- data.frame(value = ct$code, col = ct$color)
  terra::coltab(x) <- coltab_df

  lvl_df <- data.frame(id = ct$code, class_name = ct$class_name)
  terra::set.cats(x, layer = 1, value = lvl_df)

  x
}


#' Apply remap to reclassify raster and rebuild class table
#' @noRd
apply_remap <- function(x, class_table, remap) {
  rcl_rows <- lapply(names(remap), function(new_name) {
    old_names <- remap[[new_name]]
    old_codes <- class_table$code[class_table$class_name %in% old_names]
    if (length(old_codes) == 0) {
      warning("No matching classes found for remap group '", new_name, "'")
      return(NULL)
    }
    new_code <- min(old_codes)
    data.frame(from = old_codes, to = new_code)
  })
  rcl <- do.call(rbind, rcl_rows)

  if (!is.null(rcl) && nrow(rcl) > 0) {
    x <- terra::classify(x, as.matrix(rcl), right = NA)
  }

  # Rebuild class_table with remapped groups
  new_rows <- lapply(names(remap), function(new_name) {
    old_names <- remap[[new_name]]
    old_codes <- class_table$code[class_table$class_name %in% old_names]
    if (length(old_codes) == 0) return(NULL)
    tibble::tibble(
      code = min(old_codes),
      class_name = new_name,
      color = class_table$color[class_table$code == min(old_codes)],
      description = new_name
    )
  })

  remapped_names <- unlist(remap, use.names = FALSE)
  kept <- class_table[!class_table$class_name %in% remapped_names, ]
  new_class_table <- dplyr::bind_rows(kept, dplyr::bind_rows(new_rows)) |>
    dplyr::arrange(.data$code)

  list(rast = x, class_table = new_class_table)
}

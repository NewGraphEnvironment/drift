#' Resolve the code -> class-name lookup for a transition
#'
#' Shared by [dft_rast_transition()] and [dft_rast_break_class()] so the two
#' label a pixel identically (#19). Precedence:
#'
#' 1. `class_table`, as supplied;
#' 2. `dft_class_table(source)` when `source` is given;
#' 3. the union of the rasters' own factor levels (layer 1, active category),
#'    since [dft_rast_classify()] keeps only the codes present in each year;
#' 4. otherwise an error: a plain integer raster carries no labels, and
#'    guessing a table is what used to label a remapped `Vegetation` as `Trees`
#'    and non-IO LULC codes as `NA`.
#'
#' Reading levels is metadata only; no cell is read.
#'
#' @param rasters A (named) list of `SpatRaster`s.
#' @param class_table,source As in [dft_rast_transition()].
#' @param fn Character. Calling function, for messages.
#' @return A data frame with integer `code` and character `class_name`, sorted
#'   by code. Every code is a whole number in 0-999, the range the
#'   `from * 1000 + to` encoding can decode.
#' @noRd
transition_class_table <- function(rasters, class_table = NULL, source = NULL,
                                   fn = "this function") {
  if (!is.null(class_table)) {
    lookup <- data.frame(code = class_table$code,
                         class_name = as.character(class_table$class_name))
  } else if (!is.null(source)) {
    ct <- dft_class_table(source)
    lookup <- data.frame(code = ct$code, class_name = as.character(ct$class_name))
  } else {
    lookup <- transition_levels(rasters, fn)
  }

  bad <- is.na(lookup$code) | lookup$code != round(lookup$code) |
    lookup$code < 0 | lookup$code > 999
  if (any(bad)) {
    stop(fn, "() encodes a transition as from * 1000 + to, so class codes must ",
         "be whole numbers in 0-999. Out of range: ",
         paste(utils::head(unique(lookup$code[bad]), 5), collapse = ", "), ".",
         call. = FALSE)
  }
  lookup$code <- as.integer(lookup$code)
  lookup <- lookup[order(lookup$code), , drop = FALSE]
  rownames(lookup) <- NULL
  lookup
}

#' Union of factor levels across rasters, or an error naming the unlabelled
#' @noRd
transition_levels <- function(rasters, fn) {
  lv <- lapply(rasters, function(r) {
    if (!terra::is.factor(r)[1]) return(NULL)
    l <- terra::levels(r)[[1]]
    if (is.null(l) || nrow(l) == 0) return(NULL)
    data.frame(code = l[[1]], class_name = as.character(l[[2]]))
  })
  unlabelled <- vapply(lv, is.null, logical(1))
  if (any(unlabelled)) {
    nm <- names(rasters)
    which_txt <- if (!is.null(nm) && all(nzchar(nm[unlabelled]) & !is.na(nm[unlabelled]))) {
      paste0("`", nm[unlabelled], "`", collapse = ", ")
    } else {
      paste0("element ", which(unlabelled), collapse = ", ")
    }
    stop(fn, "() needs class labels, and ", which_txt,
         " carries none (not a factor raster). Either classify first with ",
         "dft_rast_classify(), set the levels yourself with ",
         "terra::set.cats(r, layer = 1, value = data.frame(id = <codes>, ",
         "class_name = <labels>)), or pass `class_table =` or `source =`.",
         call. = FALSE)
  }

  all_lv <- do.call(rbind, unname(lv))
  all_lv <- all_lv[!is.na(all_lv$code), , drop = FALSE]
  all_lv <- unique(all_lv)
  dup <- unique(all_lv$code[duplicated(all_lv$code)])
  if (length(dup) > 0) {
    clash <- vapply(dup[seq_len(min(3, length(dup)))], function(k) {
      paste0(k, " (", paste(all_lv$class_name[all_lv$code == k], collapse = " / "), ")")
    }, character(1))
    stop(fn, "() found one code labelled differently across the rasters' ",
         "factor levels: ", paste(clash, collapse = ", "),
         ". Pass `class_table =` to decide the labels.", call. = FALSE)
  }
  all_lv
}

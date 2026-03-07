#' Compute per-pixel mode across classified rasters
#'
#' Given multiple classified rasters of the same extent and resolution,
#' compute the most frequent (mode) class at each pixel. Useful for
#' temporal smoothing — averaging out single-year misclassification noise
#' before running [dft_rast_transition()].
#'
#' @details
#' Mode smoothing filters single-year misclassification but cannot
#' distinguish noise from real change. A pixel that genuinely transitions
#' mid-window may be voted back to its original class if the pre-change
#' years outnumber the post-change years. See
#' \href{https://github.com/NewGraphEnvironment/drift/issues/9}{drift#9}
#' for discussion of weighted and breakpoint approaches.
#'
#' @param x A named list of classified `SpatRaster`s (e.g. from
#'   [dft_rast_classify()]). Rasters with slightly different extents are
#'   automatically resampled (nearest-neighbour) to the first raster's grid.
#' @param confidence Logical. If `TRUE`, return a second layer with the
#'   proportion of input rasters that agreed on the mode (e.g. 3/3 = 1.0,
#'   2/3 = 0.67). Default `FALSE`.
#'
#' @return A `SpatRaster`. When `confidence = FALSE`, a single-layer factor
#'   raster with the modal class. When `confidence = TRUE`, a two-layer
#'   raster: `"consensus"` (factor) and `"confidence"` (numeric 0–1).
#' @export
#' @examples
#' # Build 3 classified rasters from example data
#' r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
#' r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
#' r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
#' classified <- dft_rast_classify(
#'   list("2017" = r17, "2020" = r20, "2023" = r23), source = "io-lulc"
#' )
#'
#' # Consensus raster (modal class)
#' cons <- dft_rast_consensus(classified)
#' terra::plot(cons)
#'
#' # With confidence layer
#' cons2 <- dft_rast_consensus(classified, confidence = TRUE)
#' terra::plot(cons2[["confidence"]])
dft_rast_consensus <- function(x, confidence = FALSE) {
  if (!is.list(x) || inherits(x, "SpatRaster")) {
    stop("`x` must be a named list of SpatRasters, not a single SpatRaster.")
  }
  if (length(x) < 2) {
    stop("`x` must contain at least 2 rasters.")
  }

  # Align all rasters to the first raster's grid
  ref <- x[[1]]
  x <- lapply(x, function(r) {
    if (!terra::compareGeom(ref, r, stopOnError = FALSE)) {
      terra::resample(r, ref, method = "near")
    } else {
      r
    }
  })

  # Stack into matrix: rows = pixels, cols = rasters
  vals <- do.call(cbind, lapply(x, function(r) terra::values(r)[, 1]))
  n <- ncol(vals)

  # Per-pixel mode and count
  mode_result <- apply(vals, 1, function(row) {
    row <- row[!is.na(row)]
    if (length(row) == 0) return(c(NA_integer_, NA_real_))
    tab <- tabulate(match(row, unique(row)))
    uq <- unique(row)
    idx <- which.max(tab)
    c(uq[idx], tab[idx] / length(row))
  })

  mode_vals <- as.integer(mode_result[1, ])
  conf_vals <- mode_result[2, ]

  # Build output raster with factor levels from first input
  r_out <- terra::rast(x[[1]])
  terra::values(r_out) <- mode_vals

  # Copy factor levels if present
  if (terra::is.factor(x[[1]])) {
    lvls <- terra::cats(x[[1]])[[1]]
    # Only keep levels that appear in the consensus
    present <- unique(mode_vals[!is.na(mode_vals)])
    lvls_present <- lvls[lvls[[1]] %in% present, , drop = FALSE]
    terra::set.cats(r_out, layer = 1, value = lvls_present)
  }

  names(r_out) <- "consensus"

  if (confidence) {
    r_conf <- terra::rast(x[[1]])
    terra::values(r_conf) <- conf_vals
    names(r_conf) <- "confidence"
    r_out <- c(r_out, r_conf)
  }

  r_out
}

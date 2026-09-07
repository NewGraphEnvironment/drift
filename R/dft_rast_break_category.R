#' Temporal category of every pixel in a break-class scan
#'
#' [dft_break_category()] at pixel grain: the same `"v1"` rule, applied to the
#' per-pixel measurements rather than to the summary rows, so the label can be
#' mapped, patched, or crossed against anything else on the grid.
#'
#' @param x The list returned by [dft_rast_break_class()]. `$breaks` supplies
#'   the measurements and `$raster` whether the endpoints differ. `$years` is
#'   **not** needed here and not required: `n_before` and `n_after` are measured
#'   per pixel, so the strength is read off them rather than recovered from
#'   `break_year` the way [dft_break_category()] must do at row grain. A result
#'   saved before drift 0.16.0 therefore works unchanged.
#' @param rule Character. The labelling rule; only `"v1"` exists. Recorded on
#'   the result as the `drift_break_rule` metadata tag, and implied by the
#'   category level labels themselves.
#' @param filename Character or `NULL`. Where to write the result. A
#'   floodplain-scale grid is worth putting somewhere you chose; `NULL` writes
#'   a temporary file that R removes at the end of the session.
#'
#'   The **file** carries the integer codes `0:4`, not the labels: the levels
#'   are set on the returned object after the write, so no `.tif.aux.xml` RAT
#'   sidecar is produced — one whose loss is silent, and which the rest of this
#'   package avoids for that reason. `terra::rast(filename)` therefore returns a
#'   plain integer raster; re-attach labels with the id order in `@return`, or
#'   keep the object this returns.
#' @param overwrite Logical. Replace `filename` if it already exists. terra
#'   refuses by default and its error names this remedy, so the argument has to
#'   exist for the message to be actionable.
#'
#' @return A two-layer `SpatRaster`:
#'   - `category` — a factor with ids `0:4` labelled `stable`,
#'     `break_sustained`, `break_endpoint`, `unsettled`, `stable_flicker`, in
#'     that order
#'   - `strength` — [dft_break_strength()] as an integer, `NA` off a clean
#'     switch
#'
#'   `NA` where the pixel could not be scanned, which is every pixel with an
#'   `NA` in any year.
#'
#' @details
#' The rule, the reason levels 3 and 4 must never be summed, and why the
#' threshold is not an argument are all documented once, under
#' [dft_break_category()].
#'
#' @section Memory:
#' One streamed [terra::app()] pass over `$breaks` plus the transition layer,
#' written straight to `filename` — nothing full-grid is pulled into R, and the
#' chunk size is bounded rather than left to terra's memory heuristic, which
#' takes a 192M-cell grid in one or two chunks on a large machine.
#'
#' @seealso [dft_break_category()] for the same rule over summary rows;
#'   [dft_rast_break_class()] for the measurements.
#'
#' @export
#' @examples
#' years <- 2017:2023
#' rasters <- lapply(years, function(yr) {
#'   terra::rast(system.file("extdata", paste0("example_", yr, ".tif"),
#'                           package = "drift"))
#' })
#' names(rasters) <- years
#' res <- dft_rast_break_class(dft_rast_classify(rasters, source = "io-lulc"))
#'
#' cat_r <- dft_rast_break_category(res)
#' terra::plot(cat_r[["category"]])
#'
#' # pixel grain and summary grain are the same rule, so they agree
#' terra::freq(cat_r[["category"]])
dft_rast_break_category <- function(x, rule = "v1", filename = NULL,
                                    overwrite = FALSE) {
  break_rule_check(rule)

  if (is.data.frame(x) || !is.list(x)) {
    stop("`x` must be a `dft_rast_break_class()` result. For a summary data ",
         "frame use `dft_break_category()`.", call. = FALSE)
  }
  # `years` is deliberately NOT required: nothing here reads it, so demanding it
  # would refuse a result saved before 0.16.0 for no reason.
  for (el in c("raster", "breaks")) {
    if (is.null(x[[el]])) {
      stop("`x` carries no `", el, "`. Expected a `dft_rast_break_class()` result.",
           call. = FALSE)
    }
  }
  breaks <- x[["breaks"]]
  trans <- x[["raster"]]
  if (!inherits(breaks, "SpatRaster") || !inherits(trans, "SpatRaster")) {
    stop("`x$breaks` and `x$raster` must be SpatRasters.", call. = FALSE)
  }
  need <- c("break_year", "n_before", "n_after", "n_flips")
  if (!identical(names(breaks), need)) {
    stop("`x$breaks` must have layers ", paste(need, collapse = ", "),
         "; got ", paste(names(breaks), collapse = ", "), ".", call. = FALSE)
  }
  if (!terra::compareGeom(trans, breaks, stopOnError = FALSE)) {
    stop("`x$raster` and `x$breaks` are on different grids.", call. = FALSE)
  }
  if (!is.null(filename) && (!is.character(filename) || length(filename) != 1L)) {
    stop("`filename` must be a single path or NULL.", call. = FALSE)
  }
  if (!isTRUE(overwrite) && !isFALSE(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }

  files <- character(0)
  tmpf <- function() {
    f <- tempfile(pattern = "dft_break_category_", fileext = ".tif")
    files <<- c(files, f)
    f
  }
  # Intermediates only; the file the returned raster points at is taken off
  # this list before returning. Guarded on length: paste0(character(0),
  # ".aux.xml") is ".aux.xml", which unlink() resolves in the working directory.
  on.exit(if (length(files)) unlink(c(files, paste0(files, ".aux.xml"))), add = TRUE)

  # strip_copy() gives a level- and colour-free copy so app() sees plain codes
  # and terra writes no RAT sidecar for the input; the caller's raster is
  # untouched (`coltab<-` deep-copies before set.cats() reaches it).
  stack <- c(breaks, strip_copy(trans))

  # terra::app() infers the output shape from a test chunk of min(ncol, 13)
  # cells and checks ncol(result) == ntest BEFORE nrow(result) == ntest, so a
  # two-column return on a two-column raster is read as TRANSPOSED and written
  # across layers with no warning. Measured on terra 1.9.34: widths 1 and 3-6
  # are correct, 2 is scrambled. Pad by one column for the scan and crop back.
  # (The parent pads at ncol == 5 because its return is five columns.)
  pad <- terra::ncol(stack) == 2L
  if (pad) {
    e <- terra::ext(stack)
    e_pad <- terra::ext(e$xmin, e$xmax + terra::res(stack)[1], e$ymin, e$ymax)
    stack <- terra::extend(stack, e_pad, filename = tmpf())
  }

  # `steps` bounds the chunk terra hands the closure: left to its memory
  # heuristic a 64 GB machine takes a 192M-cell grid in one or two chunks, and
  # the R-side matrices alone then cost ~10 GB. Five input layers here, as in
  # the parent, so use the same 2.5M-cell bound.
  steps <- max(1L, as.integer(ceiling(terra::ncell(stack) / 2.5e6)))
  out_file <- if (pad || is.null(filename)) tmpf() else filename
  out <- terra::app(stack, fun = break_category_scan(), filename = out_file,
                    overwrite = isTRUE(overwrite) && identical(out_file, filename),
                    wopt = list(datatype = "INT1U", gdal = "COMPRESS=LZW",
                                steps = steps))
  if (pad) {
    out_file <- if (is.null(filename)) tmpf() else filename
    out <- terra::crop(out, terra::ext(breaks), filename = out_file,
                       overwrite = isTRUE(overwrite) && identical(out_file, filename),
                       wopt = list(datatype = "INT1U", gdal = "COMPRESS=LZW"))
  }
  names(out) <- c("category", "strength")

  lv <- break_category_levels()
  terra::set.cats(out, layer = 1,
                  value = data.frame(id = seq_along(lv) - 1L, category = lv))
  terra::metags(out) <- c(drift_break_rule = rule)

  files <- setdiff(files, out_file)
  out
}

#' Build the per-chunk category function for [dft_rast_break_category()]
#'
#' Maps a cells x 5 matrix (`break_year`, `n_before`, `n_after`, `n_flips`,
#' `transition`) to a cells x 2 matrix (`category`, `strength`).
#'
#' terra::app() first tries `apply(chunk, 1, fun)` — one R call per CELL — and
#' falls back to `fun(chunk)` only when that errors, so a `fun` that tolerates a
#' bare vector silently runs per cell (57x slower on a 600 x 600 x 7 stack, with
#' identical values). Refusing anything but a matrix forces the vectorised path.
#' @noRd
break_category_scan <- function() {
  function(v) {
    if (!is.matrix(v)) stop("matrix chunks only")
    strength <- pmin(v[, 2L], v[, 3L])
    tr <- v[, 5L]
    # the transition code is from * 1000 + to, so the endpoints differ exactly
    # when its two halves do. NA transition -> NA changed -> NA category.
    changed <- (tr %/% 1000) != (tr %% 1000)
    cbind(category = break_category_code(v[, 4L], strength, changed),
          strength = strength)
  }
}

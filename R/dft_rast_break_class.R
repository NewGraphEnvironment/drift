#' Detect sustained class switches across an annual classified series
#'
#' Scan each pixel's class sequence across a named list of classified rasters
#' (one per year) and report whether it is **stable**, a **clean switch** (class
#' A for N years, then class B for M years, and nothing else) or **flicker**
#' (more than one change of class). A clean switch is dated. This is the
#' temporal, categorical-only leg of change QA: where
#' [dft_transition_artifact()] asks whether a patch has the *shape* of a
#' registration artifact and [dft_rast_break()] asks whether the *spectral*
#' signal actually moved, this asks whether the labels themselves settled.
#'
#' @param x A named list of classified `SpatRaster`s (e.g. from
#'   [dft_rast_classify()]), one per year, whose names parse as integer years
#'   (`"2017"`, ...). Order does not matter; layers are sorted by year. At
#'   least two, each single-layer and in the same CRS. Rasters on a different
#'   grid from the first are resampled to it (nearest neighbour).
#' @param class_table A tibble with columns `code`, `class_name`, `color`.
#'   When `NULL`, loaded via [dft_class_table()] using `source`.
#' @param source Character. Used to load a shipped class table when
#'   `class_table` is `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.
#' @param unit Character. Area unit for the summary. One of `"ha"`
#'   (default), `"km2"`, or `"m2"`.
#'
#' @return A list with three elements:
#'   - `raster`: a single-layer factor `SpatRaster` named `transition`,
#'     encoding the **first-year to last-year** class pair of every pixel as
#'     `from * 1000 + to` with levels labelled `"from_class -> to_class"` —
#'     identical to `dft_rast_transition(x, from = <first>, to = <last>)$raster`,
#'     so it feeds [dft_transition_vectors()] and [dft_transition_artifact()]
#'     unchanged.
#'   - `breaks`: a four-layer integer `SpatRaster` of per-pixel evidence:
#'     - `break_year` — the first year of the new class for a clean switch;
#'       `NA` for stable and flicker pixels
#'     - `n_before`, `n_after` — years in the old and new class either side of
#'       the switch; `NA` unless `n_flips == 1`. Confidence is `min(n_before,
#'       n_after)`: a pixel whose last year alone differs is a clean switch
#'       with `n_after == 1`, and one whose first year alone differs has
#'       `n_before == 1`.
#'     - `n_flips` — number of year-to-year class changes: `0` stable, `1` a
#'       clean switch, `2` or more flicker
#'   - `summary`: a tibble with one row per (`from_class`, `to_class`,
#'     `status`, `break_year`) with `n_cells`, `area` and `pct` of all valid
#'     pixels. `status` is `"stable"` (`n_flips == 0`), `"break"` (`1`) or
#'     `"flicker"` (`>= 2`), or `NA` where an interior year is `NA`;
#'     `break_year` is `NA` except for `"break"` rows.
#'
#' @details
#' A two-epoch comparison such as 2017 -> 2023 reports every pixel whose label
#' differs between the endpoints. This function splits that set: pixels with a
#' clean, dated switch; pixels that differ between the endpoints but flicker in
#' between (label noise — the borderline pixels that carry no spectral break);
#' and pixels that differ only because the first or last year is itself the odd
#' one out (`n_before == 1` or `n_after == 1`). It also finds what the
#' two-epoch comparison cannot: a pixel that switched and switched back, which
#' reads as stable on the endpoints and is flicker here.
#'
#' No threshold is applied — every measurement is reported and the caller
#' composes, e.g. `n_flips == 1 & pmin(n_before, n_after) >= 2` for a switch
#' sustained at least two years on each side. Compare [dft_rast_consensus()],
#' which votes a real mid-window switch back to its old class because the
#' pre-change years outnumber the post-change ones; here that pixel is a dated
#' break.
#'
#' `break_year` is an integer calendar year, unlike `break_date` from
#' [dft_rast_break()], which is a decimal year from a monthly spectral series.
#'
#' `NA` handling follows the two-epoch comparison: the transition layer is `NA`
#' where the first or last year is `NA`, exactly as [dft_rast_transition()]
#' propagates `NA` from either epoch. An `NA` in any *interior* year leaves the
#' transition in place but makes all four evidence layers `NA` — the sequence
#' cannot be scanned — and such pixels appear in `summary` with `status` `NA`.
#' Note that IO LULC carries `No Data` (code 0) and `Clouds` (code 10) as real
#' classes rather than `NA`, so a cloudy year counts as a flip; remap or mask
#' them first if that is not wanted.
#'
#' @section Memory:
#' The scan is a single streamed [terra::app()] pass over the stacked series,
#' written to a temporary LZW-compressed file, and the summary is a
#' [terra::crosstab()] over that file — nothing full-grid is pulled into R.
#' Scale numbers for a 169M-cell floodplain grid (the BULK watershed group at
#' 10 m, seven years) are in `NEWS.md`.
#'
#' @seealso [dft_rast_transition()] for the two-epoch comparison this splits;
#'   [dft_transition_vectors()] and [dft_transition_artifact()], which take
#'   `$raster` unchanged; [dft_rast_consensus()] for the mode filter this
#'   supersedes; [dft_rast_break()] for the spectral route.
#'
#' @export
#' @examples
#' years <- c(2017, 2020, 2023)
#' rasters <- lapply(years, function(yr) {
#'   terra::rast(system.file("extdata", paste0("example_", yr, ".tif"),
#'                           package = "drift"))
#' })
#' names(rasters) <- years
#' classified <- dft_rast_classify(rasters, source = "io-lulc")
#'
#' res <- dft_rast_break_class(classified)
#' res$summary
#'
#' # dated switches vs flicker among pixels that differ between the endpoints
#' terra::plot(res$breaks[["break_year"]])
#' terra::plot(res$breaks[["n_flips"]])
#'
#' # the transition layer feeds the patch tools unchanged
#' patches <- dft_transition_vectors(res$raster, changes_only = TRUE)
#' tagged <- dft_transition_artifact(patches, res$raster)
#' head(sf::st_drop_geometry(tagged))
dft_rast_break_class <- function(x,
                                 class_table = NULL,
                                 source = "io-lulc",
                                 unit = "ha") {
  unit <- match.arg(unit, c("ha", "km2", "m2"))

  if (!is.list(x) || inherits(x, "SpatRaster")) {
    stop("`x` must be a named list of SpatRasters, not a single SpatRaster.",
         call. = FALSE)
  }
  if (length(x) < 2) {
    stop("`x` must contain at least 2 rasters.", call. = FALSE)
  }
  if (!all(vapply(x, inherits, logical(1), "SpatRaster"))) {
    stop("Every element of `x` must be a SpatRaster.", call. = FALSE)
  }
  if (!all(vapply(x, terra::nlyr, numeric(1)) == 1)) {
    stop("Every element of `x` must be a single-layer SpatRaster.", call. = FALSE)
  }
  nm <- names(x)
  if (is.null(nm) || any(is.na(nm)) || !all(grepl("^[0-9]{4}$", nm))) {
    stop("Names of `x` must be four-digit years (e.g. \"2017\").", call. = FALSE)
  }
  years <- as.integer(nm)
  if (anyDuplicated(years) > 0) {
    stop("Names of `x` must be unique years.", call. = FALSE)
  }
  ord <- order(years)
  x <- x[ord]
  years <- years[ord]
  n <- length(years)

  if (is.null(class_table)) {
    class_table <- dft_class_table(source)
  }
  code_lookup <- stats::setNames(class_table$class_name, class_table$code)

  for (r in x) dft_check_crs(r, "dft_rast_break_class")

  files <- character(0)
  tmpf <- function() {
    f <- tempfile(pattern = "dft_break_class_", fileext = ".tif")
    files <<- c(files, f)
    f
  }
  # Intermediates are unlinked on exit; the output file is not (the returned
  # rasters point at it).
  # terra writes a RAT sidecar beside any factor it writes; remove those too.
  # Guarded on length: paste0(character(0), ".aux.xml") is ".aux.xml", which
  # unlink() would resolve in the caller's working directory.
  on.exit(if (length(files)) unlink(c(files, paste0(files, ".aux.xml"))), add = TRUE)

  # Align every layer to the first grid (nearest neighbour, streamed) and stack.
  # rast(list) isolates the stack's metadata from the caller's objects
  # (measured for in-memory, file-backed, shared and subset inputs), so the
  # levels are stripped IN PLACE on the stack with set.cats(NULL) — which,
  # unlike `levels<-`, neither copies the values nor would spare a caller's
  # raster if misapplied, so the caller-unmutated test guards the placement.
  ref <- x[[1]]
  aligned <- lapply(x, function(r) {
    if (!terra::same.crs(ref, r)) {
      stop("Every raster in `x` must share the CRS of the first; `resample()` ",
           "aligns grids but does not reproject. Use terra::project() first.",
           call. = FALSE)
    }
    if (!terra::compareGeom(ref, r, stopOnError = FALSE)) {
      # a palette warns on a non-byte band, and a factor is written with a RAT
      # sidecar the cleanup below would otherwise have to remove: strip a copy
      terra::resample(strip_copy(r), ref, method = "near", filename = tmpf())
    } else if (terra::inMemory(r)) {
      # rast(list) COPIES an in-memory source: seven 192M-cell rasters (what
      # dft_stac_fetch() returns when they fit) would cost ~10 GB again.
      # Spill each to a compressed temp file instead; the copy is a transient
      # of one layer.
      terra::writeRaster(strip_copy(r), tmpf(), datatype = "INT4S",
                         gdal = "COMPRESS=LZW")
    } else {
      r
    }
  })
  stack <- terra::rast(aligned)
  for (i in seq_len(n)) terra::set.cats(stack, layer = i, value = NULL)

  # terra::app() infers the output shape from a test chunk of min(ncol, 13)
  # cells and reads a 5-column return on a 5-column raster as TRANSPOSED,
  # scrambling cells across layers with no warning. Pad such a stack by one NA
  # column for the scan and crop it back afterwards (a 5-column raster is tiny,
  # so the extra pass costs nothing).
  pad <- terra::ncol(ref) == 5L
  if (pad) {
    # extend() writes the stack, and GDAL warns on a colour table in a
    # multi-band file; `coltab<-` strips one layer per call (and copies), which
    # is free on a 5-column raster.
    for (i in seq_len(n)) terra::coltab(stack, layer = i) <- NULL
    e <- terra::ext(ref)
    e_pad <- terra::ext(e$xmin, e$xmax + terra::res(ref)[1], e$ymin, e$ymax)
    stack <- terra::extend(stack, e_pad, filename = tmpf())
  }

  scan <- break_class_scan(n, years)

  # The output file is on the cleanup list until the moment a result that
  # points at it is returned, so any abort in between (the overflow handler,
  # crosstab, ...) does not strand a partial full-grid file.
  # `steps` bounds the chunk terra hands to `scan`: left to its memory
  # heuristic, a 64 GB machine takes a 192M-cell grid in one or two chunks and
  # the chunk's R-side matrices alone cost ~10 GB (measured on BULK); at
  # 9.6M-cell chunks the scan still peaked near 10 GB, at 2.5M it is a few.
  steps <- max(1L, as.integer(ceiling(terra::ncell(stack) / 2.5e6)))
  out_file <- tmpf()
  out <- withCallingHandlers(
    terra::app(stack, fun = scan, filename = out_file,
               wopt = list(datatype = "INT4S", gdal = "COMPRESS=LZW", steps = steps)),
    warning = function(w) {
      if (grepl("outside of the limits of datatype", conditionMessage(w))) {
        stop("class codes overflow the transition encoding (from * 1000 + to): ",
             conditionMessage(w), call. = FALSE)
      }
    }
  )
  if (pad) {
    out_file <- tmpf()
    out <- terra::crop(out, ref, filename = out_file)
  }
  names(out) <- c("transition", "break_year", "n_before", "n_after", "n_flips")

  # Summary before any categories are set (crosstab reports labels once they
  # are), with useNA so stable/flicker pixels (NA break_year) are kept.
  status <- terra::app(out[["n_flips"]], fun = function(v) pmin(v, 2L),
                       filename = tmpf(), wopt = list(datatype = "INT1U"))
  ct <- terra::crosstab(c(out[["transition"]], status, out[["break_year"]]),
                        long = TRUE, useNA = TRUE)
  names(ct) <- c("code", "status", "break_year", "n_cells")
  ct <- ct[!is.na(ct$code), , drop = FALSE]

  cell_area_m2 <- prod(terra::res(ref))
  m2_to_unit <- switch(unit, "m2" = 1, "ha" = 1e-4, "km2" = 1e-6)
  cell_area <- cell_area_m2 * m2_to_unit

  r_trans <- out[["transition"]]
  if (nrow(ct) == 0) {
    terra::set.cats(r_trans, layer = 1,
                    value = data.frame(id = integer(0), transition = character(0)))
    summary_tbl <- tibble::tibble(
      from_class = character(0), to_class = character(0),
      status = character(0), break_year = integer(0),
      n_cells = integer(0), area = numeric(0), pct = numeric(0)
    )
    files <- setdiff(files, out_file)
    return(list(raster = r_trans, breaks = out[[2:5]], summary = summary_tbl))
  }

  code <- as.integer(ct$code)
  from_codes <- code %/% 1000L
  to_codes <- code %% 1000L
  status_lab <- c("stable", "break", "flicker")[as.integer(ct$status) + 1L]  # NA stays NA
  total_valid <- sum(ct$n_cells)
  summary_tbl <- tibble::tibble(
    from_class = unname(code_lookup[as.character(from_codes)]),
    to_class = unname(code_lookup[as.character(to_codes)]),
    status = status_lab,
    break_year = as.integer(ct$break_year),
    n_cells = as.integer(ct$n_cells),
    area = ct$n_cells * cell_area,
    pct = round(ct$n_cells / total_valid * 100, 2)
  )
  summary_tbl <- summary_tbl[order(summary_tbl$n_cells, decreasing = TRUE), ]

  # Factor levels on the transition layer, exactly as dft_rast_transition()
  # sets them (id = from * 1000 + to, label column `transition`).
  codes_present <- sort(unique(code))
  labels <- paste0(
    code_lookup[as.character(codes_present %/% 1000L)], " -> ",
    code_lookup[as.character(codes_present %% 1000L)]
  )
  terra::set.cats(r_trans, layer = 1,
                  value = data.frame(id = codes_present, transition = labels))

  files <- setdiff(files, out_file)
  list(raster = r_trans, breaks = out[[2:5]], summary = summary_tbl)
}

#' Build the per-chunk scan function for [dft_rast_break_class()]
#'
#' Returns a closure over `n` (years in the stack) and `years` that maps a
#' cells x n matrix of class codes to a cells x 5 matrix
#' (`transition`, `break_year`, `n_before`, `n_after`, `n_flips`).
#'
#' terra::app() first tries `apply(chunk, 1, fun)` — one R call per CELL — and
#' falls back to `fun(chunk)` only when that errors. A `fun` that tolerates a
#' bare vector therefore silently runs per cell (measured 57x slower on a
#' 600 x 600 x 7 stack), so the closure refuses anything but a matrix to force
#' the vectorised path. Chunks always arrive as matrices, single cells included.
#' @noRd
break_class_scan <- function(n, years) {
  force(n)
  force(years)
  function(v) {
    if (!is.matrix(v)) stop("matrix chunks only")
    chg <- v[, -1L, drop = FALSE] != v[, -n, drop = FALSE]
    n_flips <- rowSums(chg)                         # NA if any NA in the row
    idx <- max.col(chg, ties.method = "first")      # NA on NA rows, 1 on all-FALSE
    one <- !is.na(n_flips) & n_flips == 1L
    break_year <- rep(NA_integer_, nrow(v))
    n_before <- rep(NA_integer_, nrow(v))
    n_after <- rep(NA_integer_, nrow(v))
    break_year[one] <- years[idx[one] + 1L]
    n_before[one] <- idx[one]
    n_after[one] <- n - idx[one]
    # NA only where an endpoint is NA, so the layer stays identical to the
    # two-epoch comparison; an interior NA blanks the evidence layers only.
    # Computed in double: file-backed integer sources arrive as an integer
    # matrix, and `* 1000L` would overflow in R (NA with R's own warning)
    # before terra's writer, whose overflow warning is the one caught below.
    transition <- as.double(v[, 1L]) * 1000 + as.double(v[, n])
    cbind(transition = transition, break_year = break_year,
          n_before = n_before, n_after = n_after, n_flips = n_flips)
  }
}


#' A level- and colour-free copy of a single-layer raster, the caller untouched
#'
#' `coltab<-` returns a copy (terra deep-copies unconditionally, before any
#' branch), and `set.cats(NULL)` then strips the levels IN PLACE on that copy —
#' one copy, not the two an explicit `deepcopy()` before `coltab<-` would make.
#' Should terra ever make `coltab<-` in-place, `set.cats()` would reach the
#' caller and the caller-unmutated test goes red. The colour strip is
#' load-bearing: a palette warns on every non-byte write. The level strip is
#' belt and braces: it stops terra writing a RAT sidecar at all, and the exit
#' handler would remove one anyway; the stack is stripped again after stacking.
#' @noRd
strip_copy <- function(r) {
  terra::coltab(r, layer = 1) <- NULL
  terra::set.cats(r, layer = 1, value = NULL)
  r
}

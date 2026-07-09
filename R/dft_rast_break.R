#' Detect per-pixel index-trajectory breakpoints
#'
#' Reduce a monthly index stack (from [dft_stac_cube()]) over time with
#' [bfast::bfastmonitor()], returning a two-band `SpatRaster` of the break date
#' and magnitude for every pixel. Where categorical differencing compares two
#' land-cover labels, this asks a stronger question of a continuous index
#' trajectory: *when* did the pixel's spectral history break, and by how much?
#'
#' `bfastmonitor` fits a season-trend model to a stable *history* period, then
#' watches the *monitoring* period (from `start` onward) for a structural break.
#' The returned `break_mag` is the median monitoring-period residual: **negative
#' means the index dropped** (e.g. vegetation loss / channel scour), positive
#' means it rose (establishment). `break_date` is a decimal year (e.g.
#' `2022.42`) or `NA` where no break was detected.
#'
#' Pixels are reduced in parallel with `parallel::mclapply()` (forked workers, so
#' the per-pixel logic and its parameters are inherited directly). Pixels with
#' fewer than `min_obs` valid observations short-circuit to `NA`.
#'
#' @param cube A monthly index `SpatRaster` (the return value of
#'   [dft_stac_cube()]): one layer per time step, with a time value per layer.
#' @param history Character. `bfastmonitor` history-selection method: `"all"`
#'   (default), `"ROC"`, or `"BP"`.
#' @param start Numeric `c(year, period)`. Start of the monitoring period, in the
#'   stack's temporal frequency (e.g. `c(2022, 1)` = Jan 2022 for a monthly
#'   stack). Everything before it is the stable history.
#' @param frequency Numeric or `NULL`. Seasonal frequency of the time series
#'   (12 for monthly, 1 for annual). When `NULL`, derived from the layer time
#'   spacing; when supplied, it must agree with that spacing or the call errors.
#' @param order Integer. Harmonic order of the season-trend model passed to
#'   [bfast::bfastmonitor()] (default 3). Lower it (1-2) when the series samples
#'   only part of the year (e.g. a growing-season-only cube from
#'   [dft_stac_cube()] `months`), where a high order overfits sparse seasonal
#'   coverage.
#' @param level Numeric. Significance level passed to [bfast::bfastmonitor()]
#'   (default 0.01).
#' @param min_obs Integer. Minimum non-`NA` observations required to attempt a
#'   fit; pixels with fewer return `NA` (default 6).
#' @param cores Integer or `NULL`. Forked workers for the per-pixel reduction.
#'   When `NULL`, uses one fewer than the detected cores.
#'
#' @return A two-band [terra::SpatRaster] with layers `break_date` (decimal year
#'   or `NA`) and `break_mag` (signed index change; negative = index drop).
#'
#' @seealso [dft_stac_cube()] (builds the input stack), [dft_index_expr()].
#'
#' @examples
#' \dontrun{
#' # Requires network + gdalcubes + bfast
#' aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
#' cube <- dft_stac_cube(aoi, index = "kndvi", datetime = "2019-01-01/2023-12-31")
#' breaks <- dft_rast_break(cube, start = c(2022, 1))
#' terra::plot(breaks[["break_mag"]])  # negative (blue) = scour / veg loss
#' }
#'
#' @export
dft_rast_break <- function(cube,
                           history = "all",
                           start = c(2022, 1),
                           frequency = NULL,
                           order = 3,
                           level = 0.01,
                           min_obs = 6,
                           cores = NULL) {
  rlang::check_installed("bfast", reason = "for trajectory breakpoint detection")
  if (!inherits(cube, "SpatRaster")) {
    cli::cli_abort("`cube` must be a SpatRaster time stack from {.fn dft_stac_cube}.")
  }
  tm <- terra::time(cube)
  if (length(tm) != terra::nlyr(cube) || anyNA(tm)) {
    cli::cli_abort(c(
      "`cube` must carry a time value for every layer.",
      "i" = "Pass the stack returned by {.fn dft_stac_cube}."
    ))
  }

  # derive the ts() start and seasonal frequency from the layer times
  cadence_freq <- cadence_frequency(tm)
  if (is.na(cadence_freq)) {
    cli::cli_abort("Unsupported layer cadence; use a monthly or annual stack.")
  }
  if (is.null(frequency)) {
    frequency <- cadence_freq
  } else if (!isTRUE(all.equal(as.numeric(frequency), as.numeric(cadence_freq)))) {
    cli::cli_abort(c(
      "`frequency` ({frequency}) disagrees with the layer cadence (= {cadence_freq}).",
      "i" = "Leave `frequency = NULL` to derive it from the stack."
    ))
  }
  t0 <- as.Date(tm[1])
  yr <- as.integer(format(t0, "%Y"))
  mo <- as.integer(format(t0, "%m"))
  ts_start <- c(yr, floor((mo - 1) / (12 / frequency)) + 1)

  if (is.null(cores)) {
    dc <- parallel::detectCores()
    cores <- if (is.na(dc)) 2L else max(1L, dc - 1L)
  }

  # reduce only pixels with a usable series; the rest stay NA
  vals <- terra::values(cube)
  usable <- which(rowSums(!is.na(vals)) >= min_obs)
  res <- matrix(NA_real_, nrow(vals), 2)
  if (length(usable)) {
    chunks <- split(usable, (seq_along(usable) - 1) %% cores)
    parts <- parallel::mclapply(chunks, function(ii) {
      t(vapply(ii, function(i) {
        .dft_break_pixel(vals[i, ], ts_start, frequency, start, history, order,
                         level, min_obs)
      }, numeric(2)))
    }, mc.cores = cores)
    for (k in seq_along(chunks)) res[chunks[[k]], ] <- parts[[k]]
  }

  out <- cube[[1:2]]
  terra::values(out) <- res
  names(out) <- c("break_date", "break_mag")
  out
}


#' Per-pixel breakpoint reducer logic (internal, unit-testable)
#'
#' The degenerate branches (all-`NA` or fewer than `min_obs` observations) return
#' `c(NA, NA)` before any `bfast` symbol is touched, so they are testable without
#' bfast installed.
#' @noRd
.dft_break_pixel <- function(v, ts_start, frequency, start, history, order,
                             level, min_obs) {
  if (all(is.na(v)) || sum(!is.na(v)) < min_obs) return(c(NA_real_, NA_real_))
  ts_v <- stats::ts(v, start = ts_start, frequency = frequency)
  tryCatch({
    m <- bfast::bfastmonitor(ts_v, start = start, history = history,
                             order = order, level = level)
    c(m$breakpoint, m$magnitude)
  }, error = function(e) c(NA_real_, NA_real_))
}


#' Seasonal frequency implied by a stack's layer times (internal)
#'
#' Monthly spacing -> 12, quarterly -> 4, annual -> 1. Returns `NA` for
#' unsupported cadences.
#' @noRd
cadence_frequency <- function(tm) {
  if (length(tm) < 2) return(NA_real_)
  d <- stats::median(as.numeric(diff(as.Date(tm))))
  if (is.na(d)) return(NA_real_)
  if (d >= 26 && d <= 32) return(12)
  if (d >= 85 && d <= 95) return(4)
  if (d >= 360 && d <= 370) return(1)
  NA_real_
}

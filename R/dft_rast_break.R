#' Detect per-pixel index-trajectory breakpoints
#'
#' Reduce an index cube (from [dft_stac_cube()]) over time with
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
#' The reducer runs as a per-pixel R callback. gdalcubes evaluates that callback
#' in spawned worker processes, so the function is built self-contained (its
#' parameters are baked in as literals) and `bfast` is loaded in each worker —
#' making the result independent of the `gdalcubes::gdalcubes_options(parallel=)`
#' setting.
#'
#' @param cube A `gdalcubes` index cube whose single band is a spectral index
#'   time series (the return value of [dft_stac_cube()]).
#' @param band Character. Band to reduce. When `NULL`, the cube's first band.
#' @param history Character. `bfastmonitor` history-selection method: `"all"`
#'   (default), `"ROC"`, or `"BP"`.
#' @param start Numeric `c(year, period)`. Start of the monitoring period, in the
#'   cube's temporal frequency (e.g. `c(2022, 1)` = Jan 2022 for a monthly cube).
#'   Everything before it is the stable history.
#' @param frequency Numeric or `NULL`. Seasonal frequency of the time series
#'   (12 for monthly, 1 for annual). When `NULL`, derived from the cube's
#'   temporal cadence; when supplied, it must agree with that cadence or the
#'   call errors.
#' @param level Numeric. Significance level passed to [bfast::bfastmonitor()]
#'   (default 0.01).
#' @param min_obs Integer. Minimum non-`NA` observations required to attempt a
#'   fit; pixels with fewer return `NA` (default 6).
#' @param cache_dir Character. Cache directory. When `NULL`, [dft_cache_path()].
#' @param force Logical. Recompute even if cached (default `FALSE`).
#'
#' @return A two-band [terra::SpatRaster] with layers `break_date` (decimal year
#'   or `NA`) and `break_mag` (signed index change; negative = index drop).
#'
#' @seealso [dft_stac_cube()] (builds the input cube), [dft_index_expr()].
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
                           band = NULL,
                           history = "all",
                           start = c(2022, 1),
                           frequency = NULL,
                           level = 0.01,
                           min_obs = 6,
                           cache_dir = NULL,
                           force = FALSE) {
  rlang::check_installed("gdalcubes", reason = "to reduce a data cube over time")
  rlang::check_installed("bfast", reason = "for trajectory breakpoint detection")

  band <- band %||% gdalcubes::bands(cube)$name[[1]]

  # derive the ts() start and seasonal frequency from the cube time axis, in the
  # main process (the reducer callback cannot see the cube)
  tdim <- gdalcubes::dimensions(cube)$t
  cadence_freq <- cadence_frequency(tdim$pixel_size)
  if (is.na(cadence_freq)) {
    cli::cli_abort(c(
      "Unsupported cube temporal cadence {.val {tdim$pixel_size}}.",
      "i" = "Use a monthly (`P1M`) or annual (`P1Y`) cube."
    ))
  }
  if (is.null(frequency)) {
    frequency <- cadence_freq
  } else if (!isTRUE(all.equal(as.numeric(frequency), as.numeric(cadence_freq)))) {
    cli::cli_abort(c(
      "`frequency` ({frequency}) disagrees with the cube cadence \\
       {.val {tdim$pixel_size}} (= {cadence_freq}).",
      "i" = "Leave `frequency = NULL` to derive it from the cube."
    ))
  }
  t0_date <- as.Date(tdim$low)
  yr <- as.integer(format(t0_date, "%Y"))
  mo <- as.integer(format(t0_date, "%m"))
  period <- floor((mo - 1) / (12 / frequency)) + 1
  ts_start <- c(yr, period)

  # cache keyed by the full cube definition + reducer parameters
  cache_base <- dft_cache_path(cache_dir)
  cache_break_dir <- file.path(cache_base, "break")
  dir.create(cache_break_dir, recursive = TRUE, showWarnings = FALSE)
  key <- break_cache_key(cube, band, history, start, frequency, level, min_obs)
  cache_file <- file.path(cache_break_dir, paste0("break_", key, ".nc"))

  if (!force && file.exists(cache_file)) {
    message("  break: cached")
    return(terra::rast(cache_file))
  }

  fun <- build_break_reducer(band, ts_start, frequency, start, history, level,
                             min_obs)
  reduced <- gdalcubes::reduce_time(
    cube, names = c("break_date", "break_mag"),
    load_pkgs = "bfast", FUN = fun
  )
  gdalcubes::write_ncdf(reduced, cache_file, overwrite = TRUE)
  terra::rast(cache_file)
}


#' Per-pixel breakpoint reducer logic (internal, unit-testable)
#'
#' Canonical logic shared by the exported reducer. The degenerate branches
#' (all-`NA` or fewer than `min_obs` observations) return `c(NA, NA)` before any
#' `bfast` symbol is touched, so they are testable without bfast installed.
#' @noRd
.dft_break_pixel <- function(v, ts_start, frequency, start, history, level,
                             min_obs) {
  if (all(is.na(v)) || sum(!is.na(v)) < min_obs) return(c(NA_real_, NA_real_))
  ts_v <- stats::ts(v, start = ts_start, frequency = frequency)
  tryCatch({
    m <- bfast::bfastmonitor(ts_v, start = start, history = history,
                             level = level)
    c(m$breakpoint, m$magnitude)
  }, error = function(e) c(NA_real_, NA_real_))
}


#' Seasonal frequency implied by a gdalcubes ISO cadence (internal)
#'
#' `P1M` -> 12, `P3M` -> 4, `P1Y` -> 1. Returns `NA` for unsupported cadences.
#' @noRd
cadence_frequency <- function(dt_iso) {
  m <- regmatches(dt_iso, regexec("^P(\\d+)([MY])$", dt_iso))[[1]]
  if (length(m) != 3) return(NA_real_)
  n <- as.numeric(m[2])
  switch(m[3],
    "M" = 12 / n,
    "Y" = 1 / n,
    NA_real_
  )
}


#' Build a self-contained per-pixel reducer for reduce_time (internal)
#'
#' gdalcubes serializes the callback into worker processes and does not restore
#' the calling environment, so a closure over enclosing locals fails there. This
#' embeds [.dft_break_pixel()] as a literal function object (detached to
#' `baseenv()`) and inlines every parameter as a literal, yielding a callback
#' with no free variables that runs correctly under any `parallel` setting.
#' @noRd
build_break_reducer <- function(band, ts_start, frequency, start, history,
                                level, min_obs) {
  pixfun <- .dft_break_pixel
  environment(pixfun) <- baseenv()
  f <- function(x) NULL
  body(f) <- substitute(
    PIX(x[BAND, ], TS, FRQ, ST, HI, LV, MN),
    list(PIX = pixfun, BAND = band, TS = ts_start, FRQ = frequency,
         ST = start, HI = history, LV = level, MN = min_obs)
  )
  environment(f) <- baseenv()
  f
}


#' Cache key for one break reduction (internal)
#'
#' Hashes the full cube definition (`gdalcubes::as_json`, which captures the
#' source items, view, mask, and index) plus every reducer parameter.
#' @noRd
break_cache_key <- function(cube, band, history, start, frequency, level,
                            min_obs) {
  substr(
    rlang::hash(list(
      gdalcubes::as_json(cube), band, history, as.numeric(start),
      as.numeric(frequency), as.numeric(level), as.numeric(min_obs)
    )),
    1, 12
  )
}

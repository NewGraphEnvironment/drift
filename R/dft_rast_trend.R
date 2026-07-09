#' Per-pixel index trend over time
#'
#' Reduce an index stack (from [dft_stac_cube()]) to a per-pixel **trend** — the
#' rate at which the index rises or falls across the whole record. Where
#' [dft_rast_break()] finds an abrupt structural break, this measures the slow,
#' monotonic direction: gradual degradation (a declining stand) or recovery (a
#' restoration planting greening up) that annual categorical labels cannot show.
#'
#' The slope is a **Theil-Sen** estimate — the median of all pairwise slopes —
#' which is resistant to a single anomalous season (e.g. a smoke/drought year),
#' unlike an ordinary least-squares fit. Significance is the non-parametric
#' **Mann-Kendall** test for a monotonic trend.
#'
#' @param cube A monthly index `SpatRaster` (the return value of
#'   [dft_stac_cube()]): one layer per time step, with a time value per layer.
#' @param min_obs Integer. Minimum non-`NA` observations required; pixels with
#'   fewer return `NA` (default 6).
#' @param cores Integer or `NULL`. Forked workers for the per-pixel reduction.
#'   When `NULL`, uses one fewer than the detected cores.
#'
#' @return A two-band [terra::SpatRaster] with layers `trend` (index change per
#'   year — negative = declining greenness, positive = recovering) and `trend_p`
#'   (Mann-Kendall two-sided p-value; small = a significant monotonic trend).
#'
#' @seealso [dft_rast_break()] (abrupt breaks), [dft_stac_cube()].
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
#' cube <- dft_stac_cube(aoi, index = "kndvi", datetime = "2017-01-01/2023-12-31")
#' trend <- dft_rast_trend(cube)
#' terra::plot(trend[["trend"]])  # negative (red) = declining, positive = recovering
#' }
#'
#' @export
dft_rast_trend <- function(cube, min_obs = 6, cores = NULL) {
  if (!inherits(cube, "SpatRaster")) {
    cli::cli_abort("`cube` must be a SpatRaster time stack from {.fn dft_stac_cube}.")
  }
  if (terra::nlyr(cube) < 2) {
    cli::cli_abort("`cube` needs at least 2 time layers to estimate a trend.")
  }
  tm <- terra::time(cube)
  if (length(tm) != terra::nlyr(cube) || anyNA(tm)) {
    cli::cli_abort(c(
      "`cube` must carry a time value for every layer.",
      "i" = "Pass the stack returned by {.fn dft_stac_cube}."
    ))
  }
  min_obs <- max(2L, as.integer(min_obs))    # a slope needs at least two points
  t_yr <- as.numeric(as.Date(tm)) / 365.25   # decimal years -> slope is per year

  if (is.null(cores)) {
    dc <- parallel::detectCores()
    cores <- if (is.na(dc)) 2L else max(1L, dc - 1L)
  }

  vals <- terra::values(cube)
  usable <- which(rowSums(!is.na(vals)) >= min_obs)
  res <- matrix(NA_real_, nrow(vals), 2)
  if (length(usable)) {
    chunks <- split(usable, (seq_along(usable) - 1) %% cores)
    parts <- parallel::mclapply(chunks, function(ii) {
      t(vapply(ii, function(i) .dft_trend_pixel(vals[i, ], t_yr, min_obs),
               numeric(2)))
    }, mc.cores = cores)
    for (k in seq_along(chunks)) res[chunks[[k]], ] <- parts[[k]]
  }

  out <- cube[[1:2]]
  terra::values(out) <- res
  names(out) <- c("trend", "trend_p")
  out
}


#' Theil-Sen slope + Mann-Kendall p for one pixel time series (internal)
#'
#' Robust to a minority of anomalous points. Returns `c(NA, NA)` on fewer than
#' `min_obs` valid observations, before any statistics — testable without data.
#' @noRd
.dft_trend_pixel <- function(y, t, min_obs) {
  ok <- !is.na(y)
  if (sum(ok) < min_obs) return(c(NA_real_, NA_real_))
  y <- y[ok]
  t <- t[ok]
  n <- length(y)

  ij <- utils::combn(n, 2)
  i <- ij[1, ]
  j <- ij[2, ]
  # Theil-Sen: median pairwise slope
  slope <- stats::median((y[j] - y[i]) / (t[j] - t[i]))

  # Mann-Kendall S = sum of signs of pairwise differences (ordered by time)
  s <- sum(sign(y[j] - y[i]))
  var_s <- n * (n - 1) * (2 * n + 5) / 18
  z <- if (s > 0) (s - 1) / sqrt(var_s) else if (s < 0) (s + 1) / sqrt(var_s) else 0
  p <- 2 * stats::pnorm(-abs(z))

  c(slope, p)
}

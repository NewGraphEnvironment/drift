#' Pick, per feature, the capture nearest a date
#'
#' From the captures table of [dft_wayback_captures()], keeps for each feature
#' and each target `date` the one capture whose acquisition date is nearest to
#' it. The result names the release and zoom to pass to [dft_wayback_fetch()].
#'
#' Captures are ranked by, in order:
#' 1. days between `capture_date` and `date`, either side;
#' 2. finer `res_m`;
#' 3. the later `release_date`, then the larger `release_id` (compared as a
#'    number). The same capture is usually served by many releases, and any of
#'    them fetches it: a release that has not changed a tile redirects to the
#'    release that last did;
#' 4. the larger `cover`, then the earlier `capture_date`, then `source`, so
#'    the order is total even for a polygon that shows two captures equally
#'    near the date in one release.
#'
#' Cover enters only as a tiebreak. For polygons, filter on `cover` before the
#' pick when the capture must image most of each feature.
#'
#' A study design that bands by whole years (a capture in the endpoint year
#' before any capture a year off) expresses the band through the date: pass
#' mid-season, e.g. `as.Date("2017-07-01")`, and check `days_from_date` in the
#' result. The ranking itself does not band.
#'
#' @param captures A captures table from [dft_wayback_captures()]. Any table
#'   with `feature`, `capture_date` and `res_m` works; `release_date`,
#'   `release_id` and `cover` are used as tiebreaks when present.
#' @param date A `Date` vector (or character coercible by [as.Date()]) of
#'   target dates. Duplicates are dropped.
#'
#' @return A tibble with one row per feature and target date, for every feature
#'   that has a dated capture: `feature`, `date`, the chosen capture's other
#'   columns, and `days_from_date` (signed: negative is a capture before the
#'   date). A feature with no capture has no row; merge with your feature ids
#'   to list it. Sorted by feature, then date.
#'
#' @seealso [dft_wayback_captures()], [dft_wayback_fetch()].
#'
#' @examples
#' cap <- tibble::tibble(
#'   feature = c(1L, 1L, 1L, 2L),
#'   release_id = c("100", "200", "300", "300"),
#'   release_date = as.Date(c("2017-11-16", "2020-04-29", "2024-03-07", "2024-03-07")),
#'   capture_date = as.Date(c("2013-08-01", "2017-06-11", "2023-08-25", "2016-09-30")),
#'   res_m = c(0.5, 0.5, 0.3, 0.5),
#'   source = "Maxar WV02", zoom = 18L, cover = 1
#' )
#' # the capture nearest mid-season in each endpoint year
#' dft_wayback_pick(cap, as.Date(c("2017-07-01", "2023-07-01")))
#'
#' @export
dft_wayback_pick <- function(captures, date) {
  need <- c("feature", "capture_date", "res_m")
  if (!is.data.frame(captures) || !all(need %in% names(captures))) {
    cli::cli_abort(c(
      "{.arg captures} must be a table from {.fn dft_wayback_captures}.",
      "i" = "It needs columns {.val {need}}."
    ))
  }
  date <- wayback_date_check(date)
  cap <- tibble::as_tibble(captures)
  cap$capture_date <- as.Date(cap$capture_date)
  cap <- cap[!is.na(cap$capture_date), , drop = FALSE]

  out <- lapply(seq_along(date), function(i) {
    d <- date[i]
    days <- as.numeric(cap$capture_date - d)
    o <- order(cap$feature, abs(days), cap$res_m,
               -as.numeric(wayback_col(cap, "release_date", NA)),
               -suppressWarnings(as.numeric(wayback_col(cap, "release_id", NA))),
               wayback_col(cap, "release_id", NA),
               -as.numeric(wayback_col(cap, "cover", NA)),
               cap$capture_date, wayback_col(cap, "source", NA),
               method = "radix")
    o <- o[!duplicated(cap$feature[o])]
    best <- cap[o, , drop = FALSE]
    best <- tibble::add_column(best, date = rep(d, nrow(best)),
                               .after = "feature")
    best$days_from_date <- as.integer(days[o])
    best
  })
  out <- do.call(rbind, out)
  out[order(out$feature, out$date, method = "radix"), , drop = FALSE]
}


#' A column, or a constant when the table lacks it
#' @noRd
wayback_col <- function(x, name, default) {
  if (name %in% names(x)) x[[name]] else rep(default, nrow(x))
}


#' @noRd
wayback_date_check <- function(date) {
  d <- tryCatch(as.Date(date), error = function(e) NULL)
  if (is.null(d) || !length(d) || anyNA(d)) {
    cli::cli_abort("{.arg date} must be one or more dates, with no NA.")
  }
  sort(unique(d))
}

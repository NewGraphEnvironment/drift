#' How many observations a dated class switch held, either side
#'
#' The confidence attached to a clean switch found by [dft_rast_break_class()]:
#' `pmin(n_before, n_after)`, recovered from `break_year` alone. A switch is
#' only as sure as its shorter side, so a pixel whose last observation alone
#' differs scores 1 however long the run before it was.
#'
#' This is a **measurement**, not a judgement — its meaning is fixed and it is
#' never versioned. [dft_break_category()] thresholds it to produce a label,
#' which is versioned; a caller who wants a different threshold uses this
#' number directly rather than asking for another rule.
#'
#' @param break_year Integer vector of break years, as reported in the
#'   `break_year` layer of `$breaks` or the `break_year` column of `$summary`.
#'   `NA` (a stable or flicker pixel) returns `NA_integer_`.
#' @param years Integer vector of the observation years in the series, sorted
#'   and unique — `$years` from [dft_rast_break_class()], or the names of the
#'   list passed to it.
#'
#' @return An integer vector the length of `break_year`, `NA` where
#'   `break_year` is `NA`.
#'
#' @details
#' `break_year` is the first year of the new class, so a break at position
#' `idx` in the series has `n_before = idx` and `n_after = length(years) - idx`.
#' This inverts that: `idx = match(break_year, years) - 1`.
#'
#' **The unit is observations, not calendar years.** On a gapped series such as
#' `2017, 2020, 2023`, a break at 2020 scores 1 — the same as an endpoint year
#' — even though three calendar years flank it on each side. A strength of 2 on
#' that series means "held for two observations", which is six years.
#'
#' The maximum is `floor(length(years) / 2)`: 3 on the seven-year series drift
#' is usually run on, 1 on a four-year series, and 1 on the two- and three-year
#' series [dft_rast_break_class()] also accepts — so on a series shorter than
#' four observations no break can score 2, and [dft_break_category()]'s
#' `break_sustained` level is unreachable rather than merely empty.
#'
#' A `break_year` equal to `years[1]` is refused: the first year cannot be the
#' first year of a *new* class, so a value there means the years and the breaks
#' came from different series. So is any value absent from `years`, which
#' `match()` would otherwise pass through as a silent `NA`, and so is a
#' fractional or non-numeric year, which `as.integer()` would truncate or blank.
#'
#' **`years` must be the series the breaks were measured over, exactly.** A
#' membership check cannot catch a *superset*: on the true series `2017:2023` a
#' break at 2023 scores 1, and passing `2017:2030` instead scores it 6, turning
#' an endpoint-only switch into a sustained one with nothing to say so. Take
#' `years` from `dft_rast_break_class()`'s own `$years` wherever the result is
#' to hand; a summary read back from CSV does not carry the series, so the
#' caller states it and owns being right about it.
#'
#' @seealso [dft_rast_break_class()], which measures the switch;
#'   [dft_break_category()], which thresholds this into a label.
#'
#' @export
#' @examples
#' years <- 2017:2023
#'
#' # the second and last years score 1 -- one observation on the short side
#' dft_break_strength(c(2018, 2019, 2020, 2021, 2022, 2023), years)
#'
#' # NA in, NA out: a stable or flicker pixel has no break year
#' dft_break_strength(c(2020, NA), years)
#'
#' # a gapped series scores in observations, not calendar years
#' dft_break_strength(2020, c(2017, 2020, 2023))
dft_break_strength <- function(break_year, years) {
  years <- as.integer(years)
  if (length(years) < 2L) {
    stop("`years` must hold at least 2 observation years.", call. = FALSE)
  }
  if (anyNA(years)) {
    stop("`years` must not contain NA.", call. = FALSE)
  }
  if (anyDuplicated(years) > 0L) {
    stop("`years` must be unique.", call. = FALSE)
  }
  if (is.unsorted(years)) {
    stop("`years` must be sorted ascending; `dft_rast_break_class()$years` is.",
         call. = FALSE)
  }

  # as.integer() TRUNCATES rather than refusing, so 2020.7 would silently score
  # as 2020, and a non-numeric string becomes NA with only a warning -- on a
  # function whose every other malformed input is a named error.
  if (!is.numeric(break_year) && !all(is.na(break_year))) {
    stop("`break_year` must be numeric, not ", class(break_year)[1], ".",
         call. = FALSE)
  }
  frac <- !is.na(break_year) &
    (!is.finite(break_year) | break_year != trunc(break_year))
  if (any(frac)) {
    stop("`break_year` must be whole years; got ",
         paste(utils::head(sort(unique(break_year[frac])), 3), collapse = ", "),
         ".", call. = FALSE)
  }
  break_year <- as.integer(break_year)
  n <- length(years)
  # match() returns NA for a year absent from the series and 1 for years[1],
  # giving idx 0 -- a strength of 0 rather than a refusal. Both mean the breaks
  # and the years came from different series, so both are errors.
  idx <- match(break_year, years) - 1L
  bad <- !is.na(break_year) & (is.na(idx) | idx < 1L)
  if (any(bad)) {
    stop("`break_year` values are not in `years[-1]`: ",
         paste(sort(unique(break_year[bad])), collapse = ", "),
         ". A break year is the first year of the NEW class, so it cannot be ",
         "the first year of the series.", call. = FALSE)
  }
  pmin(idx, n - idx)
}

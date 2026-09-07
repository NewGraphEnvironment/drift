#' Temporal category of every row of a break-class summary
#'
#' Compose [dft_rast_break_class()]'s threshold-free measurements into the
#' labelled split the package and its consumers actually report: whether a
#' transition is a switch that held, a switch that turns on a single endpoint
#' observation, or a sequence that never settled — and, for the last of those,
#' whether the endpoints differ at all.
#'
#' `dft_rast_break_class()` deliberately applies no threshold. Composing the
#' label is a judgement, so it lives here, in one place, under a version — see
#' `rule`. The numbers it rests on stay where they were measured.
#'
#' @param x Either the list returned by [dft_rast_break_class()] (its
#'   `$summary` and `$years` are used) or a `$summary`-shaped data frame, in
#'   which case `years` is required. Columns `from_class`, `to_class`,
#'   `status` and `break_year` must be present.
#' @param years Integer vector of the observation years in the series. Ignored
#'   with a warning when `x` is a [dft_rast_break_class()] result, which
#'   carries its own.
#' @param rule Character. The labelling rule to apply. Only `"v1"` exists; it
#'   is recorded in the returned `rule` column so old output identifies the
#'   rule that produced it.
#'
#' @return `x`'s summary with three columns appended, its class and **row
#'   order** preserved (`$summary` arrives sorted by `n_cells` descending):
#'   - `category` — a factor with the five levels below, in that order
#'   - `strength` — [dft_break_strength()], `NA` off a clean switch
#'   - `rule` — the rule that produced `category`
#'
#' @section The `"v1"` rule:
#' \tabular{rll}{
#'   0 \tab `stable`         \tab `status == "stable"` \cr
#'   1 \tab `break_sustained`\tab a clean switch, `strength >= 2` \cr
#'   2 \tab `break_endpoint` \tab a clean switch, `strength == 1` \cr
#'   3 \tab `unsettled`      \tab never settles, and the endpoints differ \cr
#'   4 \tab `stable_flicker` \tab never settles, and the endpoints agree
#' }
#'
#' Levels 3 and 4 are the reason this function exists. A two-epoch comparison
#' reports level 3 as change and cannot see level 4 at all, so they are used
#' differently and must never be added together: on the Bulkley floodplain that
#' is 2,032.9 ha against 3,186.5 ha, and summing them gives 7,811.5 ha of
#' "changed" area where the published layer says 4,625.0 — a 69% overstatement.
#'
#' `strength` is thresholded at 2 and the threshold is **not** an argument: a
#' free threshold would mean `rule = "v1"` no longer identifies the labelling,
#' which is the composition problem this function exists to end. Use
#' [dft_break_strength()] directly for another cut.
#'
#' `n_flips` is not part of this function's surface. It stays on `$breaks`,
#' where it is measured.
#'
#' @details
#' `NA` propagates: a pixel with an `NA` in any interior year cannot be scanned,
#' arrives with `status` `NA`, and is labelled `NA` rather than refused — the
#' series in this package's own examples contains one.
#'
#' A `status` value outside `stable` / `break` / `flicker`, or a `break` row
#' carrying no `break_year`, is an error rather than an `NA`: both mean the
#' frame did not come from [dft_rast_break_class()].
#'
#' @seealso [dft_rast_break_category()] for the same rule at pixel grain;
#'   [dft_break_strength()] for the number it thresholds;
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
#' cat_tbl <- dft_break_category(res)
#' head(cat_tbl[c("from_class", "to_class", "category", "strength", "rule")])
#'
#' # the two populations a four-level vocabulary pools, kept apart
#' tapply(cat_tbl$area, cat_tbl$category, sum)
#'
#' # a summary read back from CSV needs the series stated
#' dft_break_category(as.data.frame(res$summary), years = years)$category[1:5]
dft_break_category <- function(x, years = NULL, rule = "v1") {
  break_rule_check(rule)

  if (is.data.frame(x)) {
    s <- x
    if (is.null(years)) {
      stop("`years` is required when `x` is a data frame: the endpoint ",
           "threshold cannot be recovered from `break_year` alone.",
           call. = FALSE)
    }
  } else if (is.list(x)) {
    if (!is.data.frame(x[["summary"]])) {
      stop("`x` must be a `dft_rast_break_class()` result or a summary data ",
           "frame; this list has no `summary`.", call. = FALSE)
    }
    if (is.null(x[["years"]])) {
      stop("`x` carries no `years`. Results saved by drift < 0.16.0 predate ",
           "that element -- pass `years` and the summary directly, e.g. ",
           "`dft_break_category(x$summary, years = <the series>)`.",
           call. = FALSE)
    }
    if (!is.null(years)) {
      warning("`years` ignored: `x` carries its own.", call. = FALSE)
    }
    s <- x[["summary"]]
    years <- x[["years"]]
  } else {
    stop("`x` must be a `dft_rast_break_class()` result or a summary data ",
         "frame, not ", class(x)[1], ".", call. = FALSE)
  }

  need <- c("from_class", "to_class", "status", "break_year")
  missing_cols <- setdiff(need, names(s))
  if (length(missing_cols)) {
    stop("`x` is missing the column", if (length(missing_cols) > 1) "s" else "",
         " ", paste(missing_cols, collapse = ", "),
         "; a `dft_rast_break_class()` summary carries all of ",
         paste(need, collapse = ", "), ".", call. = FALSE)
  }

  # status is the aggregate-grain spelling of n_flips: pmin(n_flips, 2).
  n_flips <- unname(c(stable = 0L, "break" = 1L, flicker = 2L)[as.character(s$status)])
  unknown <- !is.na(s$status) & is.na(n_flips)
  if (any(unknown)) {
    stop("unrecognised `status` value", if (sum(unknown) > 1) "s" else "", ": ",
         paste(sort(unique(as.character(s$status[unknown]))), collapse = ", "),
         ". Expected stable, break or flicker.", call. = FALSE)
  }

  strength <- dft_break_strength(s$break_year, years)
  no_year <- !is.na(n_flips) & n_flips == 1L & is.na(strength)
  if (any(no_year)) {
    stop(sum(no_year), " row", if (sum(no_year) > 1) "s" else "",
         " with status \"break\" carry no `break_year`, so the endpoint ",
         "threshold cannot be applied.", call. = FALSE)
  }
  # and the mirror, which is what makes "`strength` is NA off a clean switch" a
  # contract rather than a description of well-formed input: a stable or
  # flicker row cannot have a break year, so one there means the frame did not
  # come from dft_rast_break_class().
  stray <- !is.na(n_flips) & n_flips != 1L & !is.na(s$break_year)
  if (any(stray)) {
    stop(sum(stray), " row", if (sum(stray) > 1) "s" else "",
         " carry a `break_year` with status ",
         paste(sort(unique(as.character(s$status[stray]))), collapse = "/"),
         "; only a clean switch has one.", call. = FALSE)
  }

  code <- break_category_code(n_flips, strength, s$from_class != s$to_class)

  s$category <- factor(break_category_levels()[code + 1L],
                       levels = break_category_levels())
  s$strength <- strength
  s$rule <- rep(rule, nrow(s))
  s
}

#' The `"v1"` category levels, in id order
#'
#' Ids `0:4` are load-bearing beyond this package: `inst/cartography/drift_temporal.csv`
#' keys its colours on these strings and the temporal-composition article's
#' colour table keys on the integers, in this order.
#' @noRd
break_category_levels <- function() {
  c("stable", "break_sustained", "break_endpoint", "unsettled", "stable_flicker")
}

#' Reject an unsupported rule by name
#'
#' `match.arg()` on a one-element vector is a typo check dressed as an API, and
#' its message does not say what the supported set is.
#' @noRd
break_rule_check <- function(rule) {
  if (!identical(rule, "v1")) {
    stop("unsupported `rule`: ", paste(format(rule), collapse = ", "),
         ". Supported: \"v1\".", call. = FALSE)
  }
  invisible(rule)
}

#' The `"v1"` map, the single definition of the split
#'
#' Both [dft_break_category()] (aggregate rows, `n_flips` recovered from
#' `status`) and [dft_rast_break_category()] (pixels, `n_flips` measured) call
#' this. `NA` in any argument yields `NA`.
#'
#' `changed` is only consulted for `n_flips >= 2`: a pixel that never flipped
#' has equal endpoints by construction, and one that flipped exactly once has
#' different ones.
#' @noRd
break_category_code <- function(n_flips, strength, changed) {
  # R recycles a divisor-length argument silently: a length-2 `changed` against
  # four rows returns 3 4 3 4 with no warning, and a scalar `strength` labels
  # every row from one. Both are shapes a second caller would plausibly pass.
  if (length(strength) != length(n_flips) || length(changed) != length(n_flips)) {
    stop("break_category_code(): n_flips, strength and changed must be the same ",
         "length; got ", length(n_flips), ", ", length(strength), ", ",
         length(changed), ".", call. = FALSE)
  }
  out <- rep(NA_integer_, length(n_flips))
  ok <- !is.na(n_flips)
  out[ok & n_flips == 0L] <- 0L
  one <- ok & n_flips == 1L & !is.na(strength)
  out[one & strength >= 2L] <- 1L
  out[one & strength < 2L] <- 2L
  many <- ok & n_flips >= 2L & !is.na(changed)
  out[many & changed] <- 3L
  out[many & !changed] <- 4L
  out
}

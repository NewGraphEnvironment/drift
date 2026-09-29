#' Check a reference-label table against the accuracy-assessment contract
#'
#' drift does not store reference labels; the caller does, in whatever review
#' tool they use. This is the contract such a table must meet before
#' [dft_accuracy_estimate()] will read it, so a review tool can be checked
#' against it directly.
#'
#' @param labels A data frame with one row per labelled sample point.
#' @param strata Optional. The `$strata` table from [dft_accuracy_sample()], or
#'   any data frame with columns `stratum` and `n_cells`. When given, the
#'   labels are also checked for coverage of it.
#'
#' @return `labels`, invisibly. Every fault is an error that names it.
#'
#' @section Columns:
#' \tabular{lll}{
#'   `point_id`   \tab required \tab unique, non-missing sample point id \cr
#'   `stratum`    \tab required \tab the stratum the point was drawn from \cr
#'   `map_class`  \tab required \tab the map's class at the point \cr
#'   `ref_class`  \tab required \tab the reference class the reviewer assigned \cr
#'   `confidence` \tab optional \tab reviewer confidence, carried and not read \cr
#'   `reviewer`   \tab optional \tab who labelled it, carried and not read \cr
#'   `use`        \tab optional \tab `"accuracy"`, `"training"` or `NA`
#' }
#'
#' `stratum` and `map_class` come from the design, not from the reviewer:
#' [dft_accuracy_sample()] writes both (`map_class` through its `map`
#' argument). Only `ref_class`, and the optional columns, are the reviewer's.
#'
#' @section What is refused, and why:
#' - **A missing or blank `ref_class`** (`read.csv()` reads an empty cell as
#'   `""`, not `NA`; both are refused). A point the reviewer could not label (cloud, no
#'   imagery) is nonresponse, and dropping it changes the stratum's sample
#'   size. That is a design decision, so the caller makes it explicitly --
#'   remove the rows and say so -- rather than having it happen silently here.
#' - **A duplicated `point_id`**, which would count one point twice.
#' - **A stratum absent from `strata`**, a stratum with no cells that
#'   nevertheless has labels, or a stratum with cells but no labels: either
#'   way the labels do not cover the population the weights describe, and no
#'   estimator can repair that.
#' - **A `use` value other than `"accuracy"`, `"training"` or `NA`.**
#'
#' Filtering by `confidence` before estimating is possible and is also a
#' design change: the kept points are no longer a random sample of their
#' stratum when low confidence is not random (it rarely is -- edges, mixed
#' cells). Report it if you do it.
#'
#' @section Change maps:
#' For accuracy of a transition map, `map_class` is the transition id and
#' `ref_class` is composed from the reviewer's two endpoint labels with the
#' same scheme [dft_rast_transition()] uses: `ref_from * 1000 + ref_to`. The
#' contract needs no endpoint columns; carry them alongside if useful.
#'
#' @seealso [dft_accuracy_estimate()], which calls this;
#'   [dft_accuracy_sample()], which writes `point_id`, `stratum` and
#'   `map_class`.
#'
#' @export
#' @examples
#' labels <- data.frame(
#'   point_id  = c("1_00001", "1_00002", "2_00001", "2_00002"),
#'   stratum   = c(1, 1, 2, 2),
#'   map_class = c(1, 1, 2, 2),
#'   ref_class = c(1, 2, 2, 2)
#' )
#' dft_accuracy_labels(labels)
#'
#' # a point nobody could label is refused, not dropped
#' labels$ref_class[2] <- NA
#' try(dft_accuracy_labels(labels))
dft_accuracy_labels <- function(labels, strata = NULL) {
  if (!is.data.frame(labels)) {
    stop("`labels` must be a data frame, not ", class(labels)[1], ".",
         call. = FALSE)
  }
  cols_required <- c("point_id", "stratum", "map_class", "ref_class")
  missing_cols <- setdiff(cols_required, names(labels))
  if (length(missing_cols) > 0L) {
    stop("`labels` is missing required column(s): ",
         paste(missing_cols, collapse = ", "), ".", call. = FALSE)
  }
  if (nrow(labels) == 0L) {
    stop("`labels` has no rows.", call. = FALSE)
  }
  for (col in cols_required) {
    n_na <- sum(accuracy_is_missing(labels[[col]]))
    if (n_na > 0L) {
      hint <- if (col == "ref_class") {
        paste0(" A point that could not be labelled is nonresponse; remove ",
               "it deliberately (it changes the stratum's sample size) ",
               "rather than passing NA.")
      } else {
        ""
      }
      stop("`", col, "` has ", n_na, " missing or blank value(s).", hint,
           call. = FALSE)
    }
  }
  # ids are compared as given: numeric normalisation would make "01" and "1"
  # the same point
  ids <- if (is.factor(labels$point_id)) as.character(labels$point_id) else
    labels$point_id
  dup <- unique(ids[duplicated(ids)])
  if (length(dup) > 0L) {
    stop("`point_id` must be unique; duplicated: ",
         paste(utils::head(dup, 5), collapse = ", "),
         if (length(dup) > 5L) ", ..." else "", ".", call. = FALSE)
  }
  if ("use" %in% names(labels)) {
    # a blank cell (read.csv() reads one as "") counts as NA, as the
    # contract allows
    use <- as.character(labels$use)
    bad_use <- setdiff(unique(use[!accuracy_is_missing(use)]),
                       c("accuracy", "training"))
    if (length(bad_use) > 0L) {
      stop("`use` must be \"accuracy\", \"training\" or NA; got: ",
           paste(bad_use, collapse = ", "), ".", call. = FALSE)
    }
  }

  if (!is.null(strata)) {
    accuracy_check_strata(strata)
    lab_strata <- unique(accuracy_key(labels$stratum))
    known <- accuracy_key(strata$stratum)
    unknown <- setdiff(lab_strata, known)
    if (length(unknown) > 0L) {
      stop("`labels` has stratum value(s) absent from `strata`: ",
           paste(unknown, collapse = ", "), ".", call. = FALSE)
    }
    empty <- intersect(lab_strata, known[strata$n_cells == 0])
    if (length(empty) > 0L) {
      stop("`labels` has points in stratum/strata with no cells in ",
           "`strata`: ", paste(empty, collapse = ", "), ". The labels and ",
           "the strata table come from different draws.", call. = FALSE)
    }
    uncovered <- setdiff(known[strata$n_cells > 0], lab_strata)
    if (length(uncovered) > 0L) {
      stop("Stratum/strata with cells but no labels: ",
           paste(uncovered, collapse = ", "), ". The labels do not cover ",
           "the population the weights describe.", call. = FALSE)
    }
  }
  invisible(labels)
}

# Shared by dft_accuracy_labels() and dft_accuracy_estimate()
accuracy_check_strata <- function(strata) {
  if (!is.data.frame(strata)) {
    stop("`strata` must be a data frame, such as `$strata` from ",
         "dft_accuracy_sample().", call. = FALSE)
  }
  missing_cols <- setdiff(c("stratum", "n_cells"), names(strata))
  if (length(missing_cols) > 0L) {
    stop("`strata` is missing required column(s): ",
         paste(missing_cols, collapse = ", "), ".", call. = FALSE)
  }
  if (any(accuracy_is_missing(strata$stratum)) ||
        anyDuplicated(accuracy_key(strata$stratum))) {
    stop("`strata$stratum` must be unique and non-missing.", call. = FALSE)
  }
  n_ok <- is.numeric(strata$n_cells) && !anyNA(strata$n_cells) &&
    all(strata$n_cells >= 0)
  if (!n_ok) {
    stop("`strata$n_cells` must be non-negative numbers.", call. = FALSE)
  }
  invisible(strata)
}

# The one string form of a class or stratum value, used for every
# comparison. as.character() writes the double 100000 as "1e+05" and the
# integer as "100000", so a double column and an integer column holding the
# same code would not match; whole numbers are written out in full instead.
accuracy_key <- function(x) {
  out <- as.character(x)
  # a factor or character value can carry R's own rendering of a number:
  # levels(factor(100000)) is "1e+05". Read such strings back as numbers so
  # they meet the numeric column holding the same code.
  num <- if (is.numeric(x)) as.numeric(x) else suppressWarnings(as.numeric(out))
  whole <- !is.na(num) & is.finite(num) & num == round(num) & abs(num) < 2^53
  out[whole] <- sprintf("%.0f", num[whole])
  out
}

# NA, or a blank string (a CSV reader's empty cell)
accuracy_is_missing <- function(x) {
  miss <- is.na(x)
  if (is.character(x) || is.factor(x)) {
    miss <- miss | !nzchar(trimws(as.character(x)))
  }
  miss
}

#' Accuracy and error-adjusted area from a stratified reference sample
#'
#' Turn reference labels at stratified random sample points into the numbers
#' a change map should be reported with: an error matrix in estimated
#' proportions of area, overall / user's / producer's accuracy, and
#' **error-adjusted area per class with a confidence interval** -- following
#' Olofsson et al. (2014) and Stehman (2014).
#'
#' Mapped area is a biased estimator whenever the map has errors, and for a
#' change map the bias is usually large: a single wrong label on either date
#' manufactures a transition. The error-adjusted area is the area the
#' *reference* labels imply, weighted back to the population by each
#' stratum's size.
#'
#' @param labels A data frame meeting the [dft_accuracy_labels()] contract:
#'   `point_id`, `stratum`, `map_class`, `ref_class`.
#' @param strata The `$strata` table from [dft_accuracy_sample()], or any data
#'   frame with `stratum`, `n_cells` (the stratum's size in cells, `n_cells_h`) and
#'   `area` (its mapped area in hectares).
#' @param level Confidence level for the intervals. Default `0.95`.
#'
#' @return A list:
#' - `matrix` -- tibble, long: `map_class`, `ref_class`, `proportion` (the
#'   estimated share of total area), one row per pair of classes, zeros
#'   included.
#' - `accuracy` -- tibble: `measure` (`"overall"`, `"user"`, `"producer"`),
#'   `class` (`NA` for overall), `estimate`, `se`, `lower`, `upper`.
#' - `area` -- tibble, one row per class: `proportion`, `proportion_se`,
#'   `area`, `area_se`, `lower`, `upper` (hectares).
#' - `stratum` -- tibble, long, per stratum and `target`: `n`, `n_cells`,
#'   `weight`, `mean` and `sd` of an indicator within the stratum. `target` is
#'   `"agreement"` (map equals reference) or a reference class, written in
#'   full as a string (`"100000"`, never `"1e+05"`). `sd` is what
#'   [dft_accuracy_size()] takes to size a full sample from a pilot.
#' - `level`, `area_total` (ha).
#'
#' @section Estimators:
#' The estimates come from [mapaccuracy::stehman2014()], which implements
#' Stehman (2014)'s estimators for stratified random sampling. Those hold
#' **whether or not the strata are the map classes** -- strata such as "change
#' attributed to fire", "change unattributed" and "stable" are fine. When the
#' strata are the map classes they give Olofsson et al. (2014)'s estimates,
#' and the package test suite reproduces that paper's worked example.
#'
#' - The **finite population correction** `(1 - n_h / n_cells_h)` is always
#'   applied, so a stratum sampled in full (a census) contributes no variance.
#'   Olofsson et al. omit it; at pixel-scale `n_cells_h` the difference is below
#'   anything reported.
#' - Intervals are Wald intervals, `estimate +/- z * se` with
#'   `z = qnorm(1 - (1 - level) / 2)`, and are **not** truncated at 0 or 1: a
#'   lower bound below 0 says the class is too rare for the sample to bound
#'   away from zero, and truncating it would hide that.
#' - **A rare class hiding in a large stratum makes the interval too narrow
#'   at small samples.** If 1\% of a big stratum is really class *j* and
#'   the stratum gets 25 points, most samples see none of it, estimate that
#'   stratum's variance for *j* as 0, and report an interval that misses. On
#'   the bundled tiles (98 of 7,127 "Trees" cells reference Water) Water's
#'   95\% interval covered 61\% of the time at 25 points per stratum, 83\%
#'   at 75 and 89\% at 150; the estimate itself stayed unbiased. Omission
#'   hides in the large stable strata, so do not starve them.
#' - When the strata are not the map classes, the error matrix's row totals
#'   (the map-class shares) are **estimated** from the sample, not the known
#'   stratum weights. That surprises readers used to Olofsson's tables.
#' - Producer's accuracy is `NA` for a class no reference label falls in.
#' - Run time grows with roughly the 2.5th power of the number of classes:
#'   about 13 s for 1,000 points over 80 transition classes. Collapse classes
#'   you will not report before estimating.
#'
#' @section Targets that are unions of classes:
#' "Tree loss" is every Trees -> non-Trees transition; an "unattributed
#' residual" is loss outside any fire or harvest. Recode `map_class` and
#' `ref_class` to the target (say `"loss"` / `"other"`) and estimate again. The
#' standard error of a union is **not** the sum of its members' standard
#' errors, because the members' estimates are correlated.
#'
#' @section Training points:
#' A row with `use == "training"` is refused. Points that trained a
#' classifier cannot also measure it -- the estimate would be optimistic by
#' construction. Keep the accuracy sample separate from the start; a subset of
#' accuracy points chosen for training by judgement also stops being a random
#' sample of its stratum.
#'
#' @references
#' Olofsson, P., Foody, G.M., Herold, M., Stehman, S.V., Woodcock, C.E. and
#' Wulder, M.A. (2014). Good practices for estimating area and assessing
#' accuracy of land change. *Remote Sensing of Environment* 148, 42-57.
#' \doi{10.1016/j.rse.2014.02.015}
#'
#' Stehman, S.V. (2014). Estimating area and map accuracy for stratified
#' random sampling when the strata are different from the map classes.
#' *International Journal of Remote Sensing* 35(13), 4923-4939.
#' \doi{10.1080/01431161.2014.930207}
#'
#' @seealso [dft_accuracy_sample()] to draw the points,
#'   [dft_accuracy_labels()] for the label contract,
#'   [dft_accuracy_size()] to size a sample from a pilot.
#'
#' @export
#' @examples
#' # Olofsson et al. (2014), Table 8: 640 labelled points in four strata that
#' # are the map classes, over 10 million 30 m pixels
#' cls <- c("deforestation", "forest_gain", "stable_forest", "stable_nonforest")
#' counts <- matrix(c(66, 0, 5, 4,  0, 55, 8, 12,  1, 0, 153, 11,  2, 1, 9, 313),
#'                  nrow = 4, byrow = TRUE)
#' idx <- which(counts > 0, arr.ind = TRUE)
#' map <- rep(cls[idx[, 1]], counts[idx])
#' ref <- rep(cls[idx[, 2]], counts[idx])
#' labels <- data.frame(point_id = seq_along(map), stratum = map,
#'                      map_class = map, ref_class = ref)
#' pixels <- c(200000, 150000, 3200000, 6450000)
#' strata <- data.frame(stratum = cls, n_cells = pixels, area = pixels * 0.09)
#'
#' res <- dft_accuracy_estimate(labels, strata)
#' res$area       # deforestation: 21,158 ha +/- 6,157 -- mapped was 18,000
#' res$accuracy
dft_accuracy_estimate <- function(labels, strata, level = 0.95) {
  dft_accuracy_labels(labels, strata)
  if (!"area" %in% names(strata)) {
    stop("`strata` needs an `area` column (hectares) for error-adjusted area.",
         call. = FALSE)
  }
  level_ok <- is.numeric(level) && length(level) == 1L && !is.na(level) &&
    level > 0 && level < 1
  if (!level_ok) {
    stop("`level` must be a single number between 0 and 1.", call. = FALSE)
  }
  if ("use" %in% names(labels)) {
    n_train <- sum(as.character(labels$use) %in% "training")
    if (n_train > 0L) {
      stop(n_train, " row(s) have `use == \"training\"`. Points that trained ",
           "a classifier cannot measure its accuracy; estimate from the ",
           "held-out accuracy sample only.", call. = FALSE)
    }
  }

  strata <- strata[strata$n_cells > 0, , drop = FALSE]
  cell_area <- strata$area / strata$n_cells
  grid_ok <- all(is.finite(cell_area)) &&
    max(abs(cell_area / cell_area[1] - 1)) <= 1e-6
  if (!grid_ok) {
    stop("`strata$area` / `strata$n_cells` differs between strata: the ",
         "weights (cells) and the areas describe different grids.",
         call. = FALSE)
  }
  area_total <- sum(strata$area)

  key <- accuracy_key(strata$stratum)
  lab_key <- accuracy_key(labels$stratum)
  n_h <- as.vector(table(factor(lab_key, levels = key)))
  n_cells_h <- strata$n_cells
  if (any(n_h > n_cells_h)) {
    bad <- key[n_h > n_cells_h]
    stop("More labels than cells in stratum/strata: ",
         paste(bad, collapse = ", "), ".", call. = FALSE)
  }
  census <- n_h == n_cells_h
  thin <- n_h < 2L & !census
  if (any(thin)) {
    stop("Stratum/strata with a single labelled point: ",
         paste(key[thin], collapse = ", "), ". Its variance is undefined; ",
         "label at least two points (or all of a stratum's cells).",
         call. = FALSE)
  }

  # one normalisation, accuracy_key(), for the class set, the labels and every
  # comparison: c() on a factor and a non-factor falls back to the factor's
  # integer codes, and as.character() writes 100000 as "1e+05" for a double
  # but not an integer -- either would split one class in two
  map_chr <- accuracy_key(labels$map_class)
  ref_chr <- accuracy_key(labels$ref_class)
  classes <- accuracy_class_order(c(map_chr, ref_chr))
  classes_numeric <- is.numeric(labels$map_class) &&
    is.numeric(labels$ref_class)

  # stehman2014() matches stratum names by regex, so pass ids that cannot
  # carry a metacharacter; its default class order sorts "10" before "2", so
  # pass the order too
  sid <- paste0("s", seq_along(key))
  nh_strata <- stats::setNames(n_cells_h, sid)
  s_lab <- sid[match(lab_key, key)]
  est <- withCallingHandlers(
    mapaccuracy::stehman2014(s = s_lab, r = ref_chr, m = map_chr,
                             Nh_strata = nh_strata, margins = FALSE,
                             order = classes),
    # a single-point stratum is refused above unless it is a census, where
    # the finite population correction makes its variance exactly 0
    warning = function(w) {
      if (grepl("include only one observation", conditionMessage(w))) {
        invokeRestart("muffleWarning")
      }
    }
  )

  z <- stats::qnorm(1 - (1 - level) / 2)
  cls_out <- if (classes_numeric) as.numeric(classes) else classes

  m <- est$matrix
  m[is.na(m)] <- 0
  matrix_long <- tibble::tibble(
    map_class  = rep(cls_out, times = length(classes)),
    ref_class  = rep(cls_out, each = length(classes)),
    proportion = as.vector(m)
  )

  acc_row <- function(measure, class, e, se) {
    tibble::tibble(measure = measure, class = class, estimate = unname(e),
                   se = unname(se), lower = unname(e - z * se),
                   upper = unname(e + z * se))
  }
  accuracy <- rbind(
    acc_row("overall", cls_out[NA_integer_], est$OA, est$SEoa),
    acc_row("user", cls_out, est$UA[classes], est$SEua[classes]),
    acc_row("producer", cls_out, est$PA[classes], est$SEpa[classes])
  )

  area <- tibble::tibble(
    class         = cls_out,
    proportion    = unname(est$area[classes]),
    proportion_se = unname(est$SEa[classes]),
    area          = unname(est$area[classes]) * area_total,
    area_se       = unname(est$SEa[classes]) * area_total
  )
  area$lower <- area$area - z * area$area_se
  area$upper <- area$area + z * area$area_se

  list(
    matrix     = matrix_long,
    accuracy   = accuracy,
    area       = area,
    stratum    = accuracy_stratum_table(labels, strata, classes),
    level      = level,
    area_total = area_total
  )
}

# Keys (from accuracy_key()) in a stable, locale-free order: numeric order when
# every class reads as a number (transition ids 1001 < 11011), radix (C-locale)
# order otherwise
accuracy_class_order <- function(x) {
  u <- unique(x)
  num <- suppressWarnings(as.numeric(u))
  if (!anyNA(num)) u[order(num)] else sort(u, method = "radix")
}

accuracy_sd <- function(v) {
  if (length(v) > 1L) stats::sd(v) else NA_real_
}

# Per-stratum mean and SD of the agreement indicator and of each reference
# class indicator -- the S_h a pilot hands to dft_accuracy_size()
accuracy_stratum_table <- function(labels, strata, classes) {
  key <- accuracy_key(strata$stratum)
  lab_key <- accuracy_key(labels$stratum)
  ref_chr <- accuracy_key(labels$ref_class)
  agree <- accuracy_key(labels$map_class) == ref_chr
  weight <- strata$n_cells / sum(strata$n_cells)
  targets <- c("agreement", classes)
  rows <- lapply(seq_along(key), function(h) {
    in_h <- lab_key == key[h]
    ind <- c(list(agree[in_h]),
             lapply(classes, function(cl) ref_chr[in_h] == cl))
    tibble::tibble(
      stratum = strata$stratum[h],
      n       = sum(in_h),
      n_cells = strata$n_cells[h],
      weight  = weight[h],
      target  = targets,
      mean    = vapply(ind, mean, numeric(1)),
      # a census stratum has no sampling variance, whatever its sd -- and a
      # one-cell census has no sd at all, which the sizer would refuse
      sd      = if (sum(in_h) == strata$n_cells[h]) 0 else
        vapply(ind, accuracy_sd, numeric(1))
    )
  })
  do.call(rbind, rows)
}

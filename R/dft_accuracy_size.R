#' Size and allocate a stratified accuracy sample
#'
#' How many reference points a stratified sample needs to hit a target
#' standard error, and how to split them across strata -- Olofsson et al.
#' (2014), Eq. 13 and section 5.1.
#'
#' @param weights Numeric stratum weights (`N_h / N`), summing to 1, named by
#'   stratum -- `$strata$weight` from [dft_accuracy_sample()], or from
#'   [dft_accuracy_estimate()]'s `$stratum` table.
#' @param se_target The standard error to achieve for the estimate being
#'   planned for, as a proportion (0.01 is one percentage point). For an
#'   area, that is the class's share of total area.
#' @param s_h Per-stratum standard deviation of the indicator behind that
#'   estimate, in the order of `weights` (or matched by name when both are
#'   named). From a pilot, take `sd` from
#'   [dft_accuracy_estimate()]`$stratum` for the target: `"agreement"` to plan
#'   for overall accuracy, or a reference class to plan for its area.
#' @param ua Alternatively, anticipated user's accuracy per stratum. Valid
#'   only when **the strata are the map classes**, where the SD of the
#'   agreement indicator in stratum `i` is `sqrt(ua_i * (1 - ua_i))`
#'   (Olofsson Eq. 13). Give `s_h` or `ua`, not both.
#' @param allocation How to split `n` across strata:
#'   - `"equal"` -- `n / H` each;
#'   - `"proportional"` -- `n * weight`;
#'   - `"proportional_min"` (default) -- at least `n_min` in every stratum,
#'     the remainder proportional to weight among the others. This is
#'     Olofsson's recommendation for change maps, where the change strata are
#'     rare and proportional allocation would give them a handful of points.
#' @param n_min Minimum points per stratum for `"proportional_min"`. Olofsson
#'   suggests 50-100 per change stratum. Default 50.
#'
#' @return A list: `n`, the total from Eq. 13 (rounded up); `allocation`, the
#'   per-stratum sizes named by stratum, ready for [dft_accuracy_sample()]'s
#'   `n`; and the `s_h` used. Allocations are rounded, so they can sum to a
#'   point or two either side of `n`.
#'
#' @details
#' Eq. 13 is `n = (sum(W_h * S_h) / SE)^2`. Its finite-population term is
#' dropped, which is safe when strata hold millions of cells and conservative
#' otherwise.
#'
#' The allocation changes which estimates are precise, not whether they are
#' unbiased: any allocation with at least two points per stratum gives
#' unbiased estimates through [dft_accuracy_estimate()]. Check the
#' anticipated standard errors of the estimates that matter -- the rare change
#' classes' areas, typically -- rather than overall accuracy alone.
#'
#' `s_h` of 0 (a pilot stratum where every point agreed) is legitimate and
#' makes that stratum contribute nothing to `n`; the minimum allocation still
#' samples it. A pilot that small understates the stratum's variance, so
#' treat a zero with suspicion.
#'
#' @references
#' Olofsson, P., Foody, G.M., Herold, M., Stehman, S.V., Woodcock, C.E. and
#' Wulder, M.A. (2014). Good practices for estimating area and assessing
#' accuracy of land change. *Remote Sensing of Environment* 148, 42-57.
#' \doi{10.1016/j.rse.2014.02.015}
#'
#' @seealso [dft_accuracy_sample()], [dft_accuracy_estimate()].
#'
#' @export
#' @examples
#' # Olofsson et al. (2014) section 5.1.1: four strata that are the map
#' # classes, anticipated user's accuracies, and a target SE of 0.01 for
#' # overall accuracy -> n = 641
#' w <- c(deforestation = 0.020, forest_gain = 0.015,
#'        stable_forest = 0.320, stable_nonforest = 0.645)
#' dft_accuracy_size(w, se_target = 0.01, ua = c(0.70, 0.60, 0.90, 0.95),
#'                   allocation = "proportional")
#'
#' # From a pilot: size a full sample for the area of one class
#' map <- terra::rast(system.file("extdata", "example_2017.tif",
#'                                package = "drift"))
#' ref <- terra::rast(system.file("extdata", "example_2023.tif",
#'                                package = "drift"))
#' pilot <- dft_accuracy_sample(map, n = 20, seed = 1, map = map)
#' pts <- sf::st_drop_geometry(pilot$points)
#' pts$ref_class <- terra::values(ref)[pts$cell, 1]   # stand-in reference
#' est <- dft_accuracy_estimate(pts, pilot$strata)
#' trees <- est$stratum[est$stratum$target == "2", ]  # IO LULC 2 = Trees
#' plan <- dft_accuracy_size(stats::setNames(trees$weight, trees$stratum),
#'                           se_target = 0.02, s_h = trees$sd, n_min = 20)
#' plan$allocation
dft_accuracy_size <- function(weights, se_target, s_h = NULL, ua = NULL,
                              allocation = c("proportional_min", "equal",
                                             "proportional"),
                              n_min = 50) {
  allocation <- match.arg(allocation)
  if (!is.numeric(weights) || length(weights) == 0L || anyNA(weights)) {
    stop("`weights` must be a non-empty numeric vector without NA.",
         call. = FALSE)
  }
  if (any(weights <= 0)) {
    stop("Every weight must be positive; a stratum with no cells has ",
         "nothing to sample. Drop it.", call. = FALSE)
  }
  if (abs(sum(weights) - 1) > 1e-6) {
    stop("`weights` must sum to 1; they sum to ", signif(sum(weights), 6),
         ".", call. = FALSE)
  }
  if (!is.numeric(se_target) || length(se_target) != 1L ||
        is.na(se_target) || se_target <= 0) {
    stop("`se_target` must be a single positive number.", call. = FALSE)
  }
  if (is.null(s_h) == is.null(ua)) {
    stop("Give exactly one of `s_h` or `ua`.", call. = FALSE)
  }
  if (!is.null(ua)) {
    if (!is.numeric(ua) || anyNA(ua) || any(ua < 0 | ua > 1)) {
      stop("`ua` must be proportions between 0 and 1.", call. = FALSE)
    }
    s_h <- sqrt(ua * (1 - ua))
    what <- "ua"
  } else {
    if (!is.numeric(s_h) || anyNA(s_h) || any(s_h < 0)) {
      stop("`s_h` must be non-negative numbers without NA. A stratum with ",
           "one pilot point has no SD; label another.", call. = FALSE)
    }
    what <- "s_h"
  }
  if (length(s_h) != length(weights)) {
    stop("`", what, "` must have one value per stratum (", length(weights),
         "); it has ", length(s_h), ".", call. = FALSE)
  }
  # match by name when both are named, so a differently ordered vector is not
  # paired with the wrong weights
  vals <- if (what == "ua") ua else s_h
  if (!is.null(names(vals)) && !is.null(names(weights))) {
    nv <- accuracy_key(names(vals))
    nw <- accuracy_key(names(weights))
    if (!setequal(nv, nw) || anyDuplicated(nv)) {
      stop("`", what, "` and `weights` are both named but name different ",
           "strata.", call. = FALSE)
    }
    s_h <- s_h[match(nw, nv)]
  }
  ws <- sum(weights * s_h)
  if (ws == 0) {
    stop("Every stratum has an SD of 0, so Eq. 13 asks for no sample at all. ",
         "A pilot that agreed everywhere is too small to plan from.",
         call. = FALSE)
  }
  n <- ceiling((ws / se_target)^2)

  nm <- names(weights)
  alloc <- switch(
    allocation,
    equal        = rep(round(n / length(weights)), length(weights)),
    proportional = round(n * weights),
    proportional_min = accuracy_alloc_min(n, weights, n_min)
  )
  names(alloc) <- nm
  names(s_h) <- nm
  list(n = n, allocation = alloc, s_h = s_h)
}

# At least n_min per stratum, the rest proportional among the others. Strata
# pushed below n_min by the reallocation join the minimum group in turn.
accuracy_alloc_min <- function(n, weights, n_min) {
  if (!is.numeric(n_min) || length(n_min) != 1L || is.na(n_min) ||
        n_min < 2 || n_min != trunc(n_min)) {
    stop("`n_min` must be a single whole number of at least 2.",
         call. = FALSE)
  }
  h <- length(weights)
  if (n_min * h > n) {
    return(rep(n_min, h))
  }
  small <- rep(FALSE, h)
  repeat {
    rest <- n - n_min * sum(small)
    share <- rest * weights / sum(weights[!small])
    grow <- !small & share < n_min
    if (!any(grow)) break
    small <- small | grow
  }
  out <- ifelse(small, n_min, round(share))
  unname(out)
}

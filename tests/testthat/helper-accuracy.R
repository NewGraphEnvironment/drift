# Published reference values for the accuracy-assessment tests (#81).
#
# Olofsson, P., Foody, G.M., Herold, M., Stehman, S.V., Woodcock, C.E.,
# Wulder, M.A. (2014). Good practices for estimating area and assessing
# accuracy of land change. Remote Sensing of Environment 148: 42-57.
# doi:10.1016/j.rse.2014.02.015. Zotero: olofsson_etal2014Goodpractices.
#
# Every value below is transcribed from the PDF, with its page and table. Where
# the printed value contradicts the paper's own equation, the equation value is
# kept and the printed one is recorded beside it -- see olofsson_printed_typos.

olofsson_classes <- c("deforestation", "forest_gain", "stable_forest",
                      "stable_nonforest")

# Table 8 (p. 55): sample counts n_ij, rows = map (= stratum), cols = reference
olofsson_counts <- matrix(
  c(66,  0,   5,   4,
     0, 55,   8,  12,
     1,  0, 153,  11,
     2,  1,   9, 313),
  nrow = 4, byrow = TRUE, dimnames = list(olofsson_classes, olofsson_classes)
)

# Table 8 (p. 55): mapped area in 30 m pixels. 1 pixel = 0.09 ha.
olofsson_pixels <- c(200000, 150000, 3200000, 6450000)
names(olofsson_pixels) <- olofsson_classes

# Table 9 (p. 55): estimated area proportions p_ij, to 4 dp
olofsson_p <- matrix(
  c(0.0176, 0,      0.0013, 0.0011,
    0,      0.0110, 0.0016, 0.0024,
    0.0019, 0,      0.2967, 0.0213,
    0.0040, 0.0020, 0.0179, 0.6212),
  nrow = 4, byrow = TRUE, dimnames = list(olofsson_classes, olofsson_classes)
)

# Section 5.2.1 (p. 54): estimate +/- 95% half-width, to 2 dp
olofsson_user     <- c(0.88, 0.73, 0.93, 0.96)
olofsson_user_hw  <- c(0.07, 0.10, 0.04, 0.02)
olofsson_prod     <- c(0.75, 0.85, 0.93, 0.96)
# Printed as 0.21, 0.23, 0.03, 0.01. Eq. (7) gives 0.254 for forest gain and
# 0.018 for stable non-forest (recomputed independently of any package, and
# matching mapac and mapaccuracy), so those two are kept at the equation value.
olofsson_prod_hw  <- c(0.21, 0.25, 0.03, 0.02)
olofsson_overall    <- 0.95
olofsson_overall_hw <- 0.02

# Section 5.2.2 (p. 54): error-adjusted area and 95% half-width, ha
olofsson_area    <- c(21158, 11686, 285770, 581386)
olofsson_area_hw <- c(6158, 3756, 15510, 16282)

# Printed values that disagree with the paper's own arithmetic, kept for the
# record and asserted nowhere
olofsson_printed_typos <- list(
  producer_hw_forest_gain      = c(printed = 0.23, eq7 = 0.254),
  producer_hw_stable_nonforest = c(printed = 0.01, eq7 = 0.018),
  # "S(A_1) = 0.0035 x 10,000,000 = 34,097 pixels" -- 1.96 x 34,097 is 66,830,
  # not the 68,418 printed next; 68,418 / 1.96 = 34,907
  se_area_deforestation_px     = c(printed = 34097, implied = 34907)
)

# Section 5.1.1 and Table 5 (p. 53): sample size planning
olofsson_plan_weights <- c(0.020, 0.015, 0.320, 0.645)
olofsson_plan_ua      <- c(0.70, 0.60, 0.90, 0.95)
olofsson_plan_n       <- 641
olofsson_plan_equal   <- c(160, 160, 160, 160)
olofsson_plan_prop    <- c(13, 10, 205, 413)
# Table 5's Alloc1-3 columns (e.g. 100/100/149/292) are not reproducible from
# the rule the paper states ("allocate the remainder proportionally to the
# stable classes" gives 146/295), so they are not asserted.

# One row per sample point, expanded from Table 8, in the label contract shape
olofsson_labels <- function() {
  idx <- which(olofsson_counts > 0, arr.ind = TRUE)
  map <- rep(olofsson_classes[idx[, "row"]], olofsson_counts[idx])
  ref <- rep(olofsson_classes[idx[, "col"]], olofsson_counts[idx])
  data.frame(
    point_id  = sprintf("p%04d", seq_along(map)),
    stratum   = map,
    map_class = map,
    ref_class = ref,
    stringsAsFactors = FALSE
  )
}

# The strata table as dft_accuracy_sample() emits it
olofsson_strata <- function(n_cells = olofsson_pixels) {
  tibble::tibble(
    stratum = olofsson_classes,
    n_cells = unname(n_cells),
    area    = unname(n_cells) * 0.09,
    weight  = unname(n_cells) / sum(n_cells)
  )
}

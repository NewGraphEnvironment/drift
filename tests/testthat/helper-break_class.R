# Synthetic annual class-series fixtures for dft_rast_break_class() tests.
#
# A cells x years integer matrix of class codes becomes a named list of
# classified SpatRasters (one per year) on a 10 m projected grid (EPSG:32609),
# using the synthetic 4-class table from helper-artifact.R — so the tests prove
# "any classified series", not IO LULC.
#
# codes: 1 = Water, 2 = Trees, 3 = Rangeland, 4 = Bare

# One row per pixel, one column per year. Pixels are laid out in a single
# raster row (1 x n_pixels) so that cell i == matrix row i.
break_series_list <- function(m, years = 2017:2023, res = 10) {
  stopifnot(ncol(m) == length(years))
  x <- lapply(seq_along(years), function(j) {
    r <- artifact_class_rast(matrix(m[, j], nrow = 1), res)
    dft_rast_classify(r, class_table = artifact_class_table())
  })
  names(x) <- years
  x
}

# The acceptance cases from drift#9, one pixel each. Names document the case;
# expected values are asserted in test-dft_rast_break_class.R.
break_series_cases <- function() {
  s <- function(...) c(...)
  rbind(
    stable          = s(2, 2, 2, 2, 2, 2, 2),
    switch_2018     = s(2, 3, 3, 3, 3, 3, 3),   # first year alone differs (n_before 1)
    switch_2019     = s(2, 2, 3, 3, 3, 3, 3),
    switch_2020     = s(2, 2, 2, 3, 3, 3, 3),
    switch_2021     = s(2, 2, 2, 2, 3, 3, 3),
    switch_2022     = s(2, 2, 2, 2, 2, 3, 3),
    switch_2023     = s(2, 2, 2, 2, 2, 2, 3),   # last year alone differs (n_after 1)
    flicker         = s(2, 3, 2, 3, 2, 3, 2),   # 6 flips, endpoints equal
    flicker_diff    = s(2, 3, 2, 3, 2, 3, 3),   # 5 flips, endpoints differ
    settling        = s(2, 2, 3, 2, 3, 3, 3),   # 3 flips, no clean break
    na_year         = s(2, 2, 2, NA, 3, 3, 3),  # one NA -> NA everywhere
    all_na          = s(NA, NA, NA, NA, NA, NA, NA)
  )
}

years <- 2017:2023
cases <- break_series_cases()
res_cases <- dft_rast_break_class(break_series_list(cases, years),
                                  class_table = artifact_class_table())

test_that("strength is pmin(n_before, n_after), recovered from break_year alone", {
  # The guard against the two derivations drifting: dft_break_strength()
  # inverts break_year == years[idx + 1], while break_class_scan() sets
  # n_before/n_after directly. They must agree on every fixture, including the
  # NA ones.
  ev <- terra::values(res_cases$breaks)
  measured <- pmin(ev[, "n_before"], ev[, "n_after"])
  recovered <- dft_break_strength(ev[, "break_year"], res_cases$years)
  expect_gt(sum(!is.na(measured)), 0L)          # or the comparison is vacuous
  expect_identical(recovered, as.integer(measured))
})

test_that("the endpoint observations score 1 and the middle scores up to floor(n/2)", {
  expect_identical(dft_break_strength(2018:2023, years), c(1L, 2L, 3L, 3L, 2L, 1L))
  # strength < 2 is exactly break_year in the second or last observation, which
  # is the identity data-raw/break_class_groups.R's endpoint test relies on
  for (n in 2:8) {
    y <- seq(2017L, length.out = n)
    st <- dft_break_strength(y[-1], y)
    expect_identical(st < 2L, y[-1] %in% c(y[2], y[n]),
                     info = paste("series length", n))
  }
})

test_that("NA in, NA out -- a stable or flicker pixel has no break year", {
  expect_identical(dft_break_strength(c(2020L, NA_integer_), years), c(3L, NA_integer_))
  expect_identical(dft_break_strength(NA_integer_, years), NA_integer_)
  expect_identical(dft_break_strength(integer(0), years), integer(0))
})

test_that("a break year outside years[-1] is refused, not silently NA", {
  # years[1] gives idx 0 and would otherwise score 0; an absent year gives NA
  expect_error(dft_break_strength(2017L, years), "not in `years\\[-1\\]`: 2017")
  expect_error(dft_break_strength(1999L, years), "not in `years\\[-1\\]`: 1999")
  expect_error(dft_break_strength(c(2020L, 2099L), years), "2099")
})

test_that("`years` must be a sorted, unique, complete series of at least two", {
  expect_error(dft_break_strength(2020L, 2017L), "at least 2")
  expect_error(dft_break_strength(2020L, c(2017L, NA_integer_, 2019L)), "must not contain NA")
  expect_error(dft_break_strength(2020L, c(2017L, 2018L, 2018L)), "must be unique")
  expect_error(dft_break_strength(2020L, c(2019L, 2018L, 2017L)), "sorted ascending")
})

test_that("the unit is observations, not calendar years", {
  # a gapped series: 2020 is flanked by three calendar years each side and
  # still scores 1, because it is the second of three observations
  expect_identical(dft_break_strength(2020L, c(2017L, 2020L, 2023L)), 1L)
  expect_identical(dft_break_strength(2023L, c(2017L, 2020L, 2023L)), 1L)
})

test_that("no break can score 2 on a series shorter than four observations", {
  for (n in 2:3) {
    y <- seq(2017L, length.out = n)
    expect_true(all(dft_break_strength(y[-1], y) < 2L), info = paste("length", n))
  }
  expect_true(any(dft_break_strength(2018:2020, 2017:2020) >= 2L))
})

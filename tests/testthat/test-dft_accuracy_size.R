w_ol <- stats::setNames(olofsson_plan_weights, olofsson_classes)

test_that("Eq. 13 reproduces Olofsson section 5.1.1: n = 641", {
  plan <- dft_accuracy_size(w_ol, se_target = 0.01, ua = olofsson_plan_ua)
  expect_identical(plan$n, olofsson_plan_n)
  # the S_i column of Table 5
  expect_equal(unname(plan$s_h), c(0.458, 0.490, 0.300, 0.218), tolerance = 1e-3)
})

test_that("equal and proportional allocations reproduce Table 5", {
  eq <- dft_accuracy_size(w_ol, 0.01, ua = olofsson_plan_ua, allocation = "equal")
  expect_equal(unname(eq$allocation), olofsson_plan_equal)
  pr <- dft_accuracy_size(w_ol, 0.01, ua = olofsson_plan_ua,
                          allocation = "proportional")
  expect_equal(unname(pr$allocation), olofsson_plan_prop)
  expect_identical(names(pr$allocation), olofsson_classes)
})

test_that("proportional_min floors rare strata and splits the rest by weight", {
  # Olofsson's Alloc1 rule: 100 per change stratum, remainder proportional
  # among the stable ones. The paper prints 149/292 for the stable pair, which
  # its own rule does not give (441 * 0.32/0.965 = 146.2); this asserts the rule
  pm <- dft_accuracy_size(w_ol, 0.01, ua = olofsson_plan_ua, n_min = 100)
  expect_equal(unname(pm$allocation), c(100, 100, 146, 295))
  # a stratum pushed under the floor by the reallocation joins the floor
  w3 <- c(a = 0.01, b = 0.09, c = 0.90)
  p3 <- dft_accuracy_size(w3, se_target = 0.05, s_h = c(0.5, 0.5, 0.5),
                          n_min = 20)
  expect_identical(p3$n, 100)
  expect_equal(unname(p3$allocation[c("a", "b")]), c(20, 20))
  expect_equal(unname(p3$allocation["c"]), 60)
  # a floor bigger than the sample takes the floor everywhere
  p4 <- dft_accuracy_size(w3, se_target = 0.2, s_h = c(0.5, 0.5, 0.5), n_min = 20)
  expect_equal(unname(p4$allocation), c(20, 20, 20))
})

test_that("the s_h form agrees with the ua form when strata are the map classes", {
  s <- sqrt(olofsson_plan_ua * (1 - olofsson_plan_ua))
  a <- dft_accuracy_size(w_ol, 0.01, ua = olofsson_plan_ua)
  b <- dft_accuracy_size(w_ol, 0.01, s_h = s)
  expect_identical(a$n, b$n)
  expect_identical(a$allocation, b$allocation)
})

test_that("named s_h is matched to weights by name, not position", {
  s <- stats::setNames(sqrt(olofsson_plan_ua * (1 - olofsson_plan_ua)),
                       olofsson_classes)
  a <- dft_accuracy_size(w_ol, 0.01, s_h = s)
  b <- dft_accuracy_size(w_ol, 0.01, s_h = rev(s))
  expect_identical(a$n, b$n)
  expect_identical(a$s_h, b$s_h)
  bad <- stats::setNames(s, c("a", "b", "c", "d"))
  expect_error(dft_accuracy_size(w_ol, 0.01, s_h = bad), "name different strata")
})

test_that("a pilot's stratum table feeds the sizer", {
  est <- dft_accuracy_estimate(olofsson_labels(), olofsson_strata())
  ag <- est$stratum[est$stratum$target == "agreement", ]
  plan <- dft_accuracy_size(stats::setNames(ag$weight, ag$stratum),
                            se_target = 0.01, s_h = ag$sd)
  expect_gt(plan$n, 0)
  expect_identical(names(plan$allocation), ag$stratum)
})

test_that("degenerate and malformed inputs are refused", {
  expect_error(dft_accuracy_size(w_ol, 0.01, ua = rep(1, 4)), "SD of 0")
  expect_error(dft_accuracy_size(c(a = 0, b = 1), 0.01, s_h = c(0.1, 0.1)),
               "must be positive")
  expect_error(dft_accuracy_size(c(a = 0.5, b = 0.6), 0.01, s_h = c(0.1, 0.1)),
               "sum to 1")
  expect_error(dft_accuracy_size(w_ol, 0.01), "exactly one of")
  expect_error(dft_accuracy_size(w_ol, 0.01, s_h = rep(.1, 4), ua = rep(.9, 4)),
               "exactly one of")
  expect_error(dft_accuracy_size(w_ol, 0.01, ua = c(0.9, 1.2, 0.9, 0.9)),
               "between 0 and 1")
  expect_error(dft_accuracy_size(w_ol, 0.01, s_h = c(0.1, NA, 0.1, 0.1)),
               "one pilot point")
  expect_error(dft_accuracy_size(w_ol, 0.01, s_h = c(0.1, 0.1)), "one value per stratum")
  expect_error(dft_accuracy_size(w_ol, 0, ua = olofsson_plan_ua), "positive")
  expect_error(dft_accuracy_size(w_ol, 0.01, ua = olofsson_plan_ua, n_min = 1),
               "at least 2")
  # a zero SD in one stratum is allowed and contributes nothing to n
  z <- dft_accuracy_size(w_ol, 0.01, s_h = c(0, 0.49, 0.3, 0.218))
  expect_lt(z$n, olofsson_plan_n)
})

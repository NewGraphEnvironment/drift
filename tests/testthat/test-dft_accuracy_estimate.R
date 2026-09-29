# Published values are in helper-accuracy.R, each cited to Olofsson et al.
# (2014)'s page and table. Tolerances are ABSOLUTE and set at the published
# precision: 0.005 for proportions printed to 2 dp, 1 ha for areas printed to
# the ha, and 1.5 ha for area half-widths, which Stehman's finite population
# correction and exact z (vs the paper's 1.96, no FPC) move by up to 1.1 ha
# (findings.md).

ol <- dft_accuracy_estimate(olofsson_labels(), olofsson_strata())
by_class <- function(tbl, measure) {
  x <- tbl[tbl$measure == measure, ]
  x[match(olofsson_classes, x$class), ]
}

test_that("error-adjusted areas reproduce Olofsson et al. (2014) section 5.2.2", {
  a <- ol$area[match(olofsson_classes, ol$area$class), ]
  expect_within(a$area, olofsson_area, 1)
  expect_within(a$area - a$lower, olofsson_area_hw, 1.5)
  expect_within(a$upper - a$area, olofsson_area_hw, 1.5)
  expect_equal(ol$area_total, 900000)
})

test_that("the error matrix reproduces Olofsson Table 9 to 4 dp", {
  got <- matrix(NA_real_, 4, 4, dimnames = dimnames(olofsson_p))
  got[cbind(ol$matrix$map_class, ol$matrix$ref_class)] <- ol$matrix$proportion
  expect_within(got, olofsson_p, 5e-5)
  expect_equal(sum(ol$matrix$proportion), 1)
  # zeros are zeros, not NA (mapaccuracy returns empty cells as NA)
  expect_false(anyNA(ol$matrix$proportion))
})

test_that("accuracies reproduce Olofsson section 5.2.1 to 2 dp", {
  u <- by_class(ol$accuracy, "user")
  p <- by_class(ol$accuracy, "producer")
  o <- ol$accuracy[ol$accuracy$measure == "overall", ]
  expect_within(u$estimate, olofsson_user, 0.005)
  expect_within(u$upper - u$estimate, olofsson_user_hw, 0.005)
  expect_within(p$estimate, olofsson_prod, 0.005)
  # two of these are Eq. (7) values, not the printed ones (helper-accuracy.R)
  expect_within(p$upper - p$estimate, olofsson_prod_hw, 0.005)
  expect_within(o$estimate, olofsson_overall, 0.005)
  expect_within(o$upper - o$estimate, olofsson_overall_hw, 0.005)
  expect_true(is.na(o$class))
})

test_that("the stratum weights are load-bearing: equal weights give the wrong answer", {
  # the must-fail: the same labels through the estimator with every stratum the
  # same size, which is what an unweighted confusion matrix assumes
  flat <- dft_accuracy_estimate(olofsson_labels(),
                                olofsson_strata(rep(2.5e6, 4)))
  a <- flat$area[match(olofsson_classes, flat$area$class), ]
  expect_gt(abs(a$area[1] - olofsson_area[1]), 100000)   # vs 21,158 ha
  p <- by_class(flat$accuracy, "producer")
  expect_gt(max(abs(p$estimate - olofsson_prod)), 0.05)
})

test_that("perfect labels give accuracy 1, SE 0 and area equal to mapped area", {
  lab <- olofsson_labels()
  lab$ref_class <- lab$map_class
  res <- dft_accuracy_estimate(lab, olofsson_strata())
  expect_equal(res$accuracy$estimate, rep(1, 9))
  expect_equal(res$accuracy$se, rep(0, 9))
  a <- res$area[match(olofsson_classes, res$area$class), ]
  expect_equal(a$area, olofsson_pixels * 0.09, ignore_attr = TRUE)
  expect_equal(a$area_se, rep(0, 4))
})

test_that("a union's SE comes from recoding, and is not the sum of its members'", {
  lab <- olofsson_labels()
  change <- c("deforestation", "forest_gain")
  lab_u <- lab
  lab_u$map_class <- ifelse(lab$map_class %in% change, "change", "stable")
  lab_u$ref_class <- ifelse(lab$ref_class %in% change, "change", "stable")
  u <- dft_accuracy_estimate(lab_u, olofsson_strata())
  a <- ol$area[match(change, ol$area$class), ]
  ch <- u$area[u$area$class == "change", ]
  # the area is additive ...
  expect_equal(ch$area, sum(a$area))
  # ... the standard error is not
  expect_false(isTRUE(all.equal(ch$area_se, sum(a$area_se))))
  expect_lt(ch$area_se, sum(a$area_se))
})

test_that("the stratum table carries per-stratum means and SDs for sizing", {
  st <- ol$stratum
  expect_setequal(unique(st$target), c("agreement", olofsson_classes))
  ag <- st[st$target == "agreement", ]
  ag <- ag[match(olofsson_classes, ag$stratum), ]
  expect_equal(ag$n, c(75, 75, 165, 325))
  expect_equal(ag$mean, unname(diag(olofsson_counts)) / c(75, 75, 165, 325))
  p <- ag$mean
  expect_equal(ag$sd, sqrt(p * (1 - p) * c(75, 75, 165, 325) /
                             (c(75, 75, 165, 325) - 1)))
  expect_equal(sum(ag$weight), 1)
})

test_that("numeric classes are ordered numerically and returned numeric", {
  lab <- data.frame(point_id = 1:8, stratum = rep(c(2, 10), each = 4),
                    map_class = rep(c(2, 10), each = 4),
                    ref_class = c(2, 2, 2, 10, 10, 10, 10, 2))
  st <- data.frame(stratum = c(2, 10), n_cells = c(100, 300), area = c(1, 3))
  res <- dft_accuracy_estimate(lab, st)
  expect_identical(res$area$class, c(2, 10))
  expect_type(res$matrix$map_class, "double")
})

test_that("a reference-only class enters the matrix and producer's accuracy is NA off the reference", {
  lab <- olofsson_labels()
  lab$ref_class[1] <- "water"            # a class the map never uses
  res <- dft_accuracy_estimate(lab, olofsson_strata())
  expect_true("water" %in% res$area$class)
  expect_true("water" %in% res$matrix$ref_class)
  # no point is labelled forest_gain in the reference -> producer's NA
  lab2 <- olofsson_labels()
  lab2$ref_class[lab2$ref_class == "forest_gain"] <- "stable_forest"
  res2 <- dft_accuracy_estimate(lab2, olofsson_strata())
  pa <- res2$accuracy[res2$accuracy$measure == "producer" &
                        res2$accuracy$class == "forest_gain", ]
  expect_true(is.na(pa$estimate))
})

test_that("strata that are not the map classes are estimated, with estimated row totals", {
  # two strata that cut across all four map classes
  lab <- olofsson_labels()
  lab$stratum <- ifelse(seq_len(nrow(lab)) %% 2 == 0, "a", "b")
  st <- data.frame(stratum = c("a", "b"), n_cells = c(4e6, 6e6),
                   area = c(4e6, 6e6) * 0.09)
  res <- dft_accuracy_estimate(lab, st)
  rows <- tapply(res$matrix$proportion, res$matrix$map_class, sum)
  expect_equal(sum(rows), 1)
  # the map-class shares are estimated from the sample, not the Olofsson W_i
  shares <- as.vector(rows[olofsson_classes])
  expect_gt(max(abs(shares - olofsson_pixels / 1e7)), 0.05)
  expect_true(all(is.finite(res$area$area_se)))
})

test_that("a census stratum contributes no variance and is not refused", {
  lab <- data.frame(point_id = 1:7,
                    stratum   = c(1, 1, 1, 1, 1, 2, 2),
                    map_class = c(1, 1, 1, 1, 1, 2, 2),
                    ref_class = c(1, 1, 2, 1, 1, 2, 1))
  # stratum 2 has exactly two cells, both labelled
  st <- data.frame(stratum = c(1, 2), n_cells = c(1000, 2), area = c(10, 0.02))
  res <- dft_accuracy_estimate(lab, st)
  s2 <- res$stratum[res$stratum$stratum == 2 & res$stratum$target == "agreement", ]
  expect_equal(s2$n, 2)
  expect_true(all(is.finite(res$area$area_se)))
  # a one-point census is allowed; the warning mapaccuracy raises is muffled
  lab1 <- lab[-7, ]
  st1 <- data.frame(stratum = c(1, 2), n_cells = c(1000, 1), area = c(10, 0.01))
  expect_no_warning(dft_accuracy_estimate(lab1, st1))
})

test_that("the design refusals name what is wrong", {
  lab <- olofsson_labels()
  st <- olofsson_strata()

  lab_t <- lab
  lab_t$use <- "accuracy"
  lab_t$use[1:3] <- "training"
  expect_error(dft_accuracy_estimate(lab_t, st), "3 row\\(s\\) have `use == \"training\"`")

  lab_na <- lab
  lab_na$ref_class[5] <- NA
  expect_error(dft_accuracy_estimate(lab_na, st), "`ref_class` has 1 missing.*nonresponse")

  lab_dup <- lab
  lab_dup$point_id[2] <- lab_dup$point_id[1]
  expect_error(dft_accuracy_estimate(lab_dup, st), "must be unique; duplicated: p0001")

  lab_unk <- lab
  lab_unk$stratum[1] <- "mystery"
  expect_error(dft_accuracy_estimate(lab_unk, st), "absent from `strata`: mystery")

  st_extra <- rbind(st, tibble::tibble(stratum = "water", n_cells = 10,
                                       area = 0.9, weight = 0))
  expect_error(dft_accuracy_estimate(lab, st_extra), "cells but no labels: water")

  first_gain <- match("forest_gain", lab$stratum)
  lab_one <- lab[lab$stratum != "forest_gain" | seq_len(nrow(lab)) == first_gain, ]
  expect_error(dft_accuracy_estimate(lab_one, st), "single labelled point: forest_gain")

  expect_error(dft_accuracy_estimate(lab, st[, c("stratum", "n_cells")]),
               "needs an `area` column")
  st_grid <- st
  st_grid$area[1] <- st_grid$area[1] * 2
  expect_error(dft_accuracy_estimate(lab, st_grid), "describe different grids")
  expect_error(dft_accuracy_estimate(lab, st, level = 95), "between 0 and 1")

  lab_use <- lab
  lab_use$use <- "test"
  expect_error(dft_accuracy_estimate(lab_use, st), "got: test")
})

test_that("a factor in one class column adds no phantom classes", {
  # c() of a factor and a numeric falls back to the factor's integer codes
  lab <- data.frame(point_id = 1:6, stratum = c(1, 1, 1, 2, 2, 2),
                    map_class = c(1001, 1001, 2002, 2002, 2002, 1001),
                    ref_class = factor(c(1001, 2002, 2002, 2002, 1001, 1001)))
  st <- data.frame(stratum = 1:2, n_cells = c(100, 100), area = c(1, 1))
  res <- dft_accuracy_estimate(lab, st)
  expect_identical(res$area$class, c("1001", "2002"))
  lab$ref_class <- as.character(lab$ref_class)
  lab$map_class <- factor(lab$map_class)
  expect_identical(dft_accuracy_estimate(lab, st)$area$class, c("1001", "2002"))
})

test_that("a blank reference label is nonresponse, refused like NA", {
  # read.csv() and fread() read an empty cell as "", not NA
  lab <- olofsson_labels()
  lab$ref_class[3] <- ""
  expect_error(dft_accuracy_estimate(lab, olofsson_strata()),
               "`ref_class` has 1 missing or blank")
  lab$ref_class[3] <- "  "
  expect_error(dft_accuracy_estimate(lab, olofsson_strata()), "missing or blank")
})

test_that("a double and an integer column holding the same code are one class", {
  # as.character(100000) is "1e+05"; as.character(100000L) is "100000"
  lab <- data.frame(point_id = 1:6, stratum = c(1L, 1L, 1L, 2L, 2L, 2L),
                    map_class = c(100000, 100000, 2002, 2002, 2002, 100000),
                    ref_class = c(100000L, 100000L, 2002L, 2002L, 2002L, 100000L))
  st <- data.frame(stratum = c(1, 2), n_cells = c(100, 100), area = c(1, 1))
  res <- dft_accuracy_estimate(lab, st)
  expect_identical(res$area$class, c(2002, 100000))
  expect_equal(res$accuracy$estimate[res$accuracy$measure == "overall"], 1)
  expect_true("100000" %in% res$stratum$target)
})

test_that("a factor of numeric codes meets a numeric column as one class", {
  # levels(factor(100000)) is "1e+05"
  lab <- data.frame(point_id = 1:8, stratum = rep(1:2, each = 4),
                    map_class = factor(rep(c(100000, 2002), each = 4)),
                    ref_class = c(100000, 100000, 100000, 2002,
                                  2002, 2002, 2002, 100000))
  st <- data.frame(stratum = 1:2, n_cells = c(100, 100), area = c(1, 1))
  res <- dft_accuracy_estimate(lab, st)
  expect_identical(res$area$class, c("2002", "100000"))
  expect_equal(res$accuracy$estimate[res$accuracy$measure == "overall"], 0.75)
})

test_that("a blank `use` cell is NA, as the contract allows", {
  lab <- olofsson_labels()
  lab$use <- ""
  lab$use[1] <- "accuracy"
  expect_no_error(dft_accuracy_estimate(lab, olofsson_strata()))
})

test_that("a census stratum reports sd 0, so the sizer can use it", {
  lab <- data.frame(point_id = 1:6, stratum = c(1, 1, 1, 1, 1, 2),
                    map_class = c(1, 1, 1, 1, 1, 2),
                    ref_class = c(1, 1, 2, 1, 1, 2))
  st <- data.frame(stratum = c(1, 2), n_cells = c(1000, 1), area = c(10, 0.01))
  res <- dft_accuracy_estimate(lab, st)
  s2 <- res$stratum[res$stratum$stratum == 2, ]
  expect_true(all(s2$sd == 0))
  ag <- res$stratum[res$stratum$target == "agreement", ]
  expect_no_error(dft_accuracy_size(stats::setNames(ag$weight, ag$stratum),
                                    se_target = 0.05, s_h = ag$sd, n_min = 2))
})

test_that("labels in a stratum with no cells are refused by name", {
  lab <- olofsson_labels()
  st <- olofsson_strata()
  st$n_cells[st$stratum == "forest_gain"] <- 0
  st$area[st$stratum == "forest_gain"] <- 0
  expect_error(dft_accuracy_estimate(lab, st), "no cells in `strata`: forest_gain")
})

test_that("expect_within() refuses a short vector that recycles", {
  expect_failure(expect_within(c(1, 2), c(1, 2, 1, 2), 0.1))
  expect_success(expect_within(c(1, 2), c(1.05, 2), 0.1))
})

test_that("level sets the interval width through qnorm", {
  r90 <- dft_accuracy_estimate(olofsson_labels(), olofsson_strata(), level = 0.90)
  hw <- r90$area$upper - r90$area$area
  expect_equal(hw, stats::qnorm(0.95) * r90$area$area_se)
})

years <- 2017:2023
cases <- break_series_cases()
res_cases <- dft_rast_break_class(break_series_list(cases, years),
                                  class_table = artifact_class_table())

# the fixture pixels are one per case, laid out so cell i == matrix row i, so a
# per-case category comes from the pixel evidence rather than from the summary
case_category <- function(res) {
  ev <- as.data.frame(terra::values(res$breaks))
  ev$strength <- dft_break_strength(ev$break_year, res$years)
  tr <- terra::values(res$raster)[, 1]
  code <- break_category_code(ev$n_flips, ev$strength, tr %/% 1000L != tr %% 1000L)
  stats::setNames(break_category_levels()[code + 1L], rownames(cases))
}

test_that("the five levels are fixed, ordered, and match the shipped cartography", {
  lv <- break_category_levels()
  expect_identical(lv, c("stable", "break_sustained", "break_endpoint",
                         "unsettled", "stable_flicker"))
  # ids 0:4 in this order are keyed on by inst/cartography/drift_temporal.csv,
  # which the temporal-composition article reads through gq, and by that
  # article's colour table, which keys on the integers. Nothing else stops the
  # vocabulary and the colours drifting apart.
  reg <- utils::read.csv(system.file("cartography", "drift_temporal.csv",
                                     package = "drift"), stringsAsFactors = FALSE)
  reg <- reg[reg$layer_key == "temporal_category", ]
  expect_gt(nrow(reg), 0L)                       # premise: the layer is in the file
  expect_identical(reg$class_value, lv)
})

test_that("named fixtures land in the level their name describes", {
  got <- case_category(res_cases)
  expect_identical(got[["stable"]], "stable")
  # break_year is the FIRST year of the new class, so the series' second and
  # last observations are the two that leave a side of length one
  expect_identical(got[["switch_2018"]], "break_endpoint")
  expect_identical(got[["switch_2023"]], "break_endpoint")
  expect_identical(got[["switch_2019"]], "break_sustained")
  expect_identical(got[["switch_2020"]], "break_sustained")
  expect_identical(got[["switch_2021"]], "break_sustained")
  expect_identical(got[["switch_2022"]], "break_sustained")
})

test_that("the two flicker populations are separate levels -- the pooling bug", {
  got <- case_category(res_cases)
  # one pixel each, and they are the whole defect: `flicker` reads identically
  # at both endpoints and is invisible to a two-epoch comparison, while
  # `flicker_diff` is part of what that comparison reports as change
  expect_identical(got[["flicker"]], "stable_flicker")
  expect_identical(got[["flicker_diff"]], "unsettled")
  expect_identical(got[["settling"]], "unsettled")
})

test_that("an interior NA year is labelled NA, not refused", {
  # dft_rast_break_class()'s own @examples series carries one of these
  got <- case_category(res_cases)
  expect_true(is.na(got[["na_year"]]))
  s <- res_cases$summary
  out <- dft_break_category(res_cases)
  expect_true(any(is.na(s$status)))
  expect_true(all(is.na(out$category[is.na(out$status)])))
})

test_that("summary grain: columns appended, class and row order preserved", {
  s <- res_cases$summary
  out <- dft_break_category(res_cases)
  expect_s3_class(out, "tbl_df")
  expect_identical(names(out), c(names(s), "category", "strength", "rule"))
  expect_identical(out[names(s)], s)              # nothing existing was touched
  expect_s3_class(out$category, "factor")
  expect_identical(levels(out$category), break_category_levels())
  expect_type(out$strength, "integer")
  expect_identical(unique(out$rule), "v1")
  # a plain data frame stays a plain data frame
  df <- dft_break_category(as.data.frame(s), years = years)
  expect_s3_class(df, "data.frame")
  expect_false(inherits(df, "tbl_df"))
  expect_identical(as.character(df$category), as.character(out$category))
})

test_that("a zero-row summary returns a zero-row frame, not an error", {
  s <- res_cases$summary[0, ]
  out <- dft_break_category(s, years = years)
  expect_identical(nrow(out), 0L)
  expect_identical(levels(out$category), break_category_levels())
})

test_that("the inputs it cannot label are named errors, not NA", {
  s <- as.data.frame(res_cases$summary)
  expect_error(dft_break_category(s), "`years` is required")
  expect_error(dft_break_category(s[c("status", "break_year")], years = years),
               "missing the columns from_class, to_class")
  bad <- s
  bad$status[1] <- "settled"
  expect_error(dft_break_category(bad, years = years),
               "unrecognised `status` value: settled")
  noyr <- s
  noyr$break_year[noyr$status == "break"] <- NA_integer_
  expect_error(dft_break_category(noyr, years = years), "carry no `break_year`")
  expect_error(dft_break_category(res_cases[c("raster", "breaks", "summary")]),
               "carries no `years`.*drift < 0\\.16\\.0")
  expect_error(dft_break_category(list(years = years)), "has no `summary`")
  expect_error(dft_break_category(1:3), "not integer")
  # a class code missing from the class table gives an NA class NAME, which would
  # make `changed` NA and hand back an NA category on a row whose status is fine
  # -- indistinguishable from the NA that means "could not be scanned"
  partial <- s
  partial$from_class[which(partial$status %in% "flicker")[1]] <- NA_character_
  expect_error(dft_break_category(partial, years = years), "carries an NA class name")
})

test_that("`rule` is validated by name and recorded in the output", {
  expect_error(dft_break_category(res_cases, rule = "v2"),
               'unsupported `rule`: v2\\. Supported: "v1"')
  expect_error(dft_break_category(res_cases, rule = c("v1", "v1")), "unsupported")
  # the rule travels as a COLUMN: every consumer here writes CSV, which drops
  # attributes, so an attribute could not identify old output
  out <- dft_break_category(res_cases)
  expect_true("rule" %in% names(out))
  f <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(out, f, row.names = FALSE)
  expect_identical(unique(utils::read.csv(f)$rule), "v1")
})

test_that("`years` passed alongside a result that carries its own is ignored, loudly", {
  expect_warning(out <- dft_break_category(res_cases, years = years),
                 "`years` ignored")
  expect_identical(out, dft_break_category(res_cases))
})

test_that("break_sustained is unreachable on a series shorter than four", {
  x2 <- break_series_list(cases[, c(1, 7)], years = c(2017L, 2023L))
  res <- dft_rast_break_class(x2, class_table = artifact_class_table())
  out <- dft_break_category(res)
  expect_identical(levels(out$category), break_category_levels())   # level kept
  expect_false("break_sustained" %in% as.character(out$category))   # but empty
  expect_true("break_endpoint" %in% as.character(out$category))
})

test_that("bundled seven-year series: the split of the two-epoch changed area", {
  # Pinned against test-dft_rast_break_class.R's own numbers for the same
  # series -- 3403 changed, of which 1098 sustained, 776 + 264 endpoint and
  # 1265 flicker, plus 2791 that flicker with the endpoints agreeing.
  years7 <- 2017:2023
  x <- lapply(years7, function(yr) {
    terra::rast(system.file("extdata", paste0("example_", yr, ".tif"), package = "drift"))
  })
  names(x) <- years7
  out <- dft_break_category(dft_rast_break_class(dft_rast_classify(x, source = "io-lulc")))
  n <- tapply(out$n_cells, out$category, sum)
  expect_equal(as.vector(n[c("break_sustained", "break_endpoint", "unsettled",
                             "stable_flicker")]),
               c(1098L, 1040L, 1265L, 2791L))
  changed <- sum(out$n_cells[out$from_class != out$to_class])
  expect_equal(changed, 3403L)
  expect_equal(sum(n[c("break_sustained", "break_endpoint", "unsettled")]), changed)
})

test_that("the flicker split is BY endpoint equality, which is what pooling loses", {
  # The regression guard, stated as the property rather than as an arithmetic
  # coincidence: an earlier version asserted that no level carried
  # changed + stable_flicker, which the four expect_equal()s above had already
  # made unfalsifiable while leaving it 77 cells from a false alarm on `stable`,
  # the one level nothing pins. What actually fails if the two populations are
  # pooled back together is this -- every `unsettled` row differs at the
  # endpoints and every `stable_flicker` row does not.
  out <- dft_break_category(res_cases)
  uns <- out[out$category %in% "unsettled", ]
  stf <- out[out$category %in% "stable_flicker", ]
  expect_gt(nrow(uns), 0L)                      # premise: both populations present
  expect_gt(nrow(stf), 0L)
  expect_true(all(uns$from_class != uns$to_class))
  expect_true(all(stf$from_class == stf$to_class))
  # and they are disjoint from the clean switches, which is why summing any two
  # of the three answers a different question than each does alone
  brk <- out[out$category %in% c("break_sustained", "break_endpoint"), ]
  expect_true(all(brk$status == "break"))
  expect_true(all(c(uns$status, stf$status) == "flicker"))
})

test_that("BULK: the pooled and unpooled totals, and the 69% overstatement", {
  # inst/extdata/temporal-composition/summary_groups.csv ships; it is the
  # published record of what data-raw/break_class_groups.R measured on the
  # Bulkley floodplain (drift#62, #66).
  g <- utils::read.csv(system.file("extdata", "temporal-composition",
                                   "summary_groups.csv", package = "drift"),
                       stringsAsFactors = FALSE)
  b <- g[g$group == "bulk", ]
  expect_identical(nrow(b), 1L)
  expect_equal(b$changed_ha, 4625.0)
  expect_equal(b$stable_flicker_ha, 3186.5)
  pooled <- b$changed_ha + b$stable_flicker_ha
  expect_equal(pooled, 7811.5)
  expect_equal(round(pooled / b$changed_ha - 1, 3), 0.689)
})

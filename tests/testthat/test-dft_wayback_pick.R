wb_cap <- function(...) {
  base <- list(feature = 1L, release_id = "100",
               release_date = as.Date("2024-03-07"),
               capture_date = as.Date("2017-06-11"), res_m = 0.5,
               source = "Maxar WV02", zoom = 18L, cover = 1)
  rows <- list(...)
  do.call(rbind, lapply(rows, function(r) {
    b <- utils::modifyList(base, r)
    b$release_date <- as.Date(b$release_date)
    b$capture_date <- as.Date(b$capture_date)
    tibble::as_tibble(b)
  }))
}

d17 <- as.Date("2017-07-01")

test_that("the nearest capture wins, either side of the date", {
  cap <- wb_cap(list(capture_date = "2016-09-30", release_id = "1"),
                list(capture_date = "2017-08-01", release_id = "2"),
                list(capture_date = "2013-08-01", release_id = "3"))
  p <- dft_wayback_pick(cap, d17)
  expect_identical(p$capture_date, as.Date("2017-08-01"))
  expect_identical(p$days_from_date, 31L)
  expect_identical(p$date, d17)
})

test_that("days_from_date is signed", {
  cap <- wb_cap(list(capture_date = "2017-06-11"))
  expect_identical(dft_wayback_pick(cap, d17)$days_from_date, -20L)
})

test_that("on equal distance the finer source wins", {
  cap <- wb_cap(list(capture_date = "2017-06-11", res_m = 0.5, release_id = "1"),
                list(capture_date = "2017-07-21", res_m = 0.3, release_id = "2"))
  expect_identical(dft_wayback_pick(cap, d17)$res_m, 0.3)
})

test_that("then the later release", {
  cap <- wb_cap(list(release_date = "2020-04-29", release_id = "900"),
                list(release_date = "2024-03-07", release_id = "100"))
  expect_identical(dft_wayback_pick(cap, d17)$release_id, "100")
})

test_that("then the larger release id, compared as a number", {
  # as strings "9" > "10"; as numbers 10 wins
  cap <- wb_cap(list(release_id = "9"), list(release_id = "10"))
  expect_identical(dft_wayback_pick(cap, d17)$release_id, "10")
  # and larger, not smaller: an ascending string order would take "8"
  cap <- wb_cap(list(release_id = "8"), list(release_id = "9"))
  expect_identical(dft_wayback_pick(cap, d17)$release_id, "9")
})

test_that("then the larger cover, then the earlier capture", {
  cap <- wb_cap(list(capture_date = "2017-06-21", cover = 0.4),
                list(capture_date = "2017-07-11", cover = 0.6))
  expect_identical(dft_wayback_pick(cap, d17)$cover, 0.6)
  cap <- wb_cap(list(capture_date = "2017-07-11", cover = 0.5),
                list(capture_date = "2017-06-21", cover = 0.5))
  expect_identical(dft_wayback_pick(cap, d17)$capture_date,
                   as.Date("2017-06-21"))
})

test_that("one row per feature and date, sorted", {
  cap <- wb_cap(list(feature = 2L, capture_date = "2023-08-25"),
                list(feature = 1L, capture_date = "2017-06-11"),
                list(feature = 1L, capture_date = "2023-07-02"))
  p <- dft_wayback_pick(cap, c("2023-07-01", "2017-07-01", "2017-07-01"))
  expect_identical(p$feature, c(1L, 1L, 2L, 2L))
  expect_identical(p$date, as.Date(c("2017-07-01", "2023-07-01",
                                     "2017-07-01", "2023-07-01")))
  expect_identical(p$capture_date, as.Date(c("2017-06-11", "2023-07-02",
                                             "2023-08-25", "2023-08-25")))
  expect_identical(names(p)[1:2], c("feature", "date"))
  expect_identical(names(p)[ncol(p)], "days_from_date")
})

test_that("a feature with no dated capture has no row", {
  cap <- wb_cap(list(feature = 1L), list(feature = 2L, capture_date = NA))
  expect_identical(dft_wayback_pick(cap, d17)$feature, 1L)
})

test_that("an empty captures table passes through", {
  cap <- wb_cap(list(feature = 1L))[0, ]
  p <- dft_wayback_pick(cap, d17)
  expect_identical(nrow(p), 0L)
  expect_true(all(c("feature", "date", "days_from_date") %in% names(p)))
})

test_that("tiebreak columns are optional", {
  cap <- tibble::tibble(feature = c(1L, 1L), res_m = c(1, 0.5),
                        capture_date = as.Date(c("2017-06-01", "2017-07-31")))
  expect_identical(dft_wayback_pick(cap, d17)$res_m, 0.5)
})

test_that("inputs are checked", {
  cap <- wb_cap(list(feature = 1L))
  expect_error(dft_wayback_pick(cap, NA), "no NA")
  expect_error(dft_wayback_pick(cap, "July"), "no NA")
  expect_error(dft_wayback_pick(cap, as.Date(character(0))), "no NA")
  expect_error(dft_wayback_pick(data.frame(x = 1), d17),
               "dft_wayback_captures")
})

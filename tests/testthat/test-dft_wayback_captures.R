wb_run <- function(aoi, spec, zoom = 17:19, releases = wb_releases(),
                   page_size = 1000L, cache_dir = withr::local_tempdir(.local_envir = parent.frame()),
                   force = FALSE) {
  svc <- wb_service(spec, page_size)
  testthat::local_mocked_bindings(wayback_get = svc$fn)
  out <- dft_wayback_captures(aoi, zoom = zoom, releases = releases,
                              cache_dir = cache_dir, force = force)
  attr(out, "calls") <- svc$calls()
  out
}

big <- function(...) wb_square(wb_x0 - 500, wb_y0 - 500, 1000)

test_that("layer L is reported as zoom 23 - L", {
  spec <- list(R1 = list("6" = list(wb_footprint(list(big())))))
  cap <- wb_run(wb_point(0, 0), spec)
  expect_identical(cap$zoom, 17L)
  expect_identical(cap$capture_date, as.Date("2017-06-11"))
  expect_identical(cap$source, "Maxar WV02")
  expect_identical(cap$res_m, 0.5)
  expect_identical(cap$release_id, "100")
  expect_identical(cap$cover, 1)
})

test_that("only the queried zooms are read", {
  spec <- list(R1 = list("4" = list(wb_footprint(list(big())))))
  expect_warning(cap <- wb_run(wb_point(0, 0), spec, zoom = 17:18),
                 "No Wayback capture")
  expect_identical(nrow(cap), 0L)
  cap <- wb_run(wb_point(0, 0), spec, zoom = 19)
  expect_identical(cap$zoom, 19L)
})

test_that("the deepest covering zoom wins per feature and release", {
  spec <- list(R1 = list(
    "6" = list(wb_footprint(list(big()), date = 20130801)),
    "5" = list(wb_footprint(list(big()), date = 20160930))
  ))
  cap <- wb_run(wb_point(0, 0), spec)
  expect_identical(nrow(cap), 1L)
  expect_identical(cap$zoom, 18L)
  expect_identical(cap$capture_date, as.Date("2016-09-30"))
})

test_that("for a point, the footprint drawn on top wins, then the finer one", {
  spec <- list(R1 = list("5" = list(
    wb_footprint(list(big()), date = 20160101, draw = 1, res = 0.3),
    wb_footprint(list(big()), date = 20150101, draw = 2, res = 0.5)
  )))
  cap <- wb_run(wb_point(0, 0), spec)
  expect_identical(cap$capture_date, as.Date("2015-01-01"))

  spec <- list(R1 = list("5" = list(
    wb_footprint(list(big()), date = 20160101, draw = 1, res = 0.5),
    wb_footprint(list(big()), date = 20150101, draw = 1, res = 0.3)
  )))
  cap <- wb_run(wb_point(0, 0), spec)
  expect_identical(cap$capture_date, as.Date("2015-01-01"))
})

test_that("a polygon gets every capture it shows, with its visible cover", {
  # a 100 x 100 m patch: the west half in A (drawn on top), all of it in B
  patch <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(wb_x0, wb_y0), c(wb_x0, wb_y0 + 100), c(wb_x0 + 100, wb_y0 + 100),
    c(wb_x0 + 100, wb_y0), c(wb_x0, wb_y0)
  ))), crs = 3857))
  spec <- list(R1 = list("5" = list(
    wb_footprint(list(wb_square(wb_x0 - 1000, wb_y0 - 500, 1050)),
                 date = 20150101, draw = 2),
    wb_footprint(list(big()), date = 20160101, draw = 1)
  )))
  cap <- wb_run(patch, spec)
  expect_identical(nrow(cap), 2L)
  expect_equal(cap$cover[cap$capture_date == as.Date("2015-01-01")], 0.5,
               tolerance = 1e-6)
  # B is drawn beneath A, so it shows only over the east half
  expect_equal(cap$cover[cap$capture_date == as.Date("2016-01-01")], 0.5,
               tolerance = 1e-6)
})

wb_patch <- function() {
  sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(wb_x0, wb_y0), c(wb_x0, wb_y0 + 100), c(wb_x0 + 100, wb_y0 + 100),
    c(wb_x0 + 100, wb_y0), c(wb_x0, wb_y0)
  ))), crs = 3857))
}

test_that("a capture wholly hidden under another earns no row", {
  spec <- list(R1 = list("5" = list(
    wb_footprint(list(big()), date = 20150101, draw = 2),
    wb_footprint(list(big()), date = 20160101, draw = 1)
  )))
  cap <- wb_run(wb_patch(), spec)
  expect_identical(cap$capture_date, as.Date("2015-01-01"))
  expect_identical(cap$cover, 1)
})

test_that("an undated deepest layer hides a dated shallower one", {
  # the tiles at zoom 18 show a base layer, so this release has no capture to
  # offer; falling back to zoom 17 would report imagery the deep tiles lack
  spec <- list(R1 = list(
    "5" = list(wb_footprint(list(big()), date = NULL)),
    "6" = list(wb_footprint(list(big()), date = 20150101))
  ))
  expect_warning(cap <- wb_run(wb_point(0, 0), spec), "base layers")
  expect_identical(nrow(cap), 0L)
})

test_that("a polygon keeps the deepest zoom that covers it whole", {
  # zoom 19 covers a corner only, zoom 18 all of it, zoom 17 all of it
  spec <- list(R1 = list(
    "4" = list(wb_footprint(list(wb_square(wb_x0 - 500, wb_y0 - 500, 520)),
                            date = 20190101)),
    "5" = list(wb_footprint(list(big()), date = 20180101)),
    "6" = list(wb_footprint(list(big()), date = 20170101))
  ))
  cap <- wb_run(wb_patch(), spec)
  expect_identical(cap$zoom, 18L)
  expect_identical(cap$capture_date, as.Date("2018-01-01"))

  # where no zoom covers it whole, the zoom covering most of it
  spec <- list(R1 = list(
    "4" = list(wb_footprint(list(wb_square(wb_x0 - 500, wb_y0 - 500, 520)),
                            date = 20190101)),
    "5" = list(wb_footprint(list(wb_square(wb_x0 - 500, wb_y0 - 500, 560)),
                            date = 20180101))
  ))
  cap <- wb_run(wb_patch(), spec)
  expect_identical(cap$zoom, 18L)
  expect_equal(cap$cover, 0.36, tolerance = 1e-6)  # a 60 x 60 m corner
})

test_that("one capture split over two footprints is one row, its cover summed", {
  patch <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(wb_x0, wb_y0), c(wb_x0, wb_y0 + 100), c(wb_x0 + 100, wb_y0 + 100),
    c(wb_x0 + 100, wb_y0), c(wb_x0, wb_y0)
  ))), crs = 3857))
  spec <- list(R1 = list("5" = list(
    wb_footprint(list(wb_square(wb_x0 - 1000, wb_y0 - 500, 1050))),
    wb_footprint(list(wb_square(wb_x0 + 50, wb_y0 - 500, 1000)))
  )))
  cap <- wb_run(patch, spec)
  expect_identical(nrow(cap), 1L)
  expect_equal(cap$cover, 1, tolerance = 1e-6)
})

test_that("a footprint with no capture date is a base layer, not a capture", {
  spec <- list(R1 = list("5" = list(wb_footprint(list(big()), date = NULL))))
  expect_warning(cap <- wb_run(wb_point(0, 0), spec), "base layers")
  expect_identical(nrow(cap), 0L)
})

test_that("a base layer on top hides the capture beneath it at a point", {
  spec <- list(R1 = list("5" = list(
    wb_footprint(list(big()), date = NULL, draw = 3),
    wb_footprint(list(big()), date = 20160101, draw = 1)
  )), R2 = list("5" = list(wb_footprint(list(big()), date = 20190101))))
  cap <- wb_run(wb_point(0, 0), spec, releases = wb_releases(2))
  expect_identical(cap$release_id, "200")
})

test_that("an unreadable date format aborts rather than reading as no imagery", {
  spec <- list(R1 = list("5" = list(wb_footprint(list(big()),
                                                 date = "2017-06-11"))))
  expect_error(wb_run(wb_point(0, 0), spec), "capture date could be read")
})

test_that("a footprint with two outer rings matches in either", {
  rings <- list(wb_square(wb_x0 - 500, wb_y0 - 500, 100),
                wb_square(wb_x0 + 200, wb_y0 + 200, 100))
  spec <- list(R1 = list("5" = list(wb_footprint(rings))))
  cap <- wb_run(rbind(wb_point(-450, -450), wb_point(250, 250),
                      wb_point(0, 0)), spec)
  expect_identical(cap$feature, c(1L, 2L))
})

test_that("a point in a footprint's hole is not covered", {
  rings <- list(wb_square(wb_x0 - 500, wb_y0 - 500, 1000),
                rev(wb_square(wb_x0 - 50, wb_y0 - 50, 100)))
  spec <- list(R1 = list("5" = list(wb_footprint(rings))))
  cap <- wb_run(rbind(wb_point(0, 0), wb_point(300, 300)), spec)
  expect_identical(cap$feature, 2L)
})

test_that("every page of a paged answer is read", {
  fps <- lapply(1:5, function(i) {
    wb_footprint(list(wb_square(wb_x0 + 1000 * i, wb_y0, 100)),
                 date = 20100101 + i)
  })
  spec <- list(R1 = list("5" = fps))
  pts <- do.call(rbind, lapply(1:5, function(i) wb_point(1000 * i + 50, 50)))
  cap <- wb_run(pts, spec, zoom = 18, page_size = 2L)
  expect_identical(cap$feature, 1:5)
  # 3 pages for one layer
  expect_identical(attr(cap, "calls"), 3L)
})

test_that("metadata is cached, and force re-reads it", {
  spec <- list(R1 = list("5" = list(wb_footprint(list(big())))))
  dir <- withr::local_tempdir()
  a <- wb_run(wb_point(0, 0), spec, cache_dir = dir)
  expect_identical(attr(a, "calls"), 3L)
  b <- wb_run(wb_point(0, 0), spec, cache_dir = dir)
  expect_identical(attr(b, "calls"), 0L)
  expect_identical(a$capture_date, b$capture_date)
  f <- wb_run(wb_point(0, 0), spec, cache_dir = dir, force = TRUE)
  expect_identical(attr(f, "calls"), 3L)
  # a moved aoi is a new query box, so a new entry
  m <- wb_run(wb_point(100, 0), spec, cache_dir = dir)
  expect_identical(attr(m, "calls"), 3L)
})

test_that("rows are per release and sorted by release date", {
  spec <- list(R1 = list("5" = list(wb_footprint(list(big()), date = 20150101))),
               R2 = list("5" = list(wb_footprint(list(big()), date = 20190101))))
  rel <- wb_releases(2)[2:1, ]
  cap <- wb_run(wb_point(0, 0), spec, releases = rel)
  expect_identical(cap$release_id, c("100", "200"))
  expect_identical(names(cap), c("feature", "release_id", "release_date",
                                 "capture_date", "res_m", "source", "zoom",
                                 "cover"))
})

test_that("inputs are checked", {
  line <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(
    c(wb_x0, wb_y0), c(wb_x0 + 1, wb_y0 + 1)
  )), crs = 3857))
  expect_error(dft_wayback_captures(line, releases = wb_releases()),
               "points or polygons")
  expect_error(dft_wayback_captures(wb_point(0, 0), zoom = 9,
                                    releases = wb_releases()), "10 to 22")
  expect_error(dft_wayback_captures(wb_point(0, 0), zoom = 23,
                                    releases = wb_releases()), "10 to 22")
  expect_error(dft_wayback_captures(wb_point(0, 0), zoom = 17.5,
                                    releases = wb_releases()), "10 to 22")
  expect_error(dft_wayback_captures(wb_point(0, 0),
                                    releases = wb_releases()[0, ]), "no rows")
  expect_error(dft_wayback_captures(wb_point(0, 0),
                                    releases = data.frame(x = 1)),
               "dft_wayback_releases")
})

test_that("live captures over a Neexdzii Kwa point", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "set DRIFT_TEST_NETWORK=true to run network tests")
  pt <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(-126.2, 54.4)),
                                        crs = 4326))
  rel <- dft_wayback_releases()
  rel <- rel[rel$release_date >= as.Date("2023-01-01"), ][1:3, ]
  cap <- dft_wayback_captures(pt, releases = rel,
                              cache_dir = withr::local_tempdir())
  expect_gt(nrow(cap), 0)
  expect_true(all(cap$capture_date <= cap$release_date))
  expect_true(all(cap$zoom %in% 17:19))
})

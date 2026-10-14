wb_fetch <- function(aoi, empty_px = 0L, cache_dir = withr::local_tempdir(.local_envir = parent.frame()),
                     ...) {
  src <- wb_local_source(withr::local_tempdir(), empty_px)
  calls <- 0L
  testthat::local_mocked_bindings(wayback_source = function(release, zoom) {
    calls <<- calls + 1L
    src
  })
  r <- dft_wayback_fetch(aoi, "60013", 18, crs = "EPSG:3857", res = 1,
                         cache_dir = cache_dir, ...)
  attr(r, "calls") <- calls
  r
}

test_that("the TMS description names the release, zoom and 404 rule", {
  x <- wayback_wms_xml("60013", 18L)
  expect_match(x, "MapServer/tile/60013/${z}/${y}/${x}", fixed = TRUE)
  expect_match(x, "<TileLevel>18</TileLevel>", fixed = TRUE)
  expect_match(x, "<ZeroBlockHttpCodes>204,404</ZeroBlockHttpCodes>",
               fixed = TRUE)
  # no tile cache: with one, GDAL reports every 404 tile as a read error
  expect_false(grepl("<Cache>", x, fixed = TRUE))
  expect_match(x, "<BandsCount>3</BandsCount>", fixed = TRUE)
})

test_that("the default resolution is the tiles' ground resolution", {
  pt54 <- sf::st_sfc(sf::st_point(c(-124, 54)), crs = 4326)
  expect_equal(wayback_ground_res(17, pt54), 0.70)
  expect_equal(wayback_ground_res(18, pt54), 0.35)
  pt0 <- sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326)
  expect_equal(wayback_ground_res(17, pt0), 1.20)
})

test_that("a fetch returns RGB, clipped by cell centre, with zeros handled", {
  aoi <- wb_poly(wb_x0 + 10.25, wb_y0 + 10.25, 100)  # no edge on a cell centre
  r <- wb_fetch(aoi, clip = TRUE)
  expect_identical(names(r), c("red", "green", "blue"))
  expect_equal(terra::RGB(r), 1:3)
  v <- terra::values(r)
  inside <- !is.na(terra::values(terra::rasterize(terra::vect(aoi), r[[1]],
                                                  touches = FALSE))[, 1])
  # a cell whose centre is outside is nodata; the edge cells half in are out
  expect_true(all(is.na(v[!inside, ])))
  expect_false(anyNA(v[inside, ]))
  expect_identical(sum(inside), 100L * 100L)
  expect_true(all(v[inside, 2:3] == 100))
})

test_that("a lone zero band becomes 1, not nodata", {
  aoi <- wb_poly(wb_x0, wb_y0 + 150, 50)  # takes in the top row, red = 0
  r <- wb_fetch(aoi)
  top <- terra::values(r)[1, ]
  expect_equal(unname(top), c(1, 100, 100))
})

test_that("pixels zero in every band are empty, and too many abort", {
  aoi <- wb_poly(wb_x0, wb_y0, 200)
  # 20 of 200 columns empty = 10%
  expect_error(wb_fetch(aoi, empty_px = 20L), class = "drift_wayback_empty")
  r <- wb_fetch(aoi, empty_px = 20L, empty_max = 0.2)
  v <- terra::values(r)
  expect_equal(mean(is.na(v[, 1])), 0.1)
  # 5 columns = 2.5%, under the default
  expect_no_error(wb_fetch(aoi, empty_px = 5L))
})

test_that("a flat AOI is not empty", {
  aoi <- wb_poly(wb_x0 + 20, wb_y0 + 20, 50)
  r <- wb_fetch(aoi)
  expect_identical(terra::global(r, "sd", na.rm = TRUE)[, 1], c(0, 0, 0))
})

test_that("clip = FALSE keeps the whole bounding box", {
  # a triangle: its bbox holds cells the triangle does not
  tri <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(wb_x0, wb_y0), c(wb_x0 + 100, wb_y0), c(wb_x0, wb_y0 + 100),
    c(wb_x0, wb_y0)
  ))), crs = 3857))
  r <- wb_fetch(tri, clip = FALSE)
  expect_false(anyNA(terra::values(r)))
  r <- wb_fetch(tri, clip = TRUE)
  expect_true(anyNA(terra::values(r)))
})

test_that("the chip is cached; force and a changed empty_max rebuild it", {
  aoi <- wb_poly(wb_x0 + 10, wb_y0 + 10, 50)
  dir <- withr::local_tempdir()
  a <- wb_fetch(aoi, cache_dir = dir)
  expect_identical(attr(a, "calls"), 1L)
  b <- wb_fetch(aoi, cache_dir = dir)
  expect_identical(attr(b, "calls"), 0L)
  expect_identical(terra::sources(a), terra::sources(b))
  expect_identical(attr(wb_fetch(aoi, cache_dir = dir, force = TRUE), "calls"),
                   1L)
  expect_identical(attr(wb_fetch(aoi, cache_dir = dir, empty_max = 0.5),
                        "calls"), 1L)
  expect_length(list.files(file.path(dir, "v2", "esri-wayback"),
                           pattern = "[.]aux"), 0L)
})

test_that("an AOI that covers no cell centre aborts", {
  aoi <- wb_poly(wb_x0 + 10.1, wb_y0 + 10.1, 0.3)
  expect_error(wb_fetch(aoi), class = "drift_wayback_empty")
})

test_that("any GDAL warning during the warp aborts, and says what it was", {
  aoi <- wb_poly(wb_x0 + 10, wb_y0 + 10, 50)
  testthat::local_mocked_bindings(
    gdal_utils = function(...) {
      warning("GDAL Error 1: HTTP error code : 500")
      TRUE
    },
    .package = "sf"
  )
  expect_error(wb_fetch(aoi), "HTTP error code : 500",
               class = "drift_wayback_http")
})

test_that("a GDAL failure that raises is classed, with GDAL's message", {
  aoi <- wb_poly(wb_x0 + 10, wb_y0 + 10, 50)
  testthat::local_mocked_bindings(
    gdal_utils = function(...) {
      warning("GDAL Error 1: Invalid dataset dimensions")
      stop("gdal_utils warp: an error occured")
    },
    .package = "sf"
  )
  expect_error(wb_fetch(aoi), "Invalid dataset dimensions",
               class = "drift_wayback_http")
})

test_that("inputs are checked", {
  aoi <- wb_poly(wb_x0, wb_y0, 50)
  expect_error(dft_wayback_fetch(wb_point(0, 0), "1", 18), "polygons")
  expect_error(dft_wayback_fetch(aoi, "abc", 18), "release id")
  expect_error(dft_wayback_fetch(aoi, c("1", "2"), 18), "release id")
  expect_error(dft_wayback_fetch(aoi, "1", 17:18), "one whole number")
  expect_error(dft_wayback_fetch(aoi, "1", 23), "10 to 22")
  expect_error(dft_wayback_fetch(aoi, "1", 18, crs = "EPSG:4326"),
               "geographic")
  expect_error(dft_wayback_fetch(aoi, "1", 18, empty_max = 2), "0 to 1")
  expect_error(dft_wayback_fetch(aoi, "1", 18, res = -1), "positive")
})

test_that("live fetch of a Neexdzii Kwa chip", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "set DRIFT_TEST_NETWORK=true to run network tests")
  # a +/-50 m square in a 2016-09-30 WorldView-2 capture served by release
  # 60013 (2024-03-07) at zoom 18 (floodplains#115, NECR point 107)
  aoi <- sf::st_buffer(sf::st_sfc(sf::st_point(c(1112930, 995190)),
                                  crs = 3005), 50, endCapStyle = "SQUARE")
  # in the AOI's own CRS, so the square is not rotated inside its bbox
  r <- dft_wayback_fetch(aoi, "60013", 18, crs = "EPSG:3005",
                         cache_dir = withr::local_tempdir())
  expect_equal(terra::nlyr(r), 3)
  expect_equal(terra::res(r)[1], 0.35)
  expect_lt(mean(is.na(terra::values(r)[, 1])), 0.05)

  # no rural BC imagery at zoom 22: every tile 404s, reads as zeros, and the
  # empty guard refuses it rather than returning a black chip
  expect_error(dft_wayback_fetch(aoi, "60013", 22, crs = "EPSG:3005",
                                 cache_dir = withr::local_tempdir()),
               class = "drift_wayback_empty")
})

test_that("auto_utm_epsg returns correct zone for BC interior", {
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  epsg <- drift:::auto_utm_epsg(aoi)
  expect_equal(epsg, "EPSG:32609")
})

test_that("auto_utm_epsg handles southern hemisphere", {
  pt <- sf::st_sfc(sf::st_point(c(175, -42)), crs = 4326) |> sf::st_sf()
  epsg <- drift:::auto_utm_epsg(pt)
  expect_equal(epsg, "EPSG:32760")
})

test_that("auto_utm_epsg handles prime meridian", {
  pt <- sf::st_sfc(sf::st_point(c(2, 48)), crs = 4326) |> sf::st_sf()
  epsg <- drift:::auto_utm_epsg(pt)
  expect_equal(epsg, "EPSG:32631")
})

test_that("dft_stac_fetch requires gdalcubes", {
  skip_if(requireNamespace("gdalcubes", quietly = TRUE),
          "gdalcubes is installed, can't test missing-package path")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  expect_error(dft_stac_fetch(aoi), "gdalcubes")
})

# helpers for stac_cache_key tests: a unit-square polygon (optionally shifted)
# and a key call with fixed defaults so each test varies one input at a time
square_aoi <- function(dx = 0) {
  sf::st_sfc(
    sf::st_polygon(list(rbind(
      c(0 + dx, 0), c(1 + dx, 0), c(1 + dx, 1), c(0 + dx, 1), c(0 + dx, 0)
    ))),
    crs = 32609
  )
}

cache_key <- function(aoi = square_aoi(), res = 10, target_crs = "EPSG:32609",
                      dt = "P1Y", aggregation = "first", resampling = "near",
                      stac_url = "https://example.com/stac",
                      collection = "test-collection", asset = "data") {
  drift:::stac_cache_key(aoi, res, target_crs, dt, aggregation, resampling,
                         stac_url, collection, asset)
}

test_that("stac_cache_key is deterministic and 12-char hex", {
  k1 <- cache_key(square_aoi())
  k2 <- cache_key(square_aoi())
  expect_equal(k1, k2)
  expect_match(k1, "^[0-9a-f]{12}$")
})

test_that("stac_cache_key changes when the AOI geometry changes", {
  expect_false(cache_key(square_aoi()) == cache_key(square_aoi(dx = 0.5)))
})

test_that("stac_cache_key changes with each fetch-affecting parameter", {
  base <- cache_key()
  expect_false(cache_key(res = 20) == base)
  expect_false(cache_key(target_crs = "EPSG:32610") == base)
  expect_false(cache_key(dt = "P2Y") == base)
  expect_false(cache_key(aggregation = "median") == base)
  expect_false(cache_key(resampling = "bilinear") == base)
  expect_false(cache_key(stac_url = "https://other.com/stac") == base)
  expect_false(cache_key(collection = "other-collection") == base)
  expect_false(cache_key(asset = "other-asset") == base)
})

test_that("stac_cache_key treats integer and double res alike", {
  expect_equal(cache_key(res = 10L), cache_key(res = 10))
})

test_that("stac_cache_key ignores sf attribute columns", {
  bare <- square_aoi()
  with_attrs <- sf::st_sf(name = "a", area = 1.5, geometry = bare)
  expect_equal(cache_key(with_attrs), cache_key(bare))
})

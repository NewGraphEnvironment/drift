test_that("dft_stac_cube requires gdalcubes", {
  skip_if(requireNamespace("gdalcubes", quietly = TRUE),
          "gdalcubes is installed, can't test missing-package path")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  expect_error(dft_stac_cube(aoi), "gdalcubes")
})

test_that("dft_stac_cube rejects categorical sources", {
  skip_if_not_installed("gdalcubes")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  expect_error(dft_stac_cube(aoi, source = "io-lulc"), "not a cube source")
})

# helpers for stac_cube_cache_key tests: a unit-square polygon (optionally
# shifted) and a key call with fixed defaults so each test varies one input
square_aoi <- function(dx = 0) {
  sf::st_sfc(
    sf::st_polygon(list(rbind(
      c(0 + dx, 0), c(1 + dx, 0), c(1 + dx, 1), c(0 + dx, 1), c(0 + dx, 0)
    ))),
    crs = 32609
  )
}

cube_key <- function(aoi = square_aoi(), res = 10, target_crs = "EPSG:32609",
                     dt = "P1M", aggregation = "median", resampling = "bilinear",
                     stac_url = "https://example.com/stac",
                     collection = "sentinel-2-l2a",
                     band_assets = c("B08", "B04"),
                     datetime = "2019-01-01/2023-12-31", index = "kndvi",
                     cloud_cover_max = 60, mask_values = c(3, 8, 9, 10),
                     scale = 1e-4, offset = -0.1) {
  drift:::stac_cube_cache_key(
    aoi, res, target_crs, dt, aggregation, resampling, stac_url, collection,
    band_assets, datetime, index, cloud_cover_max, mask_values, scale, offset
  )
}

test_that("stac_cube_cache_key is deterministic and 12-char hex", {
  expect_equal(cube_key(), cube_key())
  expect_match(cube_key(), "^[0-9a-f]{12}$")
})

test_that("stac_cube_cache_key changes with each cube-affecting parameter", {
  base <- cube_key()
  expect_false(cube_key(aoi = square_aoi(dx = 0.5)) == base)
  expect_false(cube_key(res = 20) == base)
  expect_false(cube_key(target_crs = "EPSG:32610") == base)
  expect_false(cube_key(dt = "P1Y") == base)
  expect_false(cube_key(aggregation = "mean") == base)
  expect_false(cube_key(resampling = "near") == base)
  expect_false(cube_key(collection = "landsat-c2-l2") == base)
  expect_false(cube_key(band_assets = c("B08", "B11")) == base)
  expect_false(cube_key(datetime = "2020-01-01/2020-12-31") == base)
  expect_false(cube_key(index = "ndvi") == base)
  expect_false(cube_key(cloud_cover_max = 20) == base)
  expect_false(cube_key(mask_values = c(8, 9)) == base)
  expect_false(cube_key(scale = 2.75e-5) == base)
  expect_false(cube_key(offset = -0.2) == base)
})

test_that("stac_cube_cache_key normalizes mask_values order and res type", {
  expect_equal(cube_key(mask_values = c(3, 8, 9, 10)),
               cube_key(mask_values = c(10, 9, 8, 3)))
  expect_equal(cube_key(res = 10L), cube_key(res = 10))
})

test_that("stac_cube_cache_key ignores sf attribute columns", {
  bare <- square_aoi()
  with_attrs <- sf::st_sf(name = "a", area = 1.5, geometry = bare)
  expect_equal(cube_key(with_attrs), cube_key(bare))
})

# Network end-to-end against the Planetary Computer. Opt-in only (env var), so
# the default `devtools::test()` stays network-free per the repo convention.
test_that("dft_stac_cube fetches a single-band index cube end-to-end", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "network test — set DRIFT_TEST_NETWORK=true to run")
  skip_if_not_installed("gdalcubes")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  cache <- tempfile("drift_cube_")
  dir.create(cache)
  cube <- dft_stac_cube(aoi, index = "kndvi",
                        datetime = "2021-06-01/2021-08-31", dt = "P1M",
                        cache_dir = cache)
  expect_s3_class(cube, "cube")
  expect_equal(gdalcubes::bands(cube)$name, "kndvi")
  # second call hits the cache (one cube_<key>.nc under the source dir)
  expect_length(list.files(file.path(cache, "sentinel-2-l2a"),
                           pattern = "^cube_.*\\.nc$"), 1)
})

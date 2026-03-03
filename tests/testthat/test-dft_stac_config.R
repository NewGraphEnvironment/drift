test_that("dft_stac_config returns valid config for io-lulc", {
  cfg <- dft_stac_config("io-lulc")
  expect_type(cfg, "list")
  expect_named(cfg, c("stac_url", "collection", "asset", "available_years"))
  expect_equal(cfg$collection, "io-lulc-annual-v02")
  expect_equal(cfg$asset, "data")
  expect_true(2017L %in% cfg$available_years)
  expect_true(2023L %in% cfg$available_years)
  expect_match(cfg$stac_url, "planetarycomputer")
})

test_that("dft_stac_config returns valid config for esa-worldcover", {
  cfg <- dft_stac_config("esa-worldcover")
  expect_type(cfg, "list")
  expect_equal(cfg$collection, "esa-worldcover")
  expect_equal(cfg$asset, "map")
  expect_equal(cfg$available_years, c(2020L, 2021L))
})

test_that("dft_stac_config errors on unknown source", {
  expect_error(dft_stac_config("bogus"))
})

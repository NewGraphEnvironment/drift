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

test_that("categorical sources carry no cube marker (absence = FALSE)", {
  # backward-compat: the flat 4-field shape is pinned by expect_named above;
  # consumers branch on isTRUE(cfg$cube), which must be FALSE here
  expect_false(isTRUE(dft_stac_config("io-lulc")$cube))
  expect_false(isTRUE(dft_stac_config("esa-worldcover")$cube))
})

test_that("dft_stac_config returns role-based cube config for sentinel-2-l2a", {
  cfg <- dft_stac_config("sentinel-2-l2a")
  expect_type(cfg, "list")
  expect_true(isTRUE(cfg$cube))
  expect_equal(cfg$collection, "sentinel-2-l2a")
  expect_match(cfg$stac_url, "planetarycomputer")

  # role -> asset map uses Planetary Computer band names (B04/B08/B11/SCL)
  expect_named(cfg$roles, c("red", "nir", "swir16", "mask"))
  expect_equal(cfg$roles$red, "B04")
  expect_equal(cfg$roles$nir, "B08")
  expect_equal(cfg$roles$swir16, "B11")
  expect_equal(cfg$roles$mask, "SCL")

  # mask values (incl. 11 snow/ice), reflectance affine transform, temporal extent
  expect_equal(cfg$mask_values, c(3L, 8L, 9L, 10L, 11L))
  expect_equal(cfg$scale, 1e-4)
  expect_equal(cfg$offset, -0.1)
  expect_match(cfg$available_datetime, "^\\d{4}-\\d{2}-\\d{2}/\\d{4}-\\d{2}-\\d{2}$")
})

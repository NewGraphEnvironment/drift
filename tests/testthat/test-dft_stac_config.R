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
  expect_named(cfg$roles, c("red", "green", "blue", "nir", "swir16", "mask"))
  expect_equal(cfg$roles$red, "B04")
  expect_equal(cfg$roles$green, "B03")
  expect_equal(cfg$roles$blue, "B02")
  expect_equal(cfg$roles$nir, "B08")
  expect_equal(cfg$roles$swir16, "B11")
  expect_equal(cfg$roles$mask, "SCL")

  # mask values (incl. 11 snow/ice), reflectance affine transform, temporal extent
  expect_equal(cfg$mask_values, c(3L, 8L, 9L, 10L, 11L))
  expect_equal(cfg$scale, 1e-4)
  expect_equal(cfg$offset, -0.1)
  expect_match(cfg$available_datetime, "^\\d{4}-\\d{2}-\\d{2}/\\d{4}-\\d{2}-\\d{2}$")

  # baseline offset boundary: +1000 DN only from 2022-01-25, so pre-boundary
  # scenes carry offset 0 and the fetch splits at the boundary
  expect_equal(cfg$offset_boundary, "2022-01-25")
  expect_equal(cfg$offset_before, 0)
})

test_that("dft_stac_config returns a cube config for modis-13Q1-061 (#115)", {
  cfg <- dft_stac_config("modis-13Q1-061")
  expect_true(isTRUE(cfg$cube))
  expect_equal(cfg$collection, "modis-13Q1-061")
  expect_match(cfg$stac_url, "planetarycomputer")
  expect_named(cfg$roles, c("red", "nir", "blue", "mask"))
  expect_equal(cfg$roles$red, "250m_16_days_red_reflectance")
  expect_equal(cfg$roles$nir, "250m_16_days_NIR_reflectance")
  expect_equal(cfg$roles$blue, "250m_16_days_blue_reflectance")
  expect_equal(cfg$roles$mask, "250m_16_days_pixel_reliability")
  # The MIR band is 2105-2155 nm (swir22), so no swir16; MOD13Q1 has no green
  expect_null(cfg$roles$swir16)
  expect_null(cfg$roles$green)
  # 2 snow/ice, 3 cloudy; 255 is the band's on-disk NoData (STAC says int8, the
  # COG is Byte), so a fill pixel is masked whatever gdalcubes makes of NoData
  expect_equal(cfg$mask_values, c(2L, 3L, 255L))
  expect_equal(cfg$scale, 1e-4)
  expect_equal(cfg$offset, 0)
  expect_null(cfg$offset_boundary)
  expect_equal(cfg$res, 250)
  expect_false(cfg$cloud_cover)
  expect_match(cfg$available_datetime, "^2000-02-18/\\d{4}-\\d{2}-\\d{2}$")
})

test_that("sentinel-2-l2a is marked as carrying eo:cloud_cover (#115)", {
  cfg <- dft_stac_config("sentinel-2-l2a")
  expect_false(identical(cfg$cloud_cover, FALSE))
  expect_null(cfg$res)
})

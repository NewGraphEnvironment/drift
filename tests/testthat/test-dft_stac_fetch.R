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

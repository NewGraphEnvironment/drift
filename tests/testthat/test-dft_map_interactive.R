# -- Helpers -------------------------------------------------------------------

load_classified_list <- function() {
  files <- c("2017" = "example_2017.tif", "2020" = "example_2020.tif",
             "2023" = "example_2023.tif")
  rasters <- lapply(files, function(f) {
    terra::rast(system.file("extdata", f, package = "drift"))
  })
  dft_rast_classify(rasters, source = "io-lulc")
}

load_aoi <- function() {
  sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
}

# Extract method names from leaflet call list
map_methods <- function(map) {
  vapply(map$x$calls, function(c) c$method, character(1))
}

# -- Local mode ---------------------------------------------------------------

test_that("returns leaflet htmlwidget for named list input", {
  classified <- load_classified_list()
  map <- dft_map_interactive(classified)
  expect_s3_class(map, "leaflet")
  expect_s3_class(map, "htmlwidget")
})

test_that("works with single SpatRaster (auto-wraps)", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(r, source = "io-lulc")
  map <- dft_map_interactive(classified)
  expect_s3_class(map, "leaflet")
})

test_that("works with AOI polygon", {
  classified <- load_classified_list()
  aoi <- load_aoi()
  map <- dft_map_interactive(classified, aoi = aoi)
  expect_s3_class(map, "leaflet")
  # AOI adds a polygon layer
  expect_true("addPolygons" %in% map_methods(map))
})

test_that("works without AOI", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(r, source = "io-lulc")
  map <- dft_map_interactive(classified, aoi = NULL)
  expect_false("addPolygons" %in% map_methods(map))
})

test_that("legend contains expected class names", {
  classified <- load_classified_list()
  map <- dft_map_interactive(classified)

  # Find the addLegend call
  legend_idx <- which(map_methods(map) == "addLegend")
  expect_length(legend_idx, 1)

  legend_args <- map$x$calls[[legend_idx]]$args
  # labels should include classes present in the data
  expect_true("Trees" %in% legend_args[[1]]$labels)
  expect_true("Water" %in% legend_args[[1]]$labels)
})

test_that("legend suppressed when legend_position is NULL", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(r, source = "io-lulc")
  map <- dft_map_interactive(classified, legend_position = NULL)
  expect_false("addLegend" %in% map_methods(map))
})

test_that("layer control includes all overlay groups", {
  classified <- load_classified_list()
  aoi <- load_aoi()
  map <- dft_map_interactive(classified, aoi = aoi)

  ctrl_idx <- which(map_methods(map) == "addLayersControl")
  expect_length(ctrl_idx, 1)
  ctrl_args <- map$x$calls[[ctrl_idx]]$args
  overlay <- ctrl_args[[2]]
  expect_true(all(c("2017", "2020", "2023", "AOI") %in% overlay))
})

test_that("first layer is visible, others hidden", {
  classified <- load_classified_list()
  map <- dft_map_interactive(classified)

  hide_idx <- which(map_methods(map) == "hideGroup")
  # Should hide 2020 and 2023 but not 2017
  hidden <- unlist(lapply(hide_idx, function(i) map$x$calls[[i]]$args))
  expect_true("2020" %in% hidden)
  expect_true("2023" %in% hidden)
  expect_false("2017" %in% hidden)
})

test_that("fullscreen control is added", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(r, source = "io-lulc")
  map <- dft_map_interactive(classified)
  # fullscreen adds an htmlwidget dependency, not a method call
  dep_names <- vapply(map$dependencies, function(d) d$name, character(1))
  expect_true(any(grepl("fullscreen", dep_names, ignore.case = TRUE)))
})

test_that("custom basemaps are respected", {
  r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(r, source = "io-lulc")
  map <- dft_map_interactive(classified,
                             basemaps = c("Topo" = "OpenTopoMap"))

  ctrl_idx <- which(map_methods(map) == "addLayersControl")
  base_groups <- map$x$calls[[ctrl_idx]]$args[[1]]
  expect_equal(base_groups, "Topo")
})

# -- COG mode -----------------------------------------------------------------

test_that("build_titiler_url returns correctly formatted URL", {
  ct <- dft_class_table("io-lulc")
  url <- drift:::build_titiler_url(
    "https://titiler.example.com",
    "https://bucket.s3.amazonaws.com/test.tif",
    ct
  )
  expect_type(url, "character")
  expect_match(url, "^https://titiler\\.example\\.com/cog/tiles/WebMercatorQuad/")
  expect_match(url, "\\{z\\}/\\{x\\}/\\{y\\}\\.png")
  expect_match(url, "bidx=1")
  expect_match(url, "colormap=")
  # COG URL should be encoded

  expect_match(url, "url=https")
})

test_that("build_titiler_url colormap contains RGBA arrays", {
  ct <- dft_class_table("io-lulc")
  url <- drift:::build_titiler_url("https://t.example.com", "https://x.tif", ct)
  # Decode the colormap param to check structure
  colormap_encoded <- sub(".*colormap=(.*)$", "\\1", url)
  colormap_json <- utils::URLdecode(colormap_encoded)
  # Should contain RGBA arrays like [65,155,223,255]
  expect_match(colormap_json, "\\[\\d+,\\d+,\\d+,255\\]")
})

test_that("COG mode errors without titiler_url", {
  cogs <- c("2020" = "https://bucket.s3.amazonaws.com/test.tif")
  expect_error(
    dft_map_interactive(cogs, titiler_url = NULL),
    "titiler URL"
  )
})

test_that("COG mode builds map when titiler_url provided", {
  cogs <- c("2017" = "https://bucket.s3.amazonaws.com/a.tif",
            "2023" = "https://bucket.s3.amazonaws.com/b.tif")
  map <- dft_map_interactive(cogs, source = "io-lulc",
                             titiler_url = "https://titiler.example.com")
  expect_s3_class(map, "leaflet")
  # Should use addTiles not addRasterImage
  expect_true("addTiles" %in% map_methods(map))
  expect_false("addRasterImage" %in% map_methods(map))
})

test_that("COG mode auto-wraps single unnamed URL", {
  map <- dft_map_interactive("https://bucket.s3.amazonaws.com/a.tif",
                             source = "io-lulc",
                             titiler_url = "https://titiler.example.com")
  expect_s3_class(map, "leaflet")
})

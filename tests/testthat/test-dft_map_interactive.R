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

# -- RGB imagery (#79) ---------------------------------------------------------

# A synthetic three-band "composite" on the packaged grid, in reflectance
make_rgb <- function(red = 0.1, green = 0.05, blue = 0.02) {
  tmpl <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  tmpl <- terra::aggregate(tmpl, 10)
  r <- c(terra::init(tmpl, red), terra::init(tmpl, green), terra::init(tmpl, blue))
  names(r) <- c("red", "green", "blue")
  r
}

test_that("rgb layers become overlay groups beneath the classified layers", {
  classified <- load_classified_list()
  rgb <- list("2017 Jun-Jul" = make_rgb(), "2023 Aug-Sep" = make_rgb(0.2))
  map <- dft_map_interactive(classified, rgb = rgb)
  ctrl <- map$x$calls[[which(map_methods(map) == "addLayersControl")]]$args[[2]]
  expect_equal(ctrl[1:2], names(rgb))
  # drawn first, so beneath: every rgb image call precedes the first classified one
  img <- which(map_methods(map) == "addRasterImage")
  groups <- vapply(map$x$calls[img], function(c) c$args[[4]], character(1))
  expect_equal(groups[1:2], names(rgb))
  # imagery starts hidden under classified layers
  hidden <- unlist(lapply(which(map_methods(map) == "hideGroup"),
                          function(i) map$x$calls[[i]]$args))
  expect_true(all(names(rgb) %in% hidden))
})

test_that("an imagery-only map works with x = NULL and has no land-cover legend", {
  rgb <- list("2017 Jun-Jul" = make_rgb(), "2023 Aug-Sep" = make_rgb(0.2))
  map <- dft_map_interactive(rgb = rgb, aoi = load_aoi())
  expect_s3_class(map, "leaflet")
  expect_false("addLegend" %in% map_methods(map))
  hidden <- unlist(lapply(which(map_methods(map) == "hideGroup"),
                          function(i) map$x$calls[[i]]$args))
  expect_false("2017 Jun-Jul" %in% hidden)
  expect_true("2023 Aug-Sep" %in% hidden)
  expect_error(dft_map_interactive(), "Supply")
})

test_that("band 1 draws as red: channel order is r, g, b = 1, 2, 3", {
  # leafem defaults to r = 3, b = 1, which would paint this pure blue
  rgb <- list(a = make_rgb(red = 0.3, green = 0, blue = 0),
              b = make_rgb(red = 0, green = 0, blue = 0))
  cols <- NULL
  testthat::local_mocked_bindings(
    addRasterImage = function(map, x, colors, ...) {
      cols <<- c(cols, list(colors(1)))
      map
    },
    .package = "leafem"   # leafem calls addRasterImage through its own imports
  )
  dft_map_interactive(rgb = rgb)
  # reprojection to 3857 leaves NA corners, drawn transparent; every data pixel
  # of the all-red composite must be pure red
  drawn <- unique(toupper(cols[[1]][cols[[1]] != "#00000000"]))
  expect_equal(drawn, "#FF0000FF")   # rgb(alpha = 1) carries the alpha byte
})

test_that("one stretch serves every composite, so a darker year stays darker", {
  # Per-image stretching would render both as the same full-range colour.
  dom <- drift:::rgb_domain(list(make_rgb(0.1, 0.1, 0.1), make_rgb(0.3, 0.3, 0.3)))
  expect_equal(dim(dom), c(2L, 3L))
  dark <- drift:::rgb_stretch(make_rgb(0.1, 0.1, 0.1), dom)
  bright <- drift:::rgb_stretch(make_rgb(0.3, 0.3, 0.3), dom)
  expect_lt(terra::global(dark, "max")[1, 1], terra::global(bright, "min")[1, 1])
  # per band: a band scaled 10x (NIR in false colour) does not flatten the others
  dom2 <- drift:::rgb_domain(list(make_rgb(0.5, 0.05, 0.02), make_rgb(0.4, 0.04, 0.01)))
  s <- drift:::rgb_stretch(make_rgb(0.4, 0.04, 0.01), dom2)
  expect_equal(unname(unlist(terra::global(s, "max"))), c(0, 0, 0))
  s <- drift:::rgb_stretch(make_rgb(0.5, 0.05, 0.02), dom2)
  expect_equal(unname(unlist(terra::global(s, "max"))), c(1, 1, 1))
})

test_that("rgb input is validated by name and band count", {
  classified <- load_classified_list()
  two_band <- make_rgb()[[1:2]]
  expect_error(dft_map_interactive(rgb = list(a = two_band)), "three bands.*a")
  expect_error(dft_map_interactive(rgb = list(make_rgb())), "named")
  expect_error(dft_map_interactive(classified, rgb = list("2017" = make_rgb())),
               "share layer name")
  expect_error(dft_map_interactive(rgb = list(a = make_rgb()), rgb_rescale = c(1, 0)),
               "two increasing")
  expect_error(dft_map_interactive(rgb = "https://x/y.tif", titiler_url = NULL),
               "titiler URL")
})

test_that("COG rgb layers get a three-band titiler URL with the shared rescale", {
  url <- drift:::build_titiler_rgb_url("https://ti.example", "https://b/c 1.tif",
                                       c(0, 0.3))
  expect_match(url, "&bidx=1&bidx=2&bidx=3", fixed = TRUE)
  expect_equal(lengths(regmatches(url, gregexpr("&rescale=0%2C0.3", url, fixed = TRUE))), 3L)
  expect_match(url, "url=https%3A%2F%2Fb%2Fc%201.tif", fixed = TRUE)
  map <- dft_map_interactive(rgb = c("2017 Jun-Jul" = "https://b/c.tif"),
                             titiler_url = "https://ti.example")
  tiles <- map$x$calls[map_methods(map) == "addTiles"]
  tmpl <- vapply(tiles, function(c) c$args[[1]], character(1))
  expect_true(any(grepl("bidx=3", tmpl, fixed = TRUE)))
})

test_that("classified layers are handed to leaflet in EPSG:3857", {
  # project = FALSE means leaflet assumes Web Mercator pixels; a 4326 grid would
  # be misregistered against the RGB imagery beneath it.
  crs_seen <- character(0)
  testthat::local_mocked_bindings(
    addRasterImage = function(map, x, ...) {
      crs_seen <<- c(crs_seen, terra::crs(x, describe = TRUE)$code)
      map
    },
    .package = "leaflet"
  )
  dft_map_interactive(load_classified_list())
  expect_true(length(crs_seen) > 0)
  expect_true(all(crs_seen == "3857"))
})

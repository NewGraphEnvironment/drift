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
                      collection = "test-collection", asset = "data",
                      tile_size = NULL) {
  # mirror production: dft_stac_fetch() snaps tile_size once (tile_size_check)
  # before it reaches both the tile grid and the cache key
  ts <- if (is.null(tile_size)) NULL else
    suppressMessages(drift:::tile_size_check(tile_size, res))
  drift:::stac_cache_key(aoi, res, target_crs, dt, aggregation, resampling,
                         stac_url, collection, asset, tile_size = ts)
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

test_that("stac_cache_key(tile_size = NULL) reproduces the legacy pre-tiling hash", {
  # Frozen guardian of legacy-cache preservation (#36): adding tile_size must
  # NOT change the key for an untiled fetch, or every cached io-lulc fetch
  # silently re-downloads on upgrade. If this literal must change, that is a
  # deliberate cache-format break — flag it, don't just re-freeze.
  expect_equal(cache_key(), "79f67b7b9dae")
})

test_that("stac_cache_key keys a tiled fetch distinctly from an untiled one", {
  base <- cache_key()
  expect_false(cache_key(tile_size = 500) == base)
  expect_false(cache_key(tile_size = 1000) == base)
  expect_false(cache_key(tile_size = 500) == cache_key(tile_size = 1000))
})

test_that("stac_cache_key snaps tile_size before hashing (aligned sizes key alike)", {
  # 504 and 500 both snap to 500 (res 10), so they must hit the same cache
  expect_equal(cache_key(tile_size = 504), cache_key(tile_size = 500))
})

test_that("stac_cache_key ignores sf attribute columns", {
  bare <- square_aoi()
  with_attrs <- sf::st_sf(name = "a", area = 1.5, geometry = bare)
  expect_equal(cache_key(with_attrs), cache_key(bare))
})

# --- tile_size_check(): validate + snap tile_size to a multiple of res -------
# Offline; the download-tiling normalization (#36). NULL is handled by the
# caller (it gates the whole tiled path); this helper only sees non-NULL input.
test_that("tile_size_check aborts on non-positive / non-finite / non-scalar input", {
  expect_error(drift:::tile_size_check(NA, 10), "positive")
  expect_error(drift:::tile_size_check(0, 10), "positive")
  expect_error(drift:::tile_size_check(-5, 10), "positive")
  expect_error(drift:::tile_size_check(Inf, 10), "positive")
  expect_error(drift:::tile_size_check(c(1, 2), 10), "positive")
  expect_error(drift:::tile_size_check("500", 10), "positive")
})

test_that("tile_size_check aborts when the snapped size is smaller than res", {
  # 4 snaps to round(4/10)*10 = 0, which is < res
  expect_error(drift:::tile_size_check(4, 10), "res")
})

test_that("tile_size_check snaps to the nearest multiple of res and returns it", {
  expect_equal(drift:::tile_size_check(500, 10), 500)   # already aligned
  expect_equal(drift:::tile_size_check(504, 10), 500)   # rounds down
  expect_equal(drift:::tile_size_check(506, 10), 510)   # rounds up
  expect_message(drift:::tile_size_check(504, 10), "snap")
})

# --- tile_grid(): res-aligned tiles intersecting the AOI (offline) -----------
# A rectangular AOI filling a bbox (all tiles kept) and a thin diagonal corridor
# (most bbox tiles dropped — the download-saving mechanism, tested without network).
rect_aoi <- function(xmin = 0, ymin = 0, xmax = 1000, ymax = 1000, crs = 32609) {
  sf::st_sfc(
    sf::st_polygon(list(rbind(
      c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)
    ))),
    crs = crs
  )
}

test_that("tile_grid returns res-aligned tiles anchored at (xmin, ymin)", {
  aoi <- rect_aoi(0, 0, 1000, 1000)                 # 2x2 tiles at tile_size 500
  tiles <- drift:::tile_grid(aoi, tile_size = 500, res = 10)
  expect_length(tiles, 4)
  lefts   <- vapply(tiles, `[[`, numeric(1), "left")
  bottoms <- vapply(tiles, `[[`, numeric(1), "bottom")
  widths  <- vapply(tiles, function(t) t$right - t$left, numeric(1))
  heights <- vapply(tiles, function(t) t$top - t$bottom, numeric(1))
  # anchored at (0, 0): every left/bottom is a multiple of tile_size from origin
  expect_setequal(lefts, c(0, 500))
  expect_setequal(bottoms, c(0, 500))
  # every tile is tile_size (a multiple of res) wide and tall
  expect_true(all(widths == 500))
  expect_true(all(heights == 500))
  # each edge lands on the res-lattice anchored at the bbox lower-left
  expect_true(all(lefts %% 10 == 0))
  expect_true(all(bottoms %% 10 == 0))
})

test_that("tile_grid drops bbox tiles that miss the AOI (diagonal corridor)", {
  line <- sf::st_sfc(sf::st_linestring(rbind(c(0, 0), c(1000, 1000))), crs = 32609)
  aoi  <- sf::st_buffer(line, 20)                   # thin diagonal corridor
  tiles <- drift:::tile_grid(aoi, tile_size = 500, res = 10)
  # full grid over the buffered bbox is 3x3 = 9; the diagonal keeps a strict subset
  expect_gt(length(tiles), 0)
  expect_lt(length(tiles), 9)
})

test_that("tile_grid yields a single tile when tile_size covers the bbox", {
  tiles <- drift:::tile_grid(rect_aoi(0, 0, 400, 400), tile_size = 500, res = 10)
  expect_length(tiles, 1)
  expect_equal(tiles[[1]]$left, 0)
  expect_equal(tiles[[1]]$bottom, 0)
})

test_that("tile_grid errors on a degenerate (empty) AOI", {
  expect_error(
    drift:::tile_grid(sf::st_sfc(sf::st_polygon(), crs = 32609),
                      tile_size = 500, res = 10)
  )
})

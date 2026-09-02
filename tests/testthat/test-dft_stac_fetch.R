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

test_that("stac_cache_key(tile_size = NULL) is frozen against accidental drift", {
  # Frozen guardian of cache stability (#36): a key change silently re-downloads
  # every cached io-lulc fetch on upgrade. If this literal must change, that is
  # a deliberate cache-format break — flag it, don't just re-freeze.
  #
  # MOVED ONCE, DELIBERATELY, in #51: was "79f67b7b9dae" up to v0.9.0. The
  # paging fix changes no key parameter, so without a break a raster built from
  # a TRUNCATED item set would keep being served from cache forever under
  # `force = FALSE` — the wide-AOI users the bug hit hardest would get no fix.
  # The salt in stac_cache_key() is what moved it. Cost is a one-time re-fetch
  # of small annual rasters.
  expect_equal(cache_key(), "2264b5dbef6e")
})

test_that("the #51 cache-format break actually changed the key", {
  # Pins the break itself rather than just its new value: if someone removes the
  # salt, this fails naming the reason instead of silently restoring a key that
  # serves truncated rasters.
  expect_false(cache_key() == "79f67b7b9dae")
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

# --- mosaic_tiles(): reassemble per-tile rasters into one cache raster --------
# Offline oracle for the tiled fetch (#36): res-aligned tiles that partition a
# reference grid must merge back into that grid, byte-for-byte.
test_that("mosaic_tiles merges res-aligned tiles back into the reference raster", {
  ref <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 200,
                     ymin = 0, ymax = 200, crs = "EPSG:32609")
  terra::values(ref) <- seq_len(terra::ncell(ref))     # distinct code per cell
  quads <- list(c(0, 100, 0, 100), c(100, 200, 0, 100),
                c(0, 100, 100, 200), c(100, 200, 100, 200))
  tile_files <- vapply(quads, function(e) {
    f <- tempfile(fileext = ".tif")
    terra::writeRaster(terra::crop(ref, terra::ext(e[1], e[2], e[3], e[4])), f)
    f
  }, character(1))
  out <- tempfile(fileext = ".tif")

  drift:::mosaic_tiles(tile_files, out)
  merged <- terra::rast(out)

  expect_equal(terra::nlyr(merged), 1L)
  expect_equal(
    c(terra::xmin(merged), terra::xmax(merged),
      terra::ymin(merged), terra::ymax(merged)),
    c(terra::xmin(ref), terra::xmax(ref), terra::ymin(ref), terra::ymax(ref))
  )
  expect_equal(terra::values(merged), terra::values(ref))   # exact reassembly
  unlink(c(tile_files, out))
})

test_that("mosaic_tiles handles a single tile", {
  ref <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 50,
                     ymin = 0, ymax = 50, crs = "EPSG:32609")
  terra::values(ref) <- seq_len(25)
  f <- tempfile(fileext = ".tif")
  terra::writeRaster(ref, f)
  out <- tempfile(fileext = ".tif")

  drift:::mosaic_tiles(f, out)

  expect_equal(terra::values(terra::rast(out)), terra::values(ref))
  unlink(c(f, out))
})

# --- stac_items_paged(): page to exhaustion, then sign (#51) -----------------
# Offline. `rstac::stac()` / `stac_search()` are pure query constructors with no
# network call, so only `get_request` / `items_fetch` / `items_sign` are mocked.
#
# Every mock here PASSES THROUGH AND AUGMENTS its input rather than returning a
# fixed object. That is load-bearing: a mock that ignores its input cannot
# distinguish page-then-sign from sign-then-page, so both orders would pass and
# the test could not fail.

# a doc_items shaped like a real PC page-1 response, including the `next` link
# that survives a successful items_fetch() (measured; see findings.md)
fake_items <- function(ids = "a", next_link = TRUE, ...) {
  links <- list(list(rel = "self", href = "https://example.com/self"),
                list(rel = "root", href = "https://example.com/"))
  if (next_link) links <- c(links, list(list(rel = "next", href = "https://example.com/p2")))
  structure(
    c(list(type = "FeatureCollection",
           links = links,
           features = lapply(ids, function(i) list(id = i, assets = list()))),
      list(...)),
    class = c("doc_items", "rstac_doc", "list")
  )
}

paged <- function(sign_fn = function(items) items, limit = 500) {
  drift:::stac_items_paged(
    stac_url = "https://example.com/stac", collection = "test-collection",
    bbox = c(0, 0, 1, 1), datetime = "2020-01-01/2020-12-31",
    sign_fn = sign_fn, limit = limit
  )
}

test_that("stac_items_paged signs AFTER paging, so page-2 items are signed too", {
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items("a"),
    # append a page-2 feature, as real paging does
    items_fetch = function(items, ...) {
      items$features <- c(items$features, list(list(id = "b", assets = list())))
      items
    },
    # mark whatever it is handed — so an unsigned page 2 is visible
    items_sign = function(items, ...) {
      items$features <- lapply(items$features, function(f) { f$signed <- TRUE; f })
      items
    },
    .package = "rstac"
  )
  out <- paged()
  expect_equal(length(out$features), 2L)
  # under sign-then-page, feature "b" is appended after signing and is unsigned
  expect_true(all(vapply(out$features, function(f) isTRUE(f$signed), logical(1))))
})

test_that("stac_items_paged strips the stale `next` link before returning", {
  # rstac's items_fetch() mutates only $features and never $links, so a fully
  # paged collection still carries page 1's `next`. Left attached, a caller
  # calling items_fetch() on it re-fetches pages 2..N into an already-complete
  # feature list — silent duplicates in user code.
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items("a"),
    items_fetch = function(items, ...) items,      # keeps the stale next link
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  out <- paged()
  rels <- vapply(out$links, function(l) l$rel, character(1))
  expect_false("next" %in% rels)
  expect_setequal(rels, c("self", "root"))         # nothing else was dropped
})

test_that("stac_items_paged aborts on duplicate item ids", {
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items("a"),
    items_fetch = function(items, ...) {
      items$features <- c(items$features, list(list(id = "a", assets = list())))
      items
    },
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  expect_error(paged(), "duplicate")
})

test_that("stac_items_paged aborts when items_matched disagrees with the item count", {
  # The conditional completeness guard. Fixtured deliberately: Planetary
  # Computer returns no `numberMatched`, so this guard NEVER executes against
  # PC and would otherwise be dead code.
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items(c("a", "b", "c"), numberMatched = 99L),
    items_fetch = function(items, ...) items,
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  expect_error(paged(), "99")
})

test_that("stac_items_paged does not abort when items_matched is absent (the PC case)", {
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items(c("a", "b", "c")),  # no numberMatched
    items_fetch = function(items, ...) items,
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  expect_equal(length(paged()$features), 3L)
})

test_that("stac_items_paged survives a zero-length items_matched", {
  # `&&` on a zero-length value is an error in R >= 4.2, so an is.null()-only
  # guard would abort the fetch it exists to protect. numeric(0) is reachable:
  # items_matched() reads a caller-supplied field name off the document.
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items(c("a", "b")),
    items_fetch = function(items, ...) items,
    items_sign = function(items, ...) items,
    items_matched = function(...) numeric(0),
    .package = "rstac"
  )
  expect_equal(length(paged()$features), 2L)
})

test_that("stac_items_paged passes limit through to the STAC query", {
  seen <- NULL
  testthat::local_mocked_bindings(
    get_request = function(q, ...) { seen <<- q; fake_items("a") },
    items_fetch = function(items, ...) items,
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  paged(limit = 7)
  expect_equal(seen$params$limit, 7)
})

test_that("dft_stac_fetch routes its STAC query through stac_items_paged", {
  # The helper's own unit tests all pass with the old inline pipeline still in
  # dft_stac_fetch(), so this is the only offline proof of the wiring.
  #
  # The assertion must depend on the helper HAVING BEEN CALLED. A first draft
  # asserted only that a stubbed stac_image_collection() was reached, which the
  # inline pipeline satisfies just as well — it measured 0 failures against the
  # restored defect, i.e. it was a test that could not fail. Instead: the stub
  # reports the item ids it received, and rstac::get_request() is booby-trapped,
  # so bypassing the helper produces a different error offline.
  skip_if_not_installed("gdalcubes")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  testthat::local_mocked_bindings(
    stac_items_paged = function(...) fake_items(c("sentinel-x", "sentinel-y"),
                                                next_link = FALSE)
  )
  testthat::local_mocked_bindings(
    # only reachable if dft_stac_fetch() queries STAC itself instead of via the helper
    get_request = function(...) stop("bypassed the helper and queried STAC directly"),
    .package = "rstac"
  )
  testthat::local_mocked_bindings(
    stac_image_collection = function(features, ...) {
      stop("collection built from: ",
           paste(vapply(features, function(f) f$id, character(1)), collapse = ","))
    },
    .package = "gdalcubes"
  )
  expect_error(
    suppressMessages(dft_stac_fetch(aoi, source = "io-lulc", years = 2020,
                                    cache_dir = tempfile("drift_wire_"))),
    "collection built from: sentinel-x,sentinel-y"
  )
})

# Network end-to-end against the Planetary Computer. Opt-in only (env var), so
# the default `devtools::test()` stays network-free per the repo convention.
test_that("dft_stac_fetch tiled result matches untiled over the AOI", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "network test — set DRIFT_TEST_NETWORK=true to run")
  skip_if_not_installed("gdalcubes")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  cache <- tempfile("drift_fetch_")
  dir.create(cache)

  untiled_list <- dft_stac_fetch(aoi, source = "io-lulc", years = 2020,
                                 cache_dir = cache)
  untiled <- untiled_list[["2020"]]

  # attr(, "cache_key") (#51) — pinned to its DEFINITION, not merely non-NULL,
  # by recomputing it from the same resolved inputs dft_stac_fetch() used. The
  # key is per call, not per year: the cached file is <year>_<key>.
  cfg <- dft_stac_config("io-lulc")
  expect_equal(
    attr(untiled_list, "cache_key"),
    drift:::stac_cache_key(
      sf::st_transform(aoi, as.integer(gsub("EPSG:", "", drift:::auto_utm_epsg(aoi)))),
      10, drift:::auto_utm_epsg(aoi), "P1Y", "first", "near",
      cfg$stac_url, cfg$collection, cfg$asset, tile_size = NULL
    )
  )
  expect_length(list.files(file.path(cache, "io-lulc"),
                           pattern = paste0("^2020_", attr(untiled_list, "cache_key"),
                                            "\\.nc$")), 1)
  # small tile_size relative to the AOI bbox → several tiles, most bbox-only
  # tiles dropped (the download-saving mechanism)
  tiled_list <- dft_stac_fetch(aoi, source = "io-lulc", years = 2020,
                               tile_size = 500, cache_dir = cache)
  tiled <- tiled_list[["2020"]]

  expect_false(is.null(attr(tiled_list, "stac_items")))
  expect_s4_class(tiled, "SpatRaster")
  expect_equal(terra::nlyr(tiled), 1L)
  # extension routing: untiled caches a gdalcubes .nc, tiled a terra .tif
  expect_length(list.files(file.path(cache, "io-lulc"),
                           pattern = "^2020_.*\\.nc$"), 1)
  expect_length(list.files(file.path(cache, "io-lulc"),
                           pattern = "^2020_.*\\.tif$"), 1)
  # tiled == untiled over their common in-AOI cells: tiling changes only which
  # bbox pixels are streamed, not the classification. Put the tiled mosaic onto
  # the untiled grid (nearest — a no-op where the lattices coincide, robust to
  # any sub-pixel offset gdalcubes gives the non-divisible untiled bbox) and
  # compare where both are non-NA (the in-AOI overlap).
  a <- terra::values(terra::resample(tiled, untiled, method = "near"))
  b <- terra::values(untiled)
  both <- !is.na(a) & !is.na(b)
  expect_gt(sum(both), 0)
  expect_equal(a[both], b[both])
})

test_that("stac_items_paged pages to exhaustion at a tiny page size (network)", {
  # The two-answer test for #51. The packaged AOI returns 14 items in one page
  # at PC's default, so at the default page size this path CANNOT reach the
  # bug — only a deliberately tiny `limit` exercises paging at all.
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "network test — set DRIFT_TEST_NETWORK=true to run")
  cfg <- dft_stac_config("io-lulc")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  bbox <- as.numeric(sf::st_bbox(sf::st_transform(aoi, 4326)))
  dt <- "2017-01-01/2023-12-31"
  ids <- function(x) vapply(x$features, function(f) f$id, character(1))

  big   <- drift:::stac_items_paged(cfg$stac_url, cfg$collection, bbox, dt,
                                    rstac::sign_planetary_computer(), limit = 500)
  small <- drift:::stac_items_paged(cfg$stac_url, cfg$collection, bbox, dt,
                                    rstac::sign_planetary_computer(), limit = 1)

  # The defect's own answer, built inline rather than via a production switch
  # whose only caller would be this test: one page, unpaged.
  truncated <- rstac::stac(cfg$stac_url) |>
    rstac::stac_search(collections = cfg$collection, bbox = bbox,
                       datetime = dt, limit = 1) |>
    rstac::get_request()

  # the two answers must differ, or the test cannot fail
  expect_lt(length(truncated$features), length(big$features))
  # identical ORDERED ids, not merely equal counts: item order is output-visible
  # under aggregation = "first" where items share a datetime and overlap
  expect_identical(ids(small), ids(big))
  expect_equal(anyDuplicated(ids(big)), 0L)

  # the stale `next` link is stripped even though paging occurred
  expect_false("next" %in% vapply(small$links, function(l) l$rel, character(1)))

  # signing survives paging: an item from beyond page 1 carries a SAS token.
  # This is the arm that breaks if signing precedes paging.
  expect_gt(length(small$features), 1L)
  last_href <- small$features[[length(small$features)]]$assets[[cfg$asset]]$href
  expect_match(last_href, "\\?")
})

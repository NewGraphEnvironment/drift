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
  expect_match(k1, "^[0-9a-f]{16}$")
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
  # MOVED TWICE, both times deliberately:
  #   #51  "79f67b7b9dae" -> "2264b5dbef6e"  (the salt; a truncated item set
  #        would otherwise have been served from cache forever)
  #   #48  "2264b5dbef6e" -> "8b02f87e393e7f9a"  (this one)
  #
  # #48 is NOT a drift change: rlang 1.3.0 rewrote hash() and its own NEWS says
  # "with this version all hash values will now be different". Since the key IS
  # the cache filename, that silently orphaned every cached entry. The fix moves
  # off rlang::hash() onto a canonical string hashed by digest, so the key is a
  # function of content alone. It is now also 16 chars rather than 12.
  #
  # This value is a PORTABLE FACT: identical on any machine, R version, rlang
  # version and architecture. If it differs on another machine, that is a real
  # failure of the property #48 exists to create -- not a golden to re-pin.
  expect_equal(cache_key(), "8b02f87e393e7f9a")
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

# Same call with `limit` OMITTED, so the PRODUCTION default is what reaches the
# query. `paged()` carries its own default of 500 and would therefore pin the
# test helper rather than the function — measured: changing the production
# default to 1 left the suite green until this existed.
paged_default_limit <- function() {
  drift:::stac_items_paged(
    stac_url = "https://example.com/stac", collection = "test-collection",
    bbox = c(0, 0, 1, 1), datetime = "2020-01-01/2020-12-31",
    sign_fn = function(items) items
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

test_that("stac_items_paged KEEPS a case-variant `next` and warns, keeping rel-less links", {
  # Deliberately NOT case-insensitive. rstac selects the next link with
  # `links(items, rel == "next")`, which is case-sensitive — measured:
  # next -> 1, NEXT -> 0, Next -> 0. So a `NEXT` link is inert to items_fetch()
  # and cannot cause the re-paging duplicate the strip exists to prevent. What
  # it DOES mean is that rstac could not follow it and stopped after page one —
  # the #51 truncation — and on PC nothing else can detect that. Stripping it
  # would delete the only local evidence, so it is kept and warned about.
  testthat::local_mocked_bindings(
    get_request = function(q, ...) {
      it <- fake_items("a", next_link = FALSE)
      it$links <- list(list(rel = "self", href = "s"),
                       list(href = "no-rel-at-all"),      # must survive
                       list(rel = "next", href = "p2"),   # followed -> stale, drop
                       list(rel = "NEXT", href = "p3"))   # NOT followed -> keep
      it
    },
    items_fetch = function(items, ...) items,
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  expect_warning(out <- paged(), "case-sensitively")
  rels <- vapply(out$links,
                 function(l) if (is.null(l$rel)) "" else l$rel, character(1))
  expect_false("next" %in% rels)           # the one rstac followed is gone
  expect_true("NEXT" %in% rels)            # the evidence is retained
  expect_setequal(rels, c("self", "", "NEXT"))
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
  # names the offending id, so a message that reports the wrong one fails
  expect_error(paged(), 'duplicate item id.*"a"')
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
  # both numbers, in order: "returned 3 ... reports 99". Matching only "99"
  # passes when n_items and matched are swapped, and those two numbers are
  # exactly what a user acts on.
  expect_error(paged(), "returned 3 items.*reports 99")
})

test_that("stac_items_paged warns, not aborts, when it has MORE items than reported", {
  # Asymmetric by design: fewer than reported is truncation (abort); more is
  # consistent with an ESTIMATED numberMatched, which pgstac/stac-fastapi can
  # return above a row threshold. Aborting there would fail toward abort on a
  # complete fetch — the mirror of the bug this whole change is about.
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items(c("a", "b", "c"), numberMatched = 2L),
    items_fetch = function(items, ...) items,
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  expect_warning(out <- paged(), "returned 3 items, more than the 2")
  expect_equal(length(out$features), 3L)      # and it still returns the items
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

test_that("stac_items_paged hands sign_fn to items_sign", {
  # Every other items_sign mock here is `function(items, ...)` and ignores
  # sign_fn, so dropping `sign_fn = sign_fn` from the call measured FAIL=0.
  # rstac::items_sign has no default for it, so the real failure is loud — but
  # nothing offline saw it.
  marker <- function(x) x
  got <- NULL
  testthat::local_mocked_bindings(
    get_request = function(q, ...) fake_items("a", next_link = FALSE),
    items_fetch = function(items, ...) items,
    items_sign = function(items, sign_fn, ...) { got <<- sign_fn; items },
    .package = "rstac"
  )
  paged(sign_fn = marker)
  expect_identical(got, marker)
})

test_that("stac_items_paged aborts on an item with no id, naming that cause", {
  # Not folded into the duplicate check: two id-less items would otherwise
  # abort as "duplicate item id: NA / pages overlapped", which names the wrong
  # cause. Measured FAIL=0 before this test existed.
  testthat::local_mocked_bindings(
    get_request = function(q, ...) {
      it <- fake_items("a", next_link = FALSE)
      it$features <- c(it$features, list(list(assets = list())))   # no id
      it
    },
    items_fetch = function(items, ...) items,
    items_sign = function(items, ...) items,
    .package = "rstac"
  )
  expect_error(paged(), "no usable")
  expect_error(paged(), "1 item")          # counts them
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
  # and pin the DEFAULT, which is the only value production ever uses:
  # dft_stac_fetch() never passes limit. Must go through the helper that OMITS
  # limit, or this pins the test helper's default instead of the function's.
  paged_default_limit()
  expect_equal(seen$params$limit, 500)
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
  # Capture the arguments, not just the fact of the call. A mock that discards
  # `...` proves the helper was reached and NOTHING about what it was handed —
  # measured: hardcoding sign_fn inside dft_stac_fetch(), or passing the wrong
  # bbox/datetime/collection, all leave the suite green.
  seen <- NULL
  testthat::local_mocked_bindings(
    stac_items_paged = function(...) {
      seen <<- list(...)
      fake_items(c("sentinel-x", "sentinel-y"), next_link = FALSE)
    }
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
  marker <- function(x) "SENTINEL-SIGN-FN"
  expect_error(
    suppressMessages(dft_stac_fetch(aoi, source = "io-lulc", years = 2020,
                                    sign_fn = marker,
                                    cache_dir = tempfile("drift_wire_"))),
    "collection built from: sentinel-x,sentinel-y"
  )

  # What it was handed. Without these, dft_stac_fetch() hardcoding its own
  # sign_fn would make the documented argument a silent no-op that no test in
  # this file catches — network test 1 uses the default and network test 2
  # calls the helper directly.
  cfg <- dft_stac_config("io-lulc")
  expect_identical(seen$sign_fn, marker)
  expect_identical(seen$collection, cfg$collection)
  expect_identical(seen$stac_url, cfg$stac_url)
  expect_identical(seen$datetime, "2020-01-01/2020-12-31")
  expect_equal(seen$bbox, as.numeric(sf::st_bbox(sf::st_transform(aoi, 4326))))
})

test_that("dft_stac_fetch attaches cache_key, offline", {
  # attr(, "cache_key") is a documented v0.10.0 return element whose only other
  # assertion is behind the network skip, i.e. absent from CI. Deleting the
  # assignment measured FAIL=0 without this. Pre-seed the cache so the
  # file.exists() short-circuit fires and no network or gdalcubes read happens.
  skip_if_not_installed("gdalcubes")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  cfg <- dft_stac_config("io-lulc")
  crs <- drift:::auto_utm_epsg(aoi)
  aoi_t <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", crs)))
  key <- drift:::stac_cache_key(aoi_t, 10, crs, "P1Y", "first", "near",
                                cfg$stac_url, cfg$collection, cfg$asset,
                                tile_size = NULL)
  cache <- tempfile("drift_key_")
  dir.create(drift:::cache_scheme_dir(cache, "io-lulc"), recursive = TRUE)
  # any raster GDAL can open; the extension is not sniffed for content. Built
  # over the AOI's own extent so the terra::mask() at the end of the cache-hit
  # path has something to clip.
  bb <- sf::st_bbox(aoi_t)
  r <- terra::rast(nrows = 20, ncols = 20, crs = crs,
                   xmin = bb[["xmin"]], xmax = bb[["xmax"]],
                   ymin = bb[["ymin"]], ymax = bb[["ymax"]])
  terra::values(r) <- seq_len(terra::ncell(r))
  # .nc is the extension the untiled cache path expects; terra advises writeCDF
  # for real NetCDF, but GDAL reads this back fine and the content is arbitrary
  suppressWarnings(
    terra::writeRaster(r, file.path(drift:::cache_scheme_dir(cache, "io-lulc"),
                                    paste0("2020_", key, ".nc")))
  )

  testthat::local_mocked_bindings(
    stac_items_paged = function(...) fake_items("a", next_link = FALSE)
  )
  # the image collection is built before the cache is consulted, and the fake
  # items carry no assets; the cache-hit path never uses the result
  testthat::local_mocked_bindings(
    stac_image_collection = function(...) NULL,
    .package = "gdalcubes"
  )
  out <- suppressMessages(
    dft_stac_fetch(aoi, source = "io-lulc", years = 2020, cache_dir = cache)
  )
  expect_identical(attr(out, "cache_key"), key)
  expect_s4_class(out[["2020"]], "SpatRaster")   # the cached file really was read
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

  # The discriminating comparison is truncated vs SMALL — both at limit = 1, so
  # they differ only by whether paging happened. Comparing truncated against
  # `big` cannot fail: limit = 500 returns all 14 in one page with or without
  # items_fetch(), so 1 < 14 holds in both worlds.
  expect_lt(length(truncated$features), length(small$features))
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


# ---------------------------------------------------------------------------
# #41 — atomic cache write, and validation of a cache entry before it is trusted
# ---------------------------------------------------------------------------

# Shared scaffolding: put a fetch on the MISS branch offline, with a writer we
# control. `stac_items_paged` and `stac_image_collection` are stubbed exactly as
# the cache_key test above does; `fetch_extent_to` is the drift internal that
# actually writes the untiled cache entry.
local_fetch_harness <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(
    stac_items_paged = function(...) fake_items("a", next_link = FALSE),
    .env = env
  )
  testthat::local_mocked_bindings(
    stac_image_collection = function(...) NULL,
    .package = "gdalcubes", .env = env
  )
}

# A small valid raster over the AOI, so a "successful" fetch produces something
# the trailing terra::mask() can actually clip.
aoi_raster <- function(aoi_target, nrows = 20, ncols = 20) {
  bb <- sf::st_bbox(aoi_target)
  r <- terra::rast(nrows = nrows, ncols = ncols,
                   crs = sf::st_crs(aoi_target)$wkt,
                   xmin = bb[["xmin"]], xmax = bb[["xmax"]],
                   ymin = bb[["ymin"]], ymax = bb[["ymax"]])
  terra::values(r) <- seq_len(terra::ncell(r))
  r
}

fetch_paths <- function(aoi, cache) {
  cfg <- dft_stac_config("io-lulc")
  crs <- drift:::auto_utm_epsg(aoi)
  aoi_t <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", crs)))
  key <- drift:::stac_cache_key(aoi_t, 10, crs, "P1Y", "first", "near",
                                cfg$stac_url, cfg$collection, cfg$asset,
                                tile_size = NULL)
  dir.create(drift:::cache_scheme_dir(cache, "io-lulc"), recursive = TRUE,
             showWarnings = FALSE)
  list(aoi_t = aoi_t, key = key,
       dir = drift:::cache_scheme_dir(cache, "io-lulc"),
       file = file.path(drift:::cache_scheme_dir(cache, "io-lulc"),
                        paste0("2020_", key, ".nc")))
}

read_aoi <- function() {
  sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"),
              quiet = TRUE)
}

test_that("a fetch that dies mid-write leaves NOTHING at the canonical cache path", {
  # The #41 defect itself. Against the pre-fix code the half-written bytes land
  # on `cache_file`, and the NEXT run reports them as `cached`.
  skip_if_not_installed("gdalcubes")
  aoi <- read_aoi()
  cache <- tempfile("drift_atomic_")
  p <- fetch_paths(aoi, cache)
  local_fetch_harness()

  testthat::local_mocked_bindings(
    fetch_extent_to = function(col, ext, t0, t1, target_crs, res, dt,
                               aggregation, resampling, out_nc) {
      writeBin(as.raw(rep(0, 2048)), out_nc)   # a partial, unreadable file
      stop("killed mid-write")
    }
  )

  expect_error(
    suppressMessages(suppressWarnings(
      dft_stac_fetch(aoi, source = "io-lulc", years = 2020, cache_dir = cache)
    )),
    "killed mid-write"
  )
  expect_false(file.exists(p$file))
  # and no temp survives either
  expect_length(list.files(p$dir, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("a fetch that dies mid-write does not destroy an existing good cache under force", {
  # Pre-fix, force = TRUE truncates the canonical file BEFORE writing, so an
  # interrupted forced re-fetch loses a cache that was perfectly good.
  skip_if_not_installed("gdalcubes")
  aoi <- read_aoi()
  cache <- tempfile("drift_atomic_force_")
  p <- fetch_paths(aoi, cache)
  suppressWarnings(terra::writeRaster(aoi_raster(p$aoi_t), p$file))
  before_size <- file.size(p$file)
  before_vals <- terra::values(terra::rast(p$file))
  local_fetch_harness()

  testthat::local_mocked_bindings(
    fetch_extent_to = function(col, ext, t0, t1, target_crs, res, dt,
                               aggregation, resampling, out_nc) {
      writeBin(as.raw(rep(0, 2048)), out_nc)
      stop("killed mid-write")
    }
  )

  expect_error(
    suppressMessages(suppressWarnings(
      dft_stac_fetch(aoi, source = "io-lulc", years = 2020,
                     cache_dir = cache, force = TRUE)
    )),
    "killed mid-write"
  )
  expect_true(file.exists(p$file))
  expect_identical(file.size(p$file), before_size)
  expect_equal(terra::values(terra::rast(p$file)), before_vals)
})

test_that("a successful fetch leaves the canonical file and no temp behind", {
  # Positive control for the two tests above: they would both also pass if the
  # fetch simply never wrote anything.
  skip_if_not_installed("gdalcubes")
  aoi <- read_aoi()
  cache <- tempfile("drift_atomic_ok_")
  p <- fetch_paths(aoi, cache)
  local_fetch_harness()

  seen_path <- NULL
  testthat::local_mocked_bindings(
    fetch_extent_to = function(col, ext, t0, t1, target_crs, res, dt,
                               aggregation, resampling, out_nc) {
      seen_path <<- out_nc
      suppressWarnings(terra::writeRaster(aoi_raster(p$aoi_t), out_nc,
                                          overwrite = TRUE))
      out_nc
    }
  )

  out <- suppressMessages(suppressWarnings(
    dft_stac_fetch(aoi, source = "io-lulc", years = 2020, cache_dir = cache)
  ))
  expect_s4_class(out[["2020"]], "SpatRaster")
  expect_true(file.exists(p$file))
  # No temp litter. A GDAL PAM sidecar may legitimately sit beside the entry
  # (terra emits one writing .nc, not .tif) — it must carry the CANONICAL stem,
  # never the dead temp name.
  left <- list.files(p$dir, all.files = TRUE, no.. = TRUE)
  expect_length(grep("\\.tmp[0-9]", left, value = TRUE), 0L)
  expect_true(all(startsWith(left, tools::file_path_sans_ext(basename(p$file)))))
  # The writer is handed the TEMP, not the canonical name — asserting equality
  # with p$file here would pin the very defect this fixes.
  expect_false(identical(seen_path, p$file))
  expect_identical(dirname(seen_path), p$dir)
})

test_that("a failed file.rename aborts rather than silently leaving no cache", {
  # file.rename() signals failure by RETURNING FALSE, not by erroring, so an
  # unchecked move is how a missing cache reaches a consumer with no complaint.
  skip_if_not_installed("gdalcubes")
  aoi <- read_aoi()
  cache <- tempfile("drift_atomic_rename_")
  p <- fetch_paths(aoi, cache)
  local_fetch_harness()

  testthat::local_mocked_bindings(
    fetch_extent_to = function(col, ext, t0, t1, target_crs, res, dt,
                               aggregation, resampling, out_nc) {
      suppressWarnings(terra::writeRaster(aoi_raster(p$aoi_t), out_nc,
                                          overwrite = TRUE))
      out_nc
    }
  )
  testthat::local_mocked_bindings(
    file.rename = function(from, to) FALSE, .package = "base"
  )

  expect_error(
    suppressMessages(suppressWarnings(
      dft_stac_fetch(aoi, source = "io-lulc", years = 2020, cache_dir = cache)
    )),
    "could not be moved into place"
  )
})

# --- cache_geom_ok(): the predicate, exercised on every branch ---------------
#
# Split out from the SpatRaster so all four sub-checks are reachable. terra
# refuses to CONSTRUCT a zero-dim, non-finite-res or collapsed-extent raster, so
# driving these through a file would leave three of the four shipping untested.

test_that("cache_geom_ok accepts a healthy geometry", {
  expect_true(is.na(drift:::cache_geom_ok(
    dims = c(100, 200, 1), res = c(10, 10),
    ext = c(5e5, 5.02e5, 6e6, 6.001e6), crs = "EPSG:32609"
  )))
})

test_that("cache_geom_ok rejects each degenerate geometry", {
  base_ok <- list(dims = c(100, 200, 1), res = c(10, 10),
                  ext = c(5e5, 5.02e5, 6e6, 6.001e6), crs = "EPSG:32609")
  bad <- function(...) {
    a <- utils::modifyList(base_ok, list(...))
    drift:::cache_geom_ok(a$dims, a$res, a$ext, a$crs)
  }
  expect_match(bad(dims = c(0, 200, 1)), "zero rows or columns")
  expect_match(bad(res = c(0, 10)), "non-finite or non-positive resolution")
  expect_match(bad(res = c(NaN, 10)), "non-finite or non-positive resolution")
  expect_match(bad(ext = c(5e5, Inf, 6e6, 6.001e6)), "non-finite extent")
  expect_match(bad(ext = c(5e5, 5e5, 6e6, 6.001e6)), "collapsed extent")
})

test_that("cache_geom_ok flags an empty CRS only WITH the identity geotransform", {
  # The conjunction is the point. An empty CRS alone is not proof of damage, and
  # refusing on it alone risks throwing away healthy cache entries; the identity
  # geotransform (res 1, extent 0..ncol / 0..nrow) is the second, independent
  # signal, and together they are the shape the #41 traceback describes
  # ("Cannot invert geotransform").
  identity_hit <- drift:::cache_geom_ok(
    dims = c(100, 200, 1), res = c(1, 1), ext = c(0, 200, 0, 100), crs = ""
  )
  expect_match(identity_hit, "identity geotransform")

  # empty CRS but real georeferencing -> accepted
  expect_true(is.na(drift:::cache_geom_ok(
    dims = c(100, 200, 1), res = c(10, 10),
    ext = c(5e5, 5.02e5, 6e6, 6.001e6), crs = ""
  )))
  # identity geotransform but a real CRS -> accepted
  expect_true(is.na(drift:::cache_geom_ok(
    dims = c(100, 200, 1), res = c(1, 1), ext = c(0, 200, 0, 100),
    crs = "EPSG:32609"
  )))
})

# --- cache_invalid_reason(): the three arms ---------------------------------

test_that("arm (a): an unopenable cache file is rejected", {
  d <- tempfile("drift_arm_a_"); dir.create(d)
  zero <- file.path(d, "zero.nc"); file.create(zero)

  r <- terra::rast(nrows = 60, ncols = 60, crs = "EPSG:32609",
                   xmin = 5e5, xmax = 5.006e5, ymin = 6e6, ymax = 6.0006e6)
  terra::values(r) <- seq_len(terra::ncell(r))
  full <- file.path(d, "full.tif"); terra::writeRaster(r, full)
  raw_all <- readBin(full, "raw", file.size(full))
  trunc <- file.path(d, "trunc.tif")
  writeBin(raw_all[seq_len(floor(length(raw_all) * 0.4))], trunc)

  # Premise: these fixtures really do fail to OPEN, so this test is exercising
  # arm (a) and not being carried by a later arm.
  expect_error(suppressWarnings(terra::rast(zero)))
  expect_error(suppressWarnings(terra::rast(trunc)))

  expect_match(suppressWarnings(drift:::cache_invalid_reason(zero)),
               "could not be opened")
  expect_match(suppressWarnings(drift:::cache_invalid_reason(trunc)),
               "could not be opened")
})

test_that("arm (a) does not reject a healthy raster, and tolerates open warnings", {
  # terra emits a capability warning when writing .nc; the multidim-API warning
  # on open is likewise a capability message, NOT a damage signal. Arm (a)
  # catches ERRORS only — failing on an open warning would refuse healthy .nc
  # files across the whole cache.
  d <- tempfile("drift_arm_a_ok_"); dir.create(d)
  r <- terra::rast(nrows = 40, ncols = 40, crs = "EPSG:32609",
                   xmin = 5e5, xmax = 5.004e5, ymin = 6e6, ymax = 6.0004e6)
  terra::values(r) <- seq_len(terra::ncell(r))
  for (f in c("ok.tif", "ok.nc")) {
    p <- file.path(d, f)
    suppressWarnings(terra::writeRaster(r, p))
    expect_true(is.na(suppressWarnings(drift:::cache_invalid_reason(p))),
                info = f)
  }
})

test_that("arm (c): a read probe that warns is treated as a corrupt entry", {
  # NAMED FOR WHAT IT TESTS: the handler, not the damage. The probe is injected
  # so this runs everywhere and deterministically.
  #
  # This does NOT prove drift detects real content damage — see the env-guarded
  # test below for that. Against a restored defect it fails only if the warning
  # handling is deleted, which is exactly the scope claimed here.
  d <- tempfile("drift_arm_c_"); dir.create(d)
  r <- terra::rast(nrows = 20, ncols = 20, crs = "EPSG:32609",
                   xmin = 5e5, xmax = 5.002e5, ymin = 6e6, ymax = 6.0002e6)
  terra::values(r) <- seq_len(terra::ncell(r))
  p <- file.path(d, "ok.tif"); terra::writeRaster(r, p)

  # Premise: with the real probe this file is CLEAN, so any rejection below is
  # attributable to the injected probe and not to the fixture.
  expect_true(is.na(drift:::cache_invalid_reason(p)))

  warned <- drift:::cache_invalid_reason(
    p, probe = function(x) { warning("netcdf error #-101 : NetCDF: HDF error"); TRUE }
  )
  expect_match(warned, "pixel data could not be read")

  errored <- drift:::cache_invalid_reason(p, probe = function(x) stop("read blew up"))
  expect_match(errored, "pixel data could not be read")
})

test_that("arm (c): real content damage is detected (fixture must prove itself)", {
  # The honest version. Content damage that leaves the container walkable is
  # NOT reproducible from a terra-written file: measured 2026-09-02, zeroing the
  # tail of a terra-written .nc (which is NC4/HDF5) produces no warning at all,
  # while the same damage to a gdalcubes-written .nc does. Whether the arm fires
  # depends on whether the zeroed bytes carried structure or bulk data.
  #
  # So this test builds the damage and then ASSERTS ITS OWN PREMISE: if the
  # damaged file does not actually warn on read, it SKIPS rather than passing.
  # A silent pass here would be a test that proves nothing.
  skip_if(Sys.getenv("DRIFT_TEST_CACHE_DAMAGE") != "true",
          "damage fixture is format-dependent — set DRIFT_TEST_CACHE_DAMAGE=true")
  src <- Sys.getenv("DRIFT_TEST_CACHE_DAMAGE_FILE")
  skip_if(!nzchar(src) || !file.exists(src),
          "set DRIFT_TEST_CACHE_DAMAGE_FILE to a gdalcubes-written .nc")

  d <- tempfile("drift_arm_c_real_"); dir.create(d)
  raw_all <- readBin(src, "raw", file.size(src))
  n <- length(raw_all)
  raw_all[(floor(n * 0.5) + 1):n] <- as.raw(0)
  dmg <- file.path(d, paste0("damaged.", tools::file_ext(src)))
  writeBin(raw_all, dmg)

  # Premise 1: it still OPENS with valid geometry, so arms (a) and (b) are
  # proven not to be what fires below.
  opened <- tryCatch(terra::rast(dmg), error = function(e) NULL)
  skip_if(is.null(opened), "damage broke the open — reaches arm (a), not arm (c)")
  skip_if(!is.na(drift:::cache_geom_ok(dim(opened), terra::res(opened),
                                       as.vector(terra::ext(opened)),
                                       terra::crs(opened))),
          "damage broke the geometry — reaches arm (b), not arm (c)")
  # Premise 2: the damage really does surface on read (as a warning or error).
  read_dirty <- FALSE
  withCallingHandlers(
    tryCatch(drift:::cache_probe_last_row(terra::rast(dmg)),
             error = function(e) read_dirty <<- TRUE),
    warning = function(w) {
      read_dirty <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  skip_if(!read_dirty,
          "damage did not surface on read — fixture cannot reach arm (c)")

  expect_match(drift:::cache_invalid_reason(dmg), "pixel data could not be read")
})

# --- the read gate ----------------------------------------------------------

test_that("a corrupt cache entry is re-fetched instead of served as a hit", {
  # The end-to-end #41 behaviour: presence is no longer trust.
  skip_if_not_installed("gdalcubes")
  aoi <- read_aoi()
  cache <- tempfile("drift_gate_")
  p <- fetch_paths(aoi, cache)
  writeBin(as.raw(rep(0, 4096)), p$file)   # a corrupt entry at the canonical name
  local_fetch_harness()

  refetched <- FALSE
  testthat::local_mocked_bindings(
    fetch_extent_to = function(col, ext, t0, t1, target_crs, res, dt,
                               aggregation, resampling, out_nc) {
      refetched <<- TRUE
      suppressWarnings(terra::writeRaster(aoi_raster(p$aoi_t), out_nc,
                                          overwrite = TRUE))
      out_nc
    }
  )

  expect_warning(
    out <- suppressMessages(
      dft_stac_fetch(aoi, source = "io-lulc", years = 2020, cache_dir = cache)
    ),
    "re-fetching"
  )
  expect_true(refetched)
  expect_s4_class(out[["2020"]], "SpatRaster")
  expect_true(is.na(suppressWarnings(drift:::cache_invalid_reason(p$file))))
})

test_that("a healthy cache entry is still served as a hit, with no re-fetch", {
  # False-refusal control. A validator that rejects healthy input is worse than
  # the bug it guards, because the cost is a silent permanent re-download.
  skip_if_not_installed("gdalcubes")
  aoi <- read_aoi()
  cache <- tempfile("drift_gate_ok_")
  p <- fetch_paths(aoi, cache)
  suppressWarnings(terra::writeRaster(aoi_raster(p$aoi_t), p$file))
  local_fetch_harness()

  testthat::local_mocked_bindings(
    fetch_extent_to = function(...) stop("re-fetched a healthy cache entry")
  )
  expect_no_error(
    out <- suppressMessages(suppressWarnings(
      dft_stac_fetch(aoi, source = "io-lulc", years = 2020, cache_dir = cache)
    ))
  )
  expect_s4_class(out[["2020"]], "SpatRaster")
})


# ---------------------------------------------------------------------------
# #48 — the cache key must be a function of CONTENT, not of a library's
# traversal of an R object. rlang 1.3.0 rewrote hash() and moved every key,
# silently orphaning every cached entry, because the key IS the filename.
# ---------------------------------------------------------------------------

test_that("cache_key_string returns exactly one non-NA string", {
  # THE load-bearing guard. digest(serialize = FALSE) takes only the FIRST
  # element of a character vector, silently:
  #   digest(c("a","b"), "xxhash64", serialize = FALSE) ==
  #   digest("a",        "xxhash64", serialize = FALSE)
  # so a length > 1 here collapses EVERY key to the hash of its first member —
  # a total collision, not a probabilistic one, with no warning anywhere.
  s <- drift:::cache_key_string(list(sf::st_as_binary(sf::st_geometry(square_aoi())),
                                     10, "a", TRUE, NULL, c("x", "y")))
  expect_type(s, "character")
  expect_length(s, 1L)
  expect_false(is.na(s))

  # and the premise: digest really does behave that way, so this test is
  # guarding a live hazard rather than a hypothetical one
  expect_identical(
    digest::digest(c("a", "b"), algo = "xxhash64", serialize = FALSE),
    digest::digest("a", algo = "xxhash64", serialize = FALSE)
  )
})

test_that("cache_key_hash refuses a multi-element string", {
  local_mocked_bindings(cache_key_string = function(...) c("a", "b"))
  expect_error(drift:::cache_key_hash(list(1)), "length")
})

test_that("cache_key_string distinguishes every type-collision pair", {
  # Without a per-member type tag a plain string scheme collides all of these.
  # None bites today only because each member position happens to be type-fixed
  # by coercion at the call sites — an invariant held by convention and written
  # down nowhere, which the cube key does not even follow for its character
  # members. The tags make it structural.
  ks <- function(x) drift:::cache_key_string(list(x))
  expect_false(ks(NULL)            == ks("<none>"))
  expect_false(ks(NA_character_)   == ks("<NA>"))
  expect_false(ks(10)              == ks("10"))
  expect_false(ks(TRUE)            == ks("TRUE"))
  expect_false(ks(as.raw(0xab))    == ks("ab"))
  expect_false(ks(c("B08", "B04")) == ks("B08,B04"))
  expect_false(ks(character(0))    == ks(""))
})

test_that("cache_key_string keeps NaN and NA_real_ apart", {
  # sprintf("%.17g", ...) plus an is.na() sentinel would collapse these, because
  # is.na(NaN) is TRUE. The IEEE-754 byte encoding does not.
  expect_true(is.na(NaN))                                   # the premise
  expect_false(drift:::cache_key_string(list(NaN)) ==
                 drift:::cache_key_string(list(NA_real_)))
})

test_that("cache_key_string treats integer and double alike, and TRUE is not 1", {
  expect_identical(drift:::cache_key_string(list(10L)),
                   drift:::cache_key_string(list(10)))
  # branch order: sprintf/as.double render TRUE as 1, so is.logical() must be
  # tested before is.numeric()
  expect_false(drift:::cache_key_string(list(TRUE)) ==
                 drift:::cache_key_string(list(1)))
})

test_that("cache_key_string handles the WKB member, which is a LIST not a raw", {
  # sf::st_as_binary() returns a list of raw vectors classed "WKB"; is.raw() on
  # it is FALSE. A raw-only branch would never match it, so this pins the
  # is.list() branch and its ordering.
  w <- sf::st_as_binary(sf::st_geometry(square_aoi()), endian = "little")
  expect_false(is.raw(w))                                   # the premise
  expect_true(is.list(w))
  s <- drift:::cache_key_string(list(w))
  expect_length(s, 1L)
  expect_match(s, "^l:x:[0-9a-f]+$")
})

test_that("a multi-feature AOI keys differently under a different feature order", {
  p1 <- sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0))))
  p2 <- sf::st_polygon(list(rbind(c(5, 5), c(6, 5), c(6, 6), c(5, 6), c(5, 5))))
  a <- sf::st_sfc(p1, p2, crs = 32609)
  b <- sf::st_sfc(p2, p1, crs = 32609)
  expect_false(
    drift:::stac_cache_key(a, 10, "EPSG:32609", "P1Y", "first", "near",
                           "u", "c", "d", tile_size = NULL) ==
    drift:::stac_cache_key(b, 10, "EPSG:32609", "P1Y", "first", "near",
                           "u", "c", "d", tile_size = NULL)
  )
})

test_that("the canonical STRING is pinned, not only the hash", {
  # The honest form of the stability goal, and the one that makes a future
  # failure diagnosable:
  #   this passes + the key golden fails -> the HASHING layer moved
  #   this fails                         -> OUR INPUTS moved, and the diff
  #                                          names the member that did
  expect_identical(
    drift:::cache_key_string(list(as.raw(c(0x01, 0xff)), 10, "abc", TRUE, NULL)),
    "x:01ff\x1fn:0000000000002440\x1fs:abc\x1fb:T\x1f0:"
  )
})

test_that("digest still reproduces its own published XXH64 vector", {
  # The control that separates "the hashing layer moved" from "we changed the
  # inputs". Uses digest's OWN pinned upstream vector (inst/tinytest/
  # test_digest.R) rather than an arbitrary string, so a failure here is
  # directly attributable upstream instead of being drift's problem to guess at.
  expect_identical(
    digest::digest("abc", algo = "xxhash64", serialize = FALSE),
    "44bc2cf5ad770999"
  )
})

test_that("neither key function reaches R serialization or rlang::hash", {
  # Structural, not behavioural: catches a reintroduction by ANY route,
  # including an accidental `serialize = TRUE` on the digest call — which is the
  # specific regression that would silently re-couple the key to R's
  # serialization version without changing any visible behaviour today.
  for (f in list(drift:::stac_cache_key, drift:::stac_cube_cache_key,
                 drift:::cache_key_hash, drift:::cache_key_string,
                 drift:::cache_key_member)) {
    src <- paste(deparse(body(f)), collapse = " ")
    expect_false(grepl("rlang::hash|\\bhash\\(", src))
    expect_false(grepl("serialize\\s*=\\s*TRUE|\\bserialize\\(", src))
  }
})

test_that("the key does not move when rlang's hash does", {
  # A REINTRODUCTION guard, not a proof of independence — the key now depends on
  # digest instead, and the source assertion above is what proves rlang is gone.
  # This fails loudly if someone routes the key back through rlang::hash().
  before <- cache_key()
  local_mocked_bindings(hash = function(...) "TOTALLY-DIFFERENT-VALUE",
                        .package = "rlang")
  expect_identical(cache_key(), before)
  expect_identical(cache_key(), "8b02f87e393e7f9a")
})

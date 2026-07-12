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
                     cloud_cover_max = 60, mask_values = c(3, 8, 9, 10, 11),
                     scale = 1e-4, offset = -0.1, months = NULL,
                     offset_before = 0, clip = TRUE, tile_size = NULL) {
  # dft_stac_cube snaps tile_size to the pixel grid before it reaches the key;
  # mirror that here so the snap-before-key test reflects real behavior (#38)
  if (!is.null(tile_size)) {
    tile_size <- suppressMessages(drift:::tile_size_check(tile_size, res))
  }
  drift:::stac_cube_cache_key(
    aoi, res, target_crs, dt, aggregation, resampling, stac_url, collection,
    band_assets, datetime, index, cloud_cover_max, mask_values, scale, offset,
    months, offset_before, clip, tile_size
  )
}

test_that("stac_cube_cache_key is deterministic and 12-char hex", {
  expect_equal(cube_key(), cube_key())
  expect_match(cube_key(), "^[0-9a-f]{12}$")
})

test_that("stac_cube_cache_key untiled key is frozen (legacy-cache guardian)", {
  # Freezes the exact 12-char hash for cube_key()'s fixed inputs so the
  # tile_size append can't silently perturb the untiled key and orphan every
  # existing cube_<key>.tif (10-30 min to re-stream). Mirrors the fetch golden
  # 79f67b7b9dae (#36). If this ever changes, existing cube caches are invalid.
  expect_equal(cube_key(), "638a2be11fdf")
})

test_that("stac_cube_cache_key keys tile_size distinctly and after snapping", {
  base <- cube_key()                                     # tile_size = NULL
  expect_false(cube_key(tile_size = 500) == base)        # tiled keys apart from untiled
  expect_false(cube_key(tile_size = 500) ==
                 cube_key(tile_size = 250))              # distinct sizes -> distinct keys
  # snapped to the res-lattice before the key: 504 -> 500 (res 10), same key
  expect_equal(cube_key(tile_size = 504), cube_key(tile_size = 500))
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
  expect_false(cube_key(months = 6:9) == base)
  expect_false(cube_key(offset_before = -0.1) == base)
  # clip must key distinctly, or a clip=FALSE request silently hits a clipped
  # (or vice-versa) cached .tif and returns wrong-extent data
  expect_false(cube_key(clip = FALSE) == base)
})

test_that("stac_cube_cache_key normalizes months order", {
  expect_equal(cube_key(months = c(6, 7, 8, 9)), cube_key(months = c(9, 8, 7, 6)))
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

# stac_cube_clip(): the AOI-polygon clip that replaces gdalcubes::filter_geom
# (#32). Network-free — a synthetic stack + a half-covering polygon. Cells whose
# centre is outside the polygon become NA on every layer; nlyr is preserved.
test_that("stac_cube_clip masks cells outside the AOI polygon on every layer", {
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10,
                   ymin = 0, ymax = 10, crs = "EPSG:32609", nlyrs = 2)
  terra::values(r) <- 1                       # every cell valid on both layers
  # AOI covers the left half (x in [0, 5]); no cell centre lands exactly on 5
  aoi <- sf::st_sfc(
    sf::st_polygon(list(rbind(
      c(0, 0), c(5, 0), c(5, 10), c(0, 10), c(0, 0)
    ))),
    crs = 32609
  )
  out <- drift:::stac_cube_clip(r, aoi)

  expect_s4_class(out, "SpatRaster")
  expect_equal(terra::nlyr(out), 2L)          # layers preserved
  vals <- terra::values(out)
  inside <- terra::xyFromCell(out, seq_len(terra::ncell(out)))[, 1] < 5
  expect_true(all(!is.na(vals[inside, ])))    # inside polygon: retained
  expect_true(all(is.na(vals[!inside, ])))    # outside polygon: NA
})

# mosaic_stacks(): the in-memory, multi-layer merge that reassembles per-tile
# index stacks into one raster on the tiled read path (#38). Network-free —
# synthetic multi-layer rasters split into res-aligned, non-overlapping tiles.

test_that("mosaic_stacks reassembles res-aligned tiles losslessly across layers", {
  # 3-layer reference on a known lattice; distinct values per cell AND per layer
  # (values fill layer-major: L1 = 1:64, L2 = 65:128, L3 = 129:192), so a layer
  # swap or a spatial mis-merge would change the compared values
  ref <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 80,
                     ymin = 0, ymax = 80, crs = "EPSG:32609", nlyrs = 3)
  terra::values(ref) <- seq_len(terra::ncell(ref) * terra::nlyr(ref))
  # split into 4 quadrant tiles (40x40), res-aligned, non-overlapping, tiling ref
  exts <- list(terra::ext(0, 40, 0, 40), terra::ext(40, 80, 0, 40),
               terra::ext(0, 40, 40, 80), terra::ext(40, 80, 40, 80))
  merged <- drift:::mosaic_stacks(lapply(exts, function(e) terra::crop(ref, e)))

  expect_s4_class(merged, "SpatRaster")
  expect_equal(terra::nlyr(merged), 3L)                       # all layers kept
  expect_true(terra::compareGeom(merged, ref, stopOnError = FALSE))
  expect_equal(terra::values(merged), terra::values(ref))     # exact, per layer
})

test_that("tiling commutes with the offset-split cover (per-tile cover + merge == global cover)", {
  # Mimics the 2022 offset split: pre/post subcubes with complementary NA
  # patterns, coalesced by terra::cover. Under tiling the cover runs per tile,
  # then the tiles are merged; that must equal covering the full extent once.
  base <- function() {
    terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 80,
                ymin = 0, ymax = 80, crs = "EPSG:32609", nlyrs = 2)
  }
  pre <- base()
  post <- base()
  n <- terra::ncell(pre)                         # 64
  odd <- seq_len(n) %% 2 == 1
  # layer 1: pre holds odd cells (NA on even), post holds even; layer 2 reversed
  # -> cover must pick pre-then-post per cell, per layer, and tiles partition space
  terra::values(pre)  <- c(ifelse(odd, seq_len(n), NA),
                           ifelse(odd, NA, seq_len(n) + 200))
  terra::values(post) <- c(ifelse(odd, NA, seq_len(n) + 100),
                           ifelse(odd, seq_len(n) + 300, NA))
  ref <- terra::cover(pre, post)
  expect_false(anyNA(terra::values(ref)))        # complementary -> fully coalesced

  exts <- list(terra::ext(0, 40, 0, 40), terra::ext(40, 80, 0, 40),
               terra::ext(0, 40, 40, 80), terra::ext(40, 80, 40, 80))
  tiled <- drift:::mosaic_stacks(lapply(exts, function(e) {
    terra::cover(terra::crop(pre, e), terra::crop(post, e))
  }))

  expect_true(terra::compareGeom(tiled, ref, stopOnError = FALSE))
  expect_equal(terra::values(tiled), terra::values(ref))
})

test_that("mosaic_stacks over tile_grid tiles leaves NA gaps where empty tiles were skipped", {
  # Documents the clip = FALSE + tile_size contract: the mosaic is the union of
  # AOI-intersecting tiles, with NA where empty tiles were dropped — NOT a
  # gap-free bounding box. Uses the packaged diagonal reach (area/bbox ~ 0.105).
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"), quiet = TRUE
  )
  target_crs <- drift:::auto_utm_epsg(aoi)
  aoi_t <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))
  res <- 10
  tile_size <- suppressMessages(drift:::tile_size_check(500, res))
  tiles <- drift:::tile_grid(aoi_t, tile_size, res)

  be <- sf::st_bbox(aoi_t)
  n_full <- ceiling((be[["xmax"]] - be[["xmin"]]) / tile_size) *
    ceiling((be[["ymax"]] - be[["ymin"]]) / tile_size)
  expect_lt(length(tiles), n_full)               # empty tiles dropped (the mechanism)

  # each kept tile filled with 1; merge -> rectangular bbox of kept tiles with
  # NA in the skipped-tile gaps
  merged <- drift:::mosaic_stacks(lapply(tiles, function(ext) {
    terra::rast(xmin = ext$left, xmax = ext$right, ymin = ext$bottom,
                ymax = ext$top, resolution = res, crs = target_crs, vals = 1)
  }))
  expect_true(anyNA(terra::values(merged)))      # gaps -> not a gap-free bbox
})

# Network end-to-end against the Planetary Computer. Opt-in only (env var), so
# the default `devtools::test()` stays network-free per the repo convention.
test_that("dft_stac_cube fetches an index stack end-to-end", {
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
  expect_s4_class(cube, "SpatRaster")
  expect_equal(terra::nlyr(cube), 3)                 # 3 monthly layers
  expect_false(anyNA(terra::time(cube)))             # time set per layer
  # default clip = TRUE clips to the AOI polygon: for this thin reach
  # (area / bbox ~= 0.105) most bbox cells are fully NA across all layers
  fully_na <- mean(rowSums(!is.na(terra::values(cube))) == 0)
  expect_gt(fully_na, 0.5)
  # second call hits the cache (one cube_<key>.tif under the source dir)
  expect_length(list.files(file.path(cache, "sentinel-2-l2a"),
                           pattern = "^cube_.*\\.tif$"), 1)
})

# Tiled read (#38) vs untiled, end-to-end. Opt-in. This is the only test that
# exercises the real gdalcubes tiled read against live COGs — that a tile
# sub-extent reads the same source pixels as the full bbox. The tiled and untiled
# cubes are NOT co-lattice and can't be compared pixel-for-pixel: gdalcubes
# enlarges the untiled bbox extent symmetrically to align with dx/dy (~0.5 px),
# while the tiles are anchored at the bbox lower-left. Both are valid resamplings
# of the same source, so equivalence is asserted via bilinear alignment
# (correlation + bulk agreement) and grid-independent per-layer means. Verified
# offline against saved 2021-07/08 cubes to have no tile seams (edge |diff| ==
# interior) — the residual is the benign sub-pixel offset, not a seam. Thresholds
# are measured on those cubes (cor 0.997, median |diff| 3.4e-3, per-layer mean
# 6e-4) with headroom. A growing-season window is used for robust valid-pixel
# coverage; the offset split under tiling is proven by the offline commutativity
# oracle above, not here.
test_that("dft_stac_cube tiled read reproduces the untiled cube over the AOI", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "network test — set DRIFT_TEST_NETWORK=true to run")
  skip_if_not_installed("gdalcubes")
  aoi <- sf::st_read(
    system.file("extdata", "example_aoi.gpkg", package = "drift"),
    quiet = TRUE
  )
  dtwin <- "2021-07-01/2021-08-31"
  cache <- tempfile("drift_cube_tiled_")
  dir.create(cache)

  untiled <- dft_stac_cube(aoi, index = "kndvi", datetime = dtwin, dt = "P1M",
                           cache_dir = cache)
  tiled <- dft_stac_cube(aoi, index = "kndvi", datetime = dtwin, dt = "P1M",
                         tile_size = 1000, cache_dir = cache)

  expect_s4_class(tiled, "SpatRaster")
  expect_equal(terra::nlyr(tiled), terra::nlyr(untiled))   # same monthly axis
  expect_false(anyNA(terra::time(tiled)))                  # time set per layer
  # tiled and untiled each cache one cube_<key>.tif, keyed apart (2 files total)
  expect_length(list.files(file.path(cache, "sentinel-2-l2a"),
                           pattern = "^cube_.*\\.tif$"), 2)

  # the efficiency claim: for this diagonal reach the tiled read streams fewer
  # tiles than the full grid (offline-computable, but assert it alongside the fetch)
  target_crs <- drift:::auto_utm_epsg(aoi)
  aoi_t <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))
  ts <- suppressMessages(drift:::tile_size_check(1000, 10))
  be <- sf::st_bbox(aoi_t)
  n_full <- ceiling((be[["xmax"]] - be[["xmin"]]) / ts) *
    ceiling((be[["ymax"]] - be[["ymin"]]) / ts)
  expect_lt(length(drift:::tile_grid(aoi_t, ts, 10)), n_full)

  # equivalence over common in-AOI cells: align tiled onto the untiled grid with
  # BILINEAR (corrects the sub-pixel offset), then compare. A genuinely wrong
  # tiled read (wrong per-tile offset, scrambled tiles, real seams) would drop the
  # correlation and shift the means far past these bounds.
  aligned <- terra::resample(tiled, untiled, method = "bilinear")
  a <- terra::values(untiled)
  b <- terra::values(aligned)
  both <- !is.na(a) & !is.na(b)
  expect_gt(sum(both), 0)                                        # overlap exists
  expect_gt(stats::cor(a[both], b[both]), 0.98)                  # spatial pattern reproduced
  expect_lt(stats::median(abs(a[both] - b[both])), 0.01)         # bulk agreement
  # grid-independent: per-layer spatial-mean kNDVI agrees closely
  layer_mean <- function(x) {
    vapply(seq_len(terra::nlyr(x)),
           function(i) mean(terra::values(x[[i]]), na.rm = TRUE), 0)
  }
  expect_lt(max(abs(layer_mean(tiled) - layer_mean(untiled))), 0.01)
})

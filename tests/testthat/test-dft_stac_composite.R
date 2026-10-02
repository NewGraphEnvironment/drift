s2_roles <- dft_stac_config("sentinel-2-l2a")$roles

aoi_pkg <- function() {
  sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"),
              quiet = TRUE)
}

# Arguments for stac_composite_cache_key(), varied one at a time below
key_args <- function(...) {
  aoi <- sf::st_transform(aoi_pkg(), 32609)
  base <- list(
    aoi_target = aoi, res = 10, target_crs = "EPSG:32609",
    datetime = "2017-06-01/2017-07-31", dt = "P2M", aggregation = "median",
    resampling = "bilinear",
    stac_url = "https://planetarycomputer.microsoft.com/api/stac/v1",
    collection = "sentinel-2-l2a", band_assets = c("B04", "B03", "B02"),
    bands = c("red", "green", "blue"), cloud_cover_max = 20,
    mask_values = c(3L, 8L, 9L, 10L, 11L), scale = 1e-4, offset = -0.1,
    offset_before = 0, months = 6:7, clip = TRUE, tile_size = NULL
  )
  utils::modifyList(base, list(...))
}
ckey <- function(...) do.call(drift:::stac_composite_cache_key, key_args(...))

test_that("composite_window spans first-of-first to last-of-last month as one step", {
  w <- drift:::composite_window(2017, 6:7)
  expect_equal(w$t0, "2017-06-01")
  expect_equal(w$t1, "2017-07-31")
  expect_equal(w$datetime, "2017-06-01/2017-07-31")
  expect_equal(w$dt, "P2M")
  # a gap still spans first to last; the month filter drops the gap's scenes
  expect_equal(drift:::composite_window(2023, c(6, 8))$dt, "P3M")
  # February's end follows the calendar, leap year included
  expect_equal(drift:::composite_window(2024, 2)$t1, "2024-02-29")
  expect_equal(drift:::composite_window(2023, 2)$t1, "2023-02-28")
  expect_equal(drift:::composite_window(2023, 12)$t1, "2023-12-31")
})

test_that("composite_label names the window without claiming skipped months", {
  expect_equal(drift:::composite_label(2017, 6:7), "2017 Jun\u2013Jul")
  expect_equal(drift:::composite_label(2023, 8:9), "2023 Aug\u2013Sep")
  expect_equal(drift:::composite_label(2023, 7), "2023 Jul")
  expect_equal(drift:::composite_label(2023, c(8, 6)), "2023 Jun, Aug")
})

test_that("stac_composite_cache_key is deterministic and a 16-char hex", {
  expect_identical(ckey(), ckey())
  expect_match(ckey(), "^[0-9a-f]{16}$")
})

test_that("stac_composite_cache_key changes with every pixel-affecting parameter", {
  base <- ckey()
  variants <- list(
    ckey(bands = c("nir", "red", "green"), band_assets = c("B08", "B04", "B03")),
    ckey(bands = c("blue", "green", "red"), band_assets = c("B02", "B03", "B04")),
    ckey(months = 8:9, datetime = "2017-08-01/2017-09-30"),
    ckey(months = c(6L, 8L), datetime = "2017-06-01/2017-08-31", dt = "P3M"),
    ckey(datetime = "2023-06-01/2023-07-31"),
    ckey(res = 20), ckey(target_crs = "EPSG:32610"),
    ckey(aggregation = "mean"), ckey(resampling = "near"),
    ckey(cloud_cover_max = 60), ckey(mask_values = c(3L, 8L)),
    ckey(scale = 1), ckey(offset = 0), ckey(offset_before = -0.1),
    ckey(clip = FALSE), ckey(tile_size = 1000)
  )
  keys <- vapply(variants, identity, character(1))
  expect_false(any(keys == base))
  expect_equal(length(unique(keys)), length(keys))
})

test_that("stac_composite_cache_key ignores months and mask_values order", {
  expect_identical(ckey(months = 7:6), ckey())
  expect_identical(ckey(mask_values = c(11L, 10L, 9L, 8L, 3L)), ckey())
})

test_that("a composite key cannot equal a cube key over the same inputs", {
  a <- key_args()
  cube <- drift:::stac_cube_cache_key(
    a$aoi_target, a$res, a$target_crs, a$dt, a$aggregation, a$resampling,
    a$stac_url, a$collection, a$band_assets, a$datetime, "ndvi",
    a$cloud_cover_max, a$mask_values, a$scale, a$offset, a$months,
    a$offset_before, a$clip
  )
  expect_false(identical(cube, ckey()))
})

test_that("composite_band_assets resolves roles in order and refuses bad roles", {
  expect_equal(drift:::composite_band_assets(c("red", "green", "blue"), s2_roles),
               c("B04", "B03", "B02"))
  expect_equal(drift:::composite_band_assets(c("nir", "red", "green"), s2_roles),
               c("B08", "B04", "B03"))
  expect_error(drift:::composite_band_assets("swir22", s2_roles),
               "Unknown band role.*Available roles")
  expect_error(drift:::composite_band_assets("mask", s2_roles), "Unknown band role")
  expect_error(drift:::composite_band_assets(c("red", "red"), s2_roles), "distinct")
  expect_error(drift:::composite_band_assets(character(0), s2_roles), "distinct")
})

test_that("years and months are validated before any network call", {
  expect_error(drift:::composite_years_check(numeric(0)), "whole-number years")
  expect_error(drift:::composite_years_check(2017.5), "whole-number years")
  expect_error(drift:::composite_years_check(NA_real_), "whole-number years")
  expect_equal(drift:::composite_months_check(c(7, 6, 7)), c(6L, 7L))
  expect_error(drift:::composite_months_check(13), "1-12")
  expect_error(drift:::composite_months_check(0), "1-12")
  expect_error(drift:::composite_months_check(integer(0)), "1-12")
})

test_that("dft_stac_composite refuses a categorical source and bad input offline", {
  skip_if_not_installed("gdalcubes")
  aoi <- aoi_pkg()
  # rstac::stac is stubbed: reaching it would mean validation ran too late
  testthat::local_mocked_bindings(
    stac = function(...) stop("reached the network"), .package = "rstac"
  )
  expect_error(dft_stac_composite(aoi, years = 2017, source = "io-lulc"),
               "not a cube source")
  expect_error(dft_stac_composite(aoi, years = 2017, bands = "bogus"),
               "Unknown band role")
  expect_error(dft_stac_composite(aoi, years = 2017, months = 13), "1-12")
})

test_that("the composite pixel expression folds scale and offset into every band", {
  exprs <- vapply(c("B04", "B03", "B02"), drift:::scale_token, character(1),
                  scale = 1e-4, offset = -0.1, USE.NAMES = FALSE)
  expect_equal(exprs, c("(B04 * 0.0001 - 0.1)", "(B03 * 0.0001 - 0.1)",
                        "(B02 * 0.0001 - 0.1)"))
  # post-2022 DN 1500 is reflectance 0.05
  expect_equal(eval(parse(text = exprs[1]), list(B04 = 1500)), 0.05)
})

test_that("composite_window gives the STAC query explicit times so the last day counts", {
  # A date-only end bound is read as 00:00Z and drops that day's scenes, which in
  # BC land ~19:00Z (measured: 22 of 23 items for a window ending on a scene day).
  w <- drift:::composite_window(2021, 7:8)
  expect_equal(w$query, "2021-07-01T00:00:00Z/2021-08-31T23:59:59Z")
})

test_that("a window straddling the offset boundary is refused, not covered", {
  expect_error(
    drift:::composite_offset_check(c(TRUE, FALSE), "2022 Jan", "2022-01-25"),
    class = "drift_composite_offset_split"
  )
  expect_true(drift:::composite_offset_check(c(TRUE, TRUE), "2021 Jan", "2022-01-25"))
  expect_true(drift:::composite_offset_check(c(FALSE, FALSE), "2023 Jan", "2022-01-25"))
})

test_that("composite_layers_order selects layers by name, not position", {
  # terra reads gdalcubes' multi-variable NetCDF alphabetically (measured live:
  # blue, green, red), so position would swap red and blue.
  r <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 0)
  terra::values(r) <- cbind(rep(3, 4), rep(2, 4), rep(1, 4))
  names(r) <- c("blue", "green", "red")
  w <- drift:::composite_window(2017, 6:7)
  out <- drift:::composite_layers_order(r, c("red", "green", "blue"), "x", w)
  expect_equal(names(out), c("red", "green", "blue"))
  expect_equal(unname(unlist(terra::global(out, "max"))), c(1, 2, 3))
  expect_error(drift:::composite_layers_order(c(r, r), c("red", "green", "blue"), "x", w),
               "expected 3")
  expect_error(drift:::composite_layers_order(r, c("nir", "red", "green"), "x", w),
               "do not match")
})

test_that("an empty year is dropped with a warning and the others are kept", {
  skip_if_not_installed("gdalcubes")
  aoi <- aoi_pkg()
  cache <- tempfile("drift_composite_skip_")
  # 2017 has no scenes; 2018 is served from a seeded cache entry
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) {
      rlang::abort("No STAC items found for sentinel-2-l2a", class = "drift_no_items")
    }
  )
  seeded <- NULL
  testthat::local_mocked_bindings(
    stac_composite_cache_key = function(aoi_target, res, target_crs, datetime, ...) {
      if (startsWith(datetime, "2018")) "seeded2018000000" else "empty2017000000"
    }
  )
  dir <- drift:::cache_scheme_dir(cache, "sentinel-2-l2a")
  dir.create(dir, recursive = TRUE)
  r <- terra::rast(nrows = 4, ncols = 4, nlyrs = 3, vals = 0.1,
                   crs = "EPSG:32609", extent = c(0, 40, 0, 40))
  terra::writeRaster(r, file.path(dir, "composite_seeded2018000000.tif"))
  expect_warning(
    out <- suppressMessages(
      dft_stac_composite(aoi, years = c(2017, 2018), cache_dir = cache)
    ),
    "Skipping the 2017 Jun.Jul composite: no scenes"
  )
  expect_named(out, "2018 Jun\u2013Jul")
  expect_equal(names(out[[1]]), c("red", "green", "blue"))
  # every year empty is an error, not an empty list
  expect_error(
    suppressWarnings(suppressMessages(
      dft_stac_composite(aoi, years = 2017, cache_dir = cache)
    )),
    "No year produced a composite"
  )
})

test_that("dft_stac_composite returns a cached, cloud-masked true-colour COG", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "network test; set DRIFT_TEST_NETWORK=true to run")
  skip_if_not_installed("gdalcubes")
  aoi <- aoi_pkg()
  cache <- tempfile("drift_composite_")
  tc <- suppressMessages(dft_stac_composite(aoi, years = 2021, months = 7:8,
                                            cache_dir = cache))
  expect_named(tc, "2021 Jul\u2013Aug")
  r <- tc[[1]]
  expect_equal(terra::nlyr(r), 3)
  expect_equal(names(r), c("red", "green", "blue"))
  expect_equal(terra::time(r)[1], as.Date("2021-07-01"))
  v <- terra::values(r)
  # surface reflectance, not DN: summer land is well under 0.5 in the visible
  expect_gt(mean(!is.na(v)), 0.3)
  expect_lt(stats::median(v, na.rm = TRUE), 0.3)
  expect_gt(stats::median(v, na.rm = TRUE), 0)

  # every file, not a .tif pattern: a sidecar beside the COG must show up here
  all_files <- list.files(drift:::cache_scheme_dir(cache, "sentinel-2-l2a"),
                          all.files = TRUE, no.. = TRUE)
  expect_length(all_files, 1)
  expect_match(all_files, "^composite_[0-9a-f]{16}\\.tif$")
  f <- file.path(drift:::cache_scheme_dir(cache, "sentinel-2-l2a"), all_files)
  # A COG by its layout, not by an exit status: GDAL reports the layout in the
  # image structure metadata only for a file written as a COG.
  info <- paste(sf::gdal_utils("info", f, quiet = TRUE), collapse = "\n")
  expect_match(info, "LAYOUT=COG")
  # titiler masks only what the file declares as NoData
  expect_match(info, "NoData Value=")

  # second call is a cache hit and returns the same pixels
  msgs <- testthat::capture_messages(
    tc2 <- dft_stac_composite(aoi, years = 2021, months = 7:8, cache_dir = cache)
  )
  expect_true(any(grepl("cached", msgs)))
  expect_equal(terra::values(tc2[[1]]), v)
  expect_equal(names(tc2[[1]]), c("red", "green", "blue"))
})

test_that("false colour keeps band order: NIR is brightest over summer vegetation", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "network test; set DRIFT_TEST_NETWORK=true to run")
  skip_if_not_installed("gdalcubes")
  fc <- suppressMessages(dft_stac_composite(
    aoi_pkg(), years = 2021, months = 7:8, bands = c("nir", "red", "green"),
    cache_dir = tempfile("drift_composite_fc_")
  ))[[1]]
  med <- vapply(names(fc), function(b) {
    stats::median(terra::values(fc[[b]]), na.rm = TRUE)
  }, numeric(1))
  expect_equal(names(med), c("nir", "red", "green"))
  expect_gt(med[["nir"]], 2 * med[["red"]])
})

test_that("a missing gdalcubes names the GitHub install (#80)", {
  testthat::local_mocked_bindings(gdalcubes_available = function() FALSE)
  expect_error(dft_stac_composite(aoi_pkg(), years = 2023),
               "appelmar/gdalcubes", fixed = TRUE)
})

test_that("a built composite leaves only its COG in the cache, no sidecar", {
  # Drives the real build and write path offline: the STAC query and the
  # gdalcubes assembly are stubbed with a synthetic three-band stack. A time
  # stamped before a COG write makes terra emit a .aux.json that
  # cache_write_atomic() does not move, which strands under the temp name.
  skip_if_not_installed("gdalcubes")
  aoi <- aoi_pkg()
  aoi_t <- sf::st_transform(aoi, 32609)
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) list(features = list(), is_pre = logical(0)),
    stac_cube_assemble = function(...) {
      r <- terra::rast(terra::ext(aoi_t), resolution = 50, crs = "EPSG:32609",
                       nlyrs = 3)
      # distinct per band, so a build that renamed by position instead of
      # reordering by name would put 0.02 in red (code-check round 3)
      terra::values(r) <- matrix(rep(c(0.02, 0.05, 0.1), each = terra::ncell(r)),
                                 ncol = 3)
      names(r) <- c("blue", "green", "red")   # alphabetical, as terra reads it
      # and with a time, as terra reads the gdalcubes NetCDF: a fixture without
      # one cannot reach the sidecar (code-check round 2)
      terra::time(r) <- rep(as.Date("1970-01-01"), 3)
      r
    }
  )
  cache <- tempfile("drift_composite_build_")
  out <- suppressMessages(dft_stac_composite(aoi, years = 2023, cache_dir = cache))
  dir <- drift:::cache_scheme_dir(cache, "sentinel-2-l2a")
  files <- list.files(dir, all.files = TRUE, no.. = TRUE)
  expect_length(files, 1L)
  expect_match(files, "^composite_[0-9a-f]{16}\\.tif$")
  expect_equal(names(out[[1]]), c("red", "green", "blue"))
  expect_equal(unname(unlist(terra::global(out[[1]], "max"))), c(0.1, 0.05, 0.02),
               tolerance = 1e-6)
  expect_equal(terra::time(out[[1]])[1], as.Date("2023-06-01"))
})

test_that("dft_stac_composite refuses an aggregation outside the set drift passes (#92)", {
  skip_if_not_installed("gdalcubes")
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) stop("reached the network")
  )
  cache <- withr::local_tempdir()
  for (b in list("sum", "mode", NA_character_, c("median", "mean"), 1)) {
    expect_error(dft_stac_composite(aoi_pkg(), years = 2021, aggregation = b,
                                    cache_dir = cache),
                 class = "drift_bad_aggregation")
  }
  expect_length(list.files(cache, recursive = TRUE), 0L)
})

test_that("dft_stac_composite refuses a resampling gdalcubes would read as near (#96)", {
  skip_if_not_installed("gdalcubes")
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) stop("reached the network")
  )
  cache <- withr::local_tempdir()
  for (b in list("bilinaer", "median", NA_character_, c("near", "bilinear"), 1)) {
    expect_error(dft_stac_composite(aoi_pkg(), years = 2021, resampling = b,
                                    cache_dir = cache),
                 class = "drift_bad_resampling")
  }
  # a count refuses it too: the count path also reaches cube_view()
  expect_error(dft_stac_composite(aoi_pkg(), years = 2021, aggregation = "count",
                                  resampling = "bilinaer", cache_dir = cache),
               class = "drift_bad_resampling")
  expect_length(list.files(cache, recursive = TRUE), 0L)
})

# A local, dated Sentinel-2-shaped collection: one B04 and one SCL GeoTIFF per
# item, on an n x n grid at 10 m in EPSG:32609. `items` is a list of
# list(id, date, scl), `scl` a function of cell x/y returning SCL classes. Separate
# files per band: two-band files with one_band_per_file = FALSE segfaulted a
# gdalcubes 0.7.5 worker (#92).
count_fixture <- function(items, n = 4) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  for (it in items) {
    r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * 10, ymin = 0,
                     ymax = n * 10, crs = "EPSG:32609")
    xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
    b <- r
    terra::values(b) <- 500
    s <- r
    terra::values(s) <- it$scl(xy[, 1], xy[, 2])
    stem <- file.path(d, paste0(format(as.Date(it$date), "%Y%m%d"), "_", it$id))
    terra::writeRaster(b, paste0(stem, "_B04.tif"), datatype = "INT2U")
    terra::writeRaster(s, paste0(stem, "_SCL.tif"), datatype = "INT1U")
  }
  # gdalcubes collection format, written literally (jsonlite is not a dependency)
  fmt_file <- file.path(d, "format.json")
  writeLines(c(
    '{"description": "drift #92 fixture", "tags": ["test"],',
    ' "pattern": ".*\\\\.tif",',
    ' "images": {"pattern": ".*/([0-9]{8}_[a-z]+)_.*"},',
    ' "datetime": {"pattern": ".*/([0-9]{8})_.*", "format": "%Y%m%d"},',
    ' "bands": {"B04": {"pattern": ".*_B04\\\\.tif", "nodata": 0},',
    '           "SCL": {"pattern": ".*_SCL\\\\.tif"}}}'
  ), fmt_file)
  col <- gdalcubes::create_image_collection(
    list.files(d, pattern = "\\.tif$", full.names = TRUE), format = fmt_file,
    out_file = file.path(d, "col.db")
  )
  list(col = col, n = n)
}

# Run the count path's reduction over a fixture: the same view settings and the
# same helpers dft_stac_composite() uses for aggregation = "count".
count_run <- function(fx, chunking = NULL, t0 = "2021-07-01",
                      t1 = "2021-07-31", aggregation = "first") {
  v <- gdalcubes::cube_view(
    srs = "EPSG:32609",
    extent = list(left = 0, right = fx$n * 10, bottom = 0, top = fx$n * 10,
                  t0 = t0, t1 = t1),
    dx = 10, dy = 10, dt = "P1D", aggregation = aggregation,
    resampling = "near"
  )
  m <- gdalcubes::image_mask("SCL", values = c(3, 8, 9, 10, 11))
  cube <- if (is.null(chunking)) {
    gdalcubes::raster_cube(fx$col, v, mask = m)
  } else {
    gdalcubes::raster_cube(fx$col, v, mask = m, chunking = chunking)
  }
  tmp <- withr::local_tempfile(fileext = ".nc", .local_envir = parent.frame())
  gdalcubes::write_ncdf(drift:::composite_count_cube(cube, "B04", "red"), tmp)
  drift:::count_zero_na(terra::rast(tmp))
}

test_that("the count path counts clear DAYS, not items or reflectance (#92)", {
  skip_if_not_installed("gdalcubes")
  clear <- function(x, y) rep(4, length(x))
  cloud <- function(x, y) rep(8, length(x))
  left_clear <- function(x, y) ifelse(x < 20, 4, 9)
  fx <- count_fixture(list(
    # same day, two tiles, both clear: one acquisition, counted once
    list(id = "a", date = "2021-07-03", scl = clear),
    list(id = "b", date = "2021-07-03", scl = clear),
    list(id = "a", date = "2021-07-08", scl = cloud),
    list(id = "a", date = "2021-07-13", scl = left_clear),
    # same day: tile a cloudy, tile b clear. Under the #92 "none" aggregation
    # the masked item overwrote the clear one; the count must keep it.
    list(id = "a", date = "2021-07-18", scl = cloud),
    list(id = "b", date = "2021-07-18", scl = clear)
  ))
  r <- count_run(fx)
  expect_equal(names(r), "red")
  v <- terra::values(r)[, 1]
  x <- terra::xyFromCell(r, seq_len(terra::ncell(r)))[, 1]
  # left half clear on 07-03, 07-13, 07-18; right half on 07-03, 07-18
  expect_equal(unique(v[x < 20]), 3)
  expect_equal(unique(v[x > 20]), 2)
  # whole numbers of days, not reflectance and not a scaled count
  expect_true(all(v == round(v)))
  # the day-level aggregation does not change the count: every one skips NaN
  for (agg in c("max", "median")) {
    expect_equal(terra::values(count_run(fx, aggregation = agg))[, 1], v)
  }
})

test_that("a pixel with no clear day is NA at every chunking (#92)", {
  skip_if_not_installed("gdalcubes")
  # 128 x 128: clear only in a left strip, and in a corner on a second day.
  # Raw gdalcubes gives a zero-clear pixel 0 or NaN depending on whether its
  # chunk holds a clear pixel; count_zero_na() must make the two agree.
  fx <- count_fixture(list(
    list(id = "a", date = "2021-07-05", scl = function(x, y) ifelse(x < 300, 4, 8)),
    list(id = "a", date = "2021-07-10",
         scl = function(x, y) ifelse(x < 300 & y < 300, 4, 8)),
    list(id = "a", date = "2021-07-15", scl = function(x, y) rep(8, length(x)))
  ), n = 128)
  coarse <- count_run(fx, chunking = c(16, 256, 256))
  fine <- count_run(fx, chunking = c(16, 64, 64))
  expect_equal(terra::values(fine), terra::values(coarse))
  v <- terra::values(coarse)[, 1]
  expect_false(any(v == 0, na.rm = TRUE))
  expect_equal(sum(is.na(v)), 128^2 - 30 * 128)
  expect_equal(sort(unique(stats::na.omit(v))), c(1, 2))
})

test_that("dft_stac_composite(aggregation = 'count') reads daily, unsplit, and caches integers (#92)", {
  skip_if_not_installed("gdalcubes")
  aoi <- aoi_pkg()
  aoi_t <- sf::st_transform(aoi, 32609)
  seen <- NULL
  queried <- NULL
  testthat::local_mocked_bindings(
    # a straddling window: the composite would refuse it; a count must not
    stac_cube_items = function(cfg, aoi_wgs84, datetime, cloud_cover_max,
                               months, sign_fn) {
      queried <<- list(datetime = datetime, cloud_cover_max = cloud_cover_max,
                       months = months)
      list(features = list(), is_pre = c(TRUE, FALSE, FALSE))
    },
    stac_cube_assemble = function(fetched, cfg, aoi_target, target_crs, t0, t1,
                                  res, dt, aggregation, resampling, band_assets,
                                  mask_values, offset, offset_before, pixel_fn,
                                  ...) {
      seen <<- list(is_pre = fetched$is_pre, dt = dt, aggregation = aggregation,
                    t0 = t0, t1 = t1, band_assets = band_assets,
                    pixel_fn = pixel_fn, offset = offset,
                    resampling = resampling, mask_values = mask_values)
      r <- terra::rast(terra::ext(aoi_t), resolution = 50, crs = "EPSG:32609")
      terra::values(r) <- rep_len(c(0, 1, 2, 5), terra::ncell(r))
      names(r) <- "red"
      terra::time(r) <- as.Date("1970-01-01")
      r
    }
  )
  cache <- withr::local_tempdir()
  # non-default mask, cloud cover and resampling: for a count the mask defines
  # "clear", so what the caller passes must be what the read uses
  out <- suppressMessages(dft_stac_composite(
    aoi, years = 2022, months = 1, bands = "red", aggregation = "count",
    mask_values = c(3L, 8L, 9L), cloud_cover_max = 55, resampling = "near",
    cache_dir = cache
  ))
  expect_equal(queried$datetime, "2022-01-01T00:00:00Z/2022-01-31T23:59:59Z")
  expect_equal(queried$months, 1L)
  expect_equal(queried$cloud_cover_max, 55)
  expect_equal(seen$mask_values, c(3L, 8L, 9L))
  expect_equal(seen$resampling, "near")
  expect_equal(seen$aggregation, "first")
  expect_equal(seen$dt, "P1D")
  expect_false(any(seen$is_pre))
  expect_equal(c(seen$t0, seen$t1), c("2022-01-01", "2022-01-31"))
  # the pixel function the build hands to gdalcubes is the day count, not the
  # reflectance expression: run it on a fixture cube and read the result
  expect_equal(seen$band_assets, "B04")
  fx <- count_fixture(list(
    list(id = "a", date = "2021-07-03", scl = function(x, y) rep(4, length(x))),
    list(id = "a", date = "2021-07-09", scl = function(x, y) rep(4, length(x))),
    list(id = "a", date = "2021-07-15", scl = function(x, y) rep(9, length(x)))
  ))
  v <- gdalcubes::cube_view(
    srs = "EPSG:32609",
    extent = list(left = 0, right = 40, bottom = 0, top = 40,
                  t0 = "2021-07-01", t1 = "2021-07-31"),
    dx = 10, dy = 10, dt = "P1D", aggregation = "first", resampling = "near"
  )
  cube <- gdalcubes::raster_cube(
    fx$col, v, mask = gdalcubes::image_mask("SCL", values = c(3, 8, 9, 10, 11))
  )
  nc <- withr::local_tempfile(fileext = ".nc")
  gdalcubes::write_ncdf(seen$pixel_fn(cube, seen$offset), nc)
  pix <- terra::rast(nc)
  expect_equal(names(pix), "red")
  expect_equal(unique(terra::values(pix)[, 1]), 2)
  dir <- drift:::cache_scheme_dir(cache, "sentinel-2-l2a")
  files <- list.files(dir, all.files = TRUE, no.. = TRUE)
  expect_length(files, 1L)
  expect_match(files, "^count_[0-9a-f]{16}\\.tif$")
  r <- out[[1]]
  expect_equal(names(r), "red")
  expect_equal(terra::datatype(terra::rast(file.path(dir, files))), "INT2U")
  v <- terra::values(r)[, 1]
  # zeros are NA; counts are the whole numbers written
  expect_false(any(v == 0, na.rm = TRUE))
  expect_setequal(stats::na.omit(v), c(1, 2, 5))
  # served from the count cache on a second call, not rebuilt
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) stop("rebuilt instead of served")
  )
  again <- suppressMessages(dft_stac_composite(
    aoi, years = 2022, months = 1, bands = "red", aggregation = "count",
    mask_values = c(3L, 8L, 9L), cloud_cover_max = 55, resampling = "near",
    cache_dir = cache
  ))
  expect_equal(terra::values(again[[1]]), terra::values(r))
})

test_that("a count COG takes its overviews by nearest cell, so they are still counts (#92)", {
  skip_if_not_installed("gdalcubes")
  # Wider than one 512 px block, so the COG writer builds overviews. A 1/5
  # checkerboard averages to 3, which no cell holds; nearest keeps 1 or 5.
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) list(features = list(), is_pre = FALSE),
    stac_cube_assemble = function(...) {
      r <- terra::rast(nrows = 1100, ncols = 1100, xmin = 0, xmax = 11000,
                       ymin = 0, ymax = 11000, crs = "EPSG:32609")
      cells <- seq_len(terra::ncell(r))
      terra::values(r) <- ifelse(
        (terra::rowFromCell(r, cells) + terra::colFromCell(r, cells)) %% 2 == 0,
        1, 5
      )
      names(r) <- "red"
      r
    }
  )
  cache <- withr::local_tempdir()
  suppressMessages(dft_stac_composite(aoi_pkg(), years = 2021, bands = "red",
                                      aggregation = "count", cache_dir = cache))
  f <- list.files(drift:::cache_scheme_dir(cache, "sentinel-2-l2a"),
                  full.names = TRUE)
  ov <- terra::rast(f, opts = "OVERVIEW_LEVEL=0")
  expect_lt(terra::ncol(ov), 1100)
  expect_true(all(terra::values(ov)[, 1] %in% c(1, 5)))
})

test_that("a count with no clear day anywhere drops the year, never caches zeros (#92)", {
  skip_if_not_installed("gdalcubes")
  aoi <- aoi_pkg()
  aoi_t <- sf::st_transform(aoi, 32609)
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) list(features = list(), is_pre = FALSE),
    stac_cube_assemble = function(...) {
      r <- terra::rast(terra::ext(aoi_t), resolution = 50, crs = "EPSG:32609",
                       vals = 0)
      names(r) <- "red"
      r
    }
  )
  cache <- withr::local_tempdir()
  expect_error(
    expect_warning(
      suppressMessages(dft_stac_composite(aoi, years = 2021, bands = "red",
                                          aggregation = "count",
                                          cache_dir = cache)),
      "no clear pixels"
    ),
    "No year produced"
  )
  expect_length(list.files(cache, pattern = "\\.tif$", recursive = TRUE), 0L)
})

test_that("the count keys apart from every composite, and composite keys are unchanged (#92)", {
  # pinned against v0.19.2: the family argument must not move an existing key.
  # (That callers hand the key function the caller's case is tested in
  # test-dft_stac_cube.R, through the exported functions.)
  expect_identical(ckey(), "03ee8ecc66b832a8")
  expect_identical(ckey(aggregation = "Median"), "150c8ca5003bbe78")
  count <- ckey(aggregation = "count", dt = "P1D", family = "count")
  # 0.18.0-0.19.2 wrote reflectance under this key for aggregation = "count"
  expect_false(identical(count, "08e0c5510e8ae297"))
  expect_false(identical(count, ckey(aggregation = "count")))
  # the tag alone separates the families
  expect_false(identical(ckey(family = "count"), ckey()))
  expect_identical(count, ckey(aggregation = "count", dt = "P1D",
                               family = "count"))
})

test_that("a live count is whole clear days, at most the distinct dates, and not reflectance (#92)", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "network test; set DRIFT_TEST_NETWORK=true to run")
  skip_if_not_installed("gdalcubes")
  # A 2 km square at the packaged AOI's centroid, July 2023, cloudy scenes
  # admitted so the mask has work to do. Measured 2026-09-30: 20 items on 12
  # dates (overlapping MGRS tiles), counts 5-9.
  ctr <- sf::st_centroid(sf::st_union(sf::st_transform(aoi_pkg(), 32609)))
  sq <- sf::st_as_sf(sf::st_buffer(ctr, 1000, endCapStyle = "SQUARE"))
  cache <- withr::local_tempdir()
  n <- suppressMessages(dft_stac_composite(
    sq, years = 2023, months = 7, bands = "red", aggregation = "count",
    res = 20, cloud_cover_max = 100, cache_dir = cache
  ))[[1]]
  v <- terra::values(n)[, 1]
  # the distinct acquisition dates the same query returns
  items <- rstac::stac("https://planetarycomputer.microsoft.com/api/stac/v1") |>
    rstac::stac_search(
      collections = "sentinel-2-l2a",
      intersects = sf::st_geometry(sf::st_transform(sq, 4326))[[1]],
      datetime = "2023-07-01T00:00:00Z/2023-07-31T23:59:59Z", limit = 500
    ) |>
    rstac::ext_filter(`eo:cloud_cover` <= 100) |>
    rstac::post_request() |>
    rstac::items_fetch()
  dates <- unique(substr(vapply(items$features,
                                function(f) f$properties$datetime, ""), 1, 10))
  expect_gt(length(dates), 1)
  expect_true(all(v == round(v), na.rm = TRUE))
  expect_gte(min(v, na.rm = TRUE), 1)
  expect_lte(max(v, na.rm = TRUE), length(dates))
  # the #92 value was reflectance, median ~0.03-0.04; a count is at least 1
  expect_gte(stats::median(v, na.rm = TRUE), 1)
  f <- list.files(drift:::cache_scheme_dir(cache, "sentinel-2-l2a"),
                  full.names = TRUE)
  expect_match(basename(f), "^count_[0-9a-f]{16}\\.tif$")
  expect_equal(terra::datatype(terra::rast(f)), "INT2U")
})

test_that("a count is matched without case and keys as 'count' (#92)", {
  skip_if_not_installed("gdalcubes")
  aoi_t <- sf::st_transform(aoi_pkg(), 32609)
  seen <- NULL
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) list(features = list(), is_pre = FALSE),
    stac_cube_assemble = function(fetched, cfg, aoi_target, target_crs, t0, t1,
                                  res, dt, aggregation, ...) {
      seen <<- c(seen, aggregation)
      r <- terra::rast(terra::ext(aoi_t), resolution = 50, crs = "EPSG:32609",
                       vals = 3)
      names(r) <- "red"
      r
    }
  )
  cache <- withr::local_tempdir()
  for (a in c("COUNT", "count")) {
    suppressMessages(dft_stac_composite(aoi_pkg(), years = 2021, bands = "red",
                                        aggregation = a, cache_dir = cache))
  }
  # the upper-case call took the count path; the lower-case one hit its cache
  expect_equal(seen, "first")
  files <- list.files(drift:::cache_scheme_dir(cache, "sentinel-2-l2a"))
  expect_length(files, 1L)
  expect_match(files, "^count_")
})


# --- #87: a failed chunk read aborts and caches nothing ----------------------
#
# The real gdalcubes writer over a local collection (chunk_fixture(), in
# helper-gdalcubes.R) whose 2021-07-13 image is deleted after the collection is
# built: the read fails the way an expired signed URL does. Only the STAC query
# and the collection constructor are stubbed, so stac_cube_assemble(), the
# write, the guard and the cache publish all run as in production. At
# parallel = 4, because the default resolves to 1 on a two-core runner, and the
# fill value an unvisited chunk keeps (which the guard must read as OK) is the
# worker path's.

# The fixture's extent: the packaged AOI's bbox in its UTM zone, widened to whole
# cells and a margin so every cube_view drift builds over it lies inside.
aoi_fixture_ext <- function(aoi) {
  bb <- sf::st_bbox(sf::st_transform(aoi, 32609))
  c(floor(bb[["xmin"]] / 10) * 10 - 20, ceiling(bb[["xmax"]] / 10) * 10 + 20,
    floor(bb[["ymin"]] / 10) * 10 - 20, ceiling(bb[["ymax"]] / 10) * 10 + 20)
}

# `break_dates` holds one entry per year: the dates to break in that year's
# collection. Years are 2021, 2022, ...; each has scenes on 07-03 and 07-13.
composite_on_fixture <- function(break_dates, tile_size = NULL, cache,
                                 env = parent.frame()) {
  aoi <- aoi_pkg()
  years <- 2020 + seq_along(break_dates)
  cols <- lapply(seq_along(years), function(i) {
    chunk_fixture(paste0(years[i], c("-07-03", "-07-13")),
                  ext = aoi_fixture_ext(aoi), break_dates = break_dates[[i]],
                  envir = env)
  })
  year_now <- 0L
  testthat::local_mocked_bindings(
    stac_cube_items = function(...) {
      year_now <<- year_now + 1L
      list(features = list(list(id = "a"), list(id = "b")),
           is_pre = rep(years[year_now] < 2022, 2))
    },
    .env = env
  )
  testthat::local_mocked_bindings(
    stac_image_collection = function(...) cols[[year_now]],
    .package = "gdalcubes", .env = env
  )
  suppressMessages(dft_stac_composite(aoi, years = years, months = 7,
                                      bands = "red", tile_size = tile_size,
                                      parallel = 4, cache_dir = cache))
}

test_that("a composite whose chunk reads failed aborts and caches nothing (#87)", {
  skip_if_not_installed("gdalcubes")
  cache <- withr::local_tempdir()
  expect_error(composite_on_fixture(list("2021-07-13"), cache = cache),
               class = "drift_incomplete_cube")
  expect_length(list.files(cache, recursive = TRUE, all.files = TRUE), 0L)
})

test_that("a tiled composite whose chunk reads failed aborts and caches nothing (#87)", {
  skip_if_not_installed("gdalcubes")
  cache <- withr::local_tempdir()
  expect_error(composite_on_fixture(list("2021-07-13"), tile_size = 1000,
                                    cache = cache),
               class = "drift_incomplete_cube")
  expect_length(list.files(cache, recursive = TRUE, all.files = TRUE), 0L)
})

test_that("a composite over a readable collection is built and cached as before (#87)", {
  # False-refusal control: the guard must not fire on a clean read, tiled or not.
  skip_if_not_installed("gdalcubes")
  for (ts in list(NULL, 1000)) {
    cache <- withr::local_tempdir()
    out <- composite_on_fixture(list(character(0)), tile_size = ts,
                                cache = cache)
    expect_s4_class(out[[1]], "SpatRaster")
    expect_gt(sum(terra::global(out[[1]], "notNA")$notNA), 0)
    expect_length(list.files(cache, pattern = "\\.tif$", recursive = TRUE), 1L)
  }
})

test_that("a failed year is an abort, not a skipped year (#87)", {
  # The year loop turns drift_no_items and drift_empty_cube into a warning and a
  # dropped year. A holed read must not take that exit: it would return the
  # other years as though the window simply had no scenes.
  skip_if_not_installed("gdalcubes")
  cache <- withr::local_tempdir()
  expect_error(
    composite_on_fixture(list(character(0), "2022-07-13"), cache = cache),
    class = "drift_incomplete_cube"
  )
  # year 1 was built before year 2 failed, and stays cached; year 2 does not
  expect_length(list.files(cache, pattern = "\\.tif$", recursive = TRUE), 1L)
})

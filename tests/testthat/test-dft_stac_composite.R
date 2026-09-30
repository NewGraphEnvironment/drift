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

test_that("dft_stac_composite refuses an aggregation gdalcubes would not honour (#92)", {
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

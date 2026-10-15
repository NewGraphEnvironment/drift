wb_config_json <- function(entries) {
  jsonlite::toJSON(entries, auto_unbox = TRUE)
}

wb_entry <- function(date, meta = "https://metadata.example/World_Imagery_Metadata_x/MapServer") {
  list(itemTitle = paste0("World Imagery (Wayback ", date, ")"),
       metadataLayerUrl = meta)
}

test_that("releases are sorted by date, not by id", {
  json <- wb_config_json(list(
    "500" = wb_entry("2026-09-24"),
    "10" = wb_entry("2017-11-16"),
    "25521" = wb_entry("2014-02-20")
  ))
  testthat::local_mocked_bindings(wayback_get = function(url, ...) json)
  rel <- dft_wayback_releases()
  expect_s3_class(rel, "tbl_df")
  # by numeric id this would be 10, 500, 25521; as strings 10, 25521, 500
  expect_identical(rel$release_id, c("25521", "10", "500"))
  expect_s3_class(rel$release_date, "Date")
  expect_identical(format(rel$release_date),
                   c("2014-02-20", "2017-11-16", "2026-09-24"))
  expect_identical(names(rel), c("release_id", "release_date", "meta_url"))
})

test_that("a release with no parseable date aborts rather than dropping", {
  json <- wb_config_json(list(
    "1" = wb_entry("2017-11-16"),
    "2" = list(itemTitle = "World Imagery (Wayback)",
               metadataLayerUrl = "https://m.example/MapServer")
  ))
  testthat::local_mocked_bindings(wayback_get = function(url, ...) json)
  expect_error(dft_wayback_releases(), "lack a parseable date")
})

test_that("an impossible date aborts", {
  json <- wb_config_json(list("1" = wb_entry("2017-13-40")))
  testthat::local_mocked_bindings(wayback_get = function(url, ...) json)
  expect_error(dft_wayback_releases(), "lack a parseable date")
})

test_that("a release with no metadata URL aborts", {
  json <- wb_config_json(list(
    "1" = wb_entry("2017-11-16"),
    "2" = list(itemTitle = "World Imagery (Wayback 2018-01-08)")
  ))
  testthat::local_mocked_bindings(wayback_get = function(url, ...) json)
  expect_error(dft_wayback_releases(), "metadata URL")
})

test_that("wayback_get raises a classed error on a non-200", {
  testthat::local_mocked_bindings(
    curl_fetch_memory = function(url, handle) {
      list(status_code = 500L, content = charToRaw("err"))
    },
    .package = "curl"
  )
  expect_error(wayback_get("https://x.example/a", tries = 1L),
               class = "drift_wayback_http")
})

test_that("the live configuration parses", {
  skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true",
          "set DRIFT_TEST_NETWORK=true to run network tests")
  rel <- dft_wayback_releases()
  expect_gt(nrow(rel), 150)
  expect_false(is.unsorted(rel$release_date))
  expect_true(all(grepl("^https://", rel$meta_url)))
})

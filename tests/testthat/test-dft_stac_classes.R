test_that("dft_class_table loads io-lulc CSV", {
  tbl <- dft_class_table("io-lulc")
  expect_s3_class(tbl, "tbl_df")
  expect_true(all(c("code", "class_name", "color", "description") %in% names(tbl)))
  expect_true(nrow(tbl) >= 9)
  expect_true(2L %in% tbl$code)  # Trees
  expect_true(all(grepl("^#", tbl$color)))
})

test_that("dft_class_table loads esa-worldcover CSV", {
  tbl <- dft_class_table("esa-worldcover")
  expect_s3_class(tbl, "tbl_df")
  expect_true(nrow(tbl) >= 11)
  expect_true(10L %in% tbl$code)  # Tree cover
})

test_that("dft_class_table errors on unknown source", {
  expect_error(dft_class_table("bogus"))
})

test_that("dft_stac_classes falls back to CSV when items is NULL", {
  tbl <- dft_stac_classes(items = NULL, source = "io-lulc")
  expect_s3_class(tbl, "tbl_df")
  expect_true(nrow(tbl) >= 9)
})

test_that("stac_classes_from_items returns NULL for empty items", {
  items <- list(features = list())
  result <- drift:::stac_classes_from_items(items)
  expect_null(result)
})

test_that("stac_classes_from_items parses classification:classes", {
  items <- list(features = list(
    list(properties = list(
      `classification:classes` = list(
        list(value = 1, description = "Water", `color-hint` = "419bdf"),
        list(value = 2, description = "Trees", `color-hint` = "397d49")
      )
    ))
  ))
  result <- drift:::stac_classes_from_items(items)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2)
  expect_equal(result$code, c(1L, 2L))
  expect_equal(result$class_name, c("Water", "Trees"))
  expect_equal(result$color, c("#419bdf", "#397d49"))
})

test_that("format_color handles various inputs", {
  expect_equal(drift:::format_color("#ff0000"), "#ff0000")
  expect_equal(drift:::format_color("ff0000"), "#ff0000")
  expect_true(is.na(drift:::format_color(NA_character_)))
})

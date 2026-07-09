# S2 role map (Planetary Computer band names) used across the resolver tests
s2_roles <- list(red = "B04", nir = "B08", swir16 = "B11", mask = "SCL")

test_that("dft_index_table ships ndvi, kndvi, ndmi with formulas over roles", {
  tbl <- dft_index_table()
  expect_s3_class(tbl, "tbl_df")
  expect_named(tbl, c("index", "formula", "roles", "description"))
  expect_true(all(c("ndvi", "kndvi", "ndmi") %in% tbl$index))
  # kNDVI must use tinyexpr pow(), never R's ^ (which gdalcubes cannot parse)
  kndvi <- tbl$formula[tbl$index == "kndvi"]
  expect_match(kndvi, "pow\\(")
  expect_false(grepl("\\^", kndvi))
})

test_that("kNDVI resolves over S2 roles with scale/offset folded in", {
  expr <- drift:::index_resolve_expr("kndvi", s2_roles, scale = 1e-4, offset = -0.1)
  expect_equal(
    expr,
    paste0(
      "tanh(pow(((B08 * 0.0001 - 0.1) - (B04 * 0.0001 - 0.1)) / ",
      "((B08 * 0.0001 - 0.1) + (B04 * 0.0001 - 0.1)), 2))"
    )
  )
})

test_that("identity scale/offset yields bare asset tokens (no affine)", {
  expr <- drift:::index_resolve_expr("ndvi", s2_roles, scale = 1, offset = 0)
  expect_equal(expr, "(B08 - B04) / (B08 + B04)")
})

test_that("non-zero offset appears in the expression (ratio-on-DN guard)", {
  # Landsat C2 L2 affine: scale 2.75e-5, offset -0.2 must not cancel in a ratio
  landsat_roles <- list(red = "red", nir = "nir08", swir16 = "swir16")
  expr <- drift:::index_resolve_expr("ndvi", landsat_roles,
                                     scale = 2.75e-5, offset = -0.2)
  expect_match(expr, "red * 0.0000275 - 0.2", fixed = TRUE)
  expect_match(expr, "nir08 * 0.0000275 - 0.2", fixed = TRUE)
})

test_that("ndmi resolves swir16 -> its asset", {
  expr <- drift:::index_resolve_expr("ndmi", s2_roles, scale = 1, offset = 0)
  expect_equal(expr, "(B08 - B11) / (B08 + B11)")
})

test_that("index_roles reports the roles an index needs", {
  expect_setequal(drift:::index_roles("kndvi"), c("nir", "red"))
  expect_setequal(drift:::index_roles("ndmi"), c("nir", "swir16"))
})

test_that("unknown index errors with the available set", {
  expect_error(drift:::index_resolve_expr("bogus", s2_roles), "Unknown index")
  expect_error(drift:::index_roles("bogus"), "Unknown index")
})

test_that("an index needing an absent role errors", {
  # ndmi needs swir16; a role map without it must fail loudly
  expect_error(
    drift:::index_resolve_expr("ndmi", list(red = "B04", nir = "B08")),
    "role"
  )
})

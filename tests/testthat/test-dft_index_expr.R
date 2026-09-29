# S2 role map (Planetary Computer band names) used across the resolver tests
s2_roles <- list(red = "B04", green = "B03", blue = "B02", nir = "B08",
                 swir16 = "B11", mask = "SCL")

# Evaluate a resolved expression in R over named band values. The water indices
# are plain arithmetic, so R and tinyexpr agree on them; this checks the NUMBER
# the formula produces, not just its string.
eval_expr <- function(expr, bands) eval(parse(text = expr), as.list(bands))

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


test_that("dft_index_table ships ndwi and mndwi over green", {
  tbl <- dft_index_table()
  expect_true(all(c("ndwi", "mndwi") %in% tbl$index))
  expect_setequal(drift:::index_roles("ndwi"), c("green", "nir"))
  expect_setequal(drift:::index_roles("mndwi"), c("green", "swir16"))
})

test_that("ndwi and mndwi give the hand-computed value on known reflectance", {
  # Open water: green 0.10, nir 0.03, swir16 0.01 -> both strongly positive.
  # Vegetation: green 0.10, nir 0.30, swir16 0.20 -> both negative.
  water <- c(B03 = 0.10, B08 = 0.03, B11 = 0.01)
  veg   <- c(B03 = 0.10, B08 = 0.30, B11 = 0.20)
  ndwi  <- drift:::index_resolve_expr("ndwi", s2_roles, scale = 1, offset = 0)
  mndwi <- drift:::index_resolve_expr("mndwi", s2_roles, scale = 1, offset = 0)
  expect_equal(ndwi, "(B03 - B08) / (B03 + B08)")
  expect_equal(mndwi, "(B03 - B11) / (B03 + B11)")
  expect_equal(eval_expr(ndwi, water), (0.10 - 0.03) / (0.10 + 0.03))
  expect_equal(eval_expr(ndwi, veg), -0.5)
  expect_equal(eval_expr(mndwi, water), (0.10 - 0.01) / (0.10 + 0.01))
  expect_equal(eval_expr(mndwi, veg), -1 / 3)
})

test_that("ndwi applies the S2 offset per band, so DN input gives reflectance output", {
  # Post-2022 S2 DN = reflectance * 1e4 + 1000. Feeding those DNs through the
  # scale/offset-folded expression must return the same value as the
  # reflectance above; computing it on raw DN would not (the offset does not
  # cancel in a ratio), which is the defect the affine folding exists to stop.
  dn <- c(B03 = 0.10 * 1e4 + 1000, B08 = 0.30 * 1e4 + 1000)
  expr <- drift:::index_resolve_expr("ndwi", s2_roles, scale = 1e-4, offset = -0.1)
  expect_equal(eval_expr(expr, dn), -0.5)
  raw <- drift:::index_resolve_expr("ndwi", s2_roles, scale = 1, offset = 0)
  expect_false(isTRUE(all.equal(eval_expr(raw, dn), -0.5)))
})

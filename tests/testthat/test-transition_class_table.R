# transition_class_table(): where dft_rast_transition() and
# dft_rast_break_class() get their labels (#19). Precedence: class_table >
# source > the rasters' own factor levels > error.

label_rast <- function(m, ids = NULL, labs = NULL) {
  r <- artifact_class_rast(m)
  if (!is.null(ids)) {
    terra::set.cats(r, layer = 1, value = data.frame(id = ids, class_name = labs))
  }
  r
}

m2 <- matrix(c(101L, 102L, 101L, 103L), 2)

test_that("class_table wins over source and over the levels", {
  r <- label_rast(m2, c(101L, 102L, 103L), c("a", "b", "c"))
  ct <- tibble::tibble(code = 101:103, class_name = c("x", "y", "z"), color = "#000000")
  out <- transition_class_table(list(r, r), class_table = ct, source = "io-lulc")
  expect_equal(out$class_name, c("x", "y", "z"))
})

test_that("an explicit source wins over the levels", {
  r <- label_rast(matrix(c(1L, 2L, 1L, 2L), 2), 1:2, c("a", "b"))
  out <- transition_class_table(list(r, r), source = "io-lulc")
  expect_equal(out$class_name[match(1:2, out$code)], c("Water", "Trees"))
})

test_that("factor levels are read when neither class_table nor source is given", {
  r <- label_rast(m2, c(101L, 102L, 103L), c("Bog", "Fen", "Marsh"))
  out <- transition_class_table(list(r, r))
  expect_equal(out$code, 101:103)
  expect_equal(out$class_name, c("Bog", "Fen", "Marsh"))
})

test_that("levels are the union across rasters", {
  # dft_rast_classify() keeps only the codes present in each year
  a <- label_rast(m2, c(101L, 102L), c("Bog", "Fen"))
  b <- label_rast(m2, c(102L, 103L), c("Fen", "Marsh"))
  out <- transition_class_table(list(a, b))
  expect_equal(out$code, 101:103)
  expect_equal(out$class_name, c("Bog", "Fen", "Marsh"))
})

test_that("one code labelled differently in two rasters is an error", {
  a <- label_rast(m2, c(101L, 102L), c("Bog", "Fen"))
  b <- label_rast(m2, c(101L, 102L), c("Bog", "Swamp"))
  expect_error(transition_class_table(list(a, b)), "102.*Fen.*Swamp")
})

test_that("a raster without levels and no class_table/source is an error", {
  raw <- label_rast(m2)
  expect_error(transition_class_table(list(raw, raw), fn = "f"),
               "dft_rast_classify")
  expect_error(transition_class_table(list(raw, raw), fn = "f"), "set.cats")
})

test_that("a mix of factor and plain rasters names the plain one", {
  a <- label_rast(m2, c(101L, 102L, 103L), c("Bog", "Fen", "Marsh"))
  raw <- label_rast(m2)
  expect_error(transition_class_table(list("2017" = a, "2023" = raw)), "2023")
})

test_that("a factor with zero levels counts as unlabelled", {
  e <- label_rast(m2)
  terra::set.cats(e, layer = 1,
                  value = data.frame(id = integer(0), class_name = character(0)))
  expect_true(terra::is.factor(e))
  expect_error(transition_class_table(list(e, e)), "dft_rast_classify")
})

test_that("the active category of a multi-column table supplies the labels", {
  r <- artifact_class_rast(m2)
  terra::set.cats(r, layer = 1, value = data.frame(
    id = 101:103, abbrev = c("B", "F", "M"), long = c("Bog", "Fen", "Marsh")
  ))
  terra::activeCat(r) <- 2
  out <- transition_class_table(list(r, r))
  expect_equal(out$class_name, c("Bog", "Fen", "Marsh"))
})

test_that("codes the from * 1000 + to encoding cannot hold are an error", {
  ct <- tibble::tibble(code = c(1L, 1000L), class_name = c("a", "b"), color = "#000000")
  expect_error(transition_class_table(list(), class_table = ct), "0.*999")
  ct$code <- c(-1L, 2L)
  expect_error(transition_class_table(list(), class_table = ct), "0.*999")
  ct$code <- c(1.5, 2)
  expect_error(transition_class_table(list(), class_table = ct), "0.*999")
  r <- label_rast(matrix(c(1L, 1200L, 1L, 1200L), 2), c(1L, 1200L), c("a", "b"))
  expect_error(transition_class_table(list(r, r)), "1200")
})

test_that("dft_rast_transition returns raster and summary", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")

  expect_type(result, "list")
  expect_named(result, c("raster", "summary", "removed"))
  expect_s4_class(result$raster, "SpatRaster")
  expect_s3_class(result$summary, "tbl_df")
  expect_true(terra::is.factor(result$raster))
})

test_that("summary has expected columns and positive values", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  s <- result$summary

  expect_true(all(c("from_class", "to_class", "n_cells", "area", "pct") %in% names(s)))
  expect_true(all(s$n_cells > 0))
  expect_true(all(s$area > 0))
  expect_true(all(s$pct > 0))
})

test_that("pct sums to 100", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  expect_equal(sum(result$summary$pct), 100, tolerance = 0.1)
})

test_that("from_class filter works", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                from_class = "Trees")

  expect_true(all(result$summary$from_class == "Trees"))
})

test_that("to_class filter works", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                to_class = c("Crops", "Rangeland", "Bare Ground"))

  expect_true(all(result$summary$to_class %in% c("Crops", "Rangeland", "Bare Ground")))
})

test_that("both from_class and to_class filter together", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                from_class = "Trees",
                                to_class = "Rangeland")

  if (nrow(result$summary) > 0) {
    expect_true(all(result$summary$from_class == "Trees"))
    expect_true(all(result$summary$to_class == "Rangeland"))
  }
})

test_that("impossible filter returns empty summary", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                from_class = "NONEXISTENT_CLASS")

  expect_equal(nrow(result$summary), 0)
})

test_that("unit parameter works", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  ha <- dft_rast_transition(classified, from = "2017", to = "2020", unit = "ha")
  km2 <- dft_rast_transition(classified, from = "2017", to = "2020", unit = "km2")

  # ha should be 100x km2
  expect_equal(ha$summary$area[1] / km2$summary$area[1], 100, tolerance = 0.01)
})

test_that("errors on single SpatRaster", {
  r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  expect_error(dft_rast_transition(r, from = "2017", to = "2020"),
               "named list")
})

test_that("errors on missing layer name", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  expect_error(dft_rast_transition(classified, from = "2017", to = "2099"),
               "2099")
})

test_that("transition labels use arrow format", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  lvls <- terra::cats(result$raster)[[1]]

  expect_true(all(grepl(" -> ", lvls$transition)))
})

test_that("summary is sorted by n_cells descending", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  s <- result$summary

  if (nrow(s) > 1) {
    expect_true(all(diff(s$n_cells) <= 0))
  }
})

# --- patch_area_min tests ---

test_that("patch_area_min = NULL preserves current behavior", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result_default <- dft_rast_transition(classified, from = "2017", to = "2020")
  result_null <- dft_rast_transition(classified, from = "2017", to = "2020",
                                     patch_area_min = NULL)

  expect_equal(result_default$summary, result_null$summary)
})

test_that("patch_area_min = 0 preserves current behavior", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result_default <- dft_rast_transition(classified, from = "2017", to = "2020")
  result_zero <- dft_rast_transition(classified, from = "2017", to = "2020",
                                     patch_area_min = 0)

  expect_equal(result_default$summary, result_zero$summary)
})

test_that("patch_area_min removes small patches", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  no_filter <- dft_rast_transition(classified, from = "2017", to = "2020")
  filtered <- dft_rast_transition(classified, from = "2017", to = "2020",
                                  patch_area_min = 500)

  # Filtered should have fewer or equal transition cells
  expect_lte(sum(filtered$summary$n_cells), sum(no_filter$summary$n_cells))
  # Filtered area should be less
  expect_lt(sum(filtered$summary$area), sum(no_filter$summary$area))
})

test_that("larger patch_area_min removes more patches", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  small <- dft_rast_transition(classified, from = "2017", to = "2020",
                               patch_area_min = 500)
  large <- dft_rast_transition(classified, from = "2017", to = "2020",
                               patch_area_min = 5000)

  expect_lte(sum(large$summary$n_cells), sum(small$summary$n_cells))
})

test_that("patch_area_min filters raster and summary consistently", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                patch_area_min = 1000)

  # Raster non-NA count should equal summary n_cells total
  rast_count <- sum(!is.na(terra::values(result$raster)[, 1]))
  summary_count <- sum(result$summary$n_cells)
  expect_equal(rast_count, summary_count)
})

test_that("pct still sums to ~100 with patch_area_min", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                patch_area_min = 1000)

  expect_equal(sum(result$summary$pct), 100, tolerance = 0.5)
})

test_that("patch_area_min works with from_class/to_class filters", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                from_class = "Trees",
                                patch_area_min = 500)

  # Should still only have Trees in from_class
  if (nrow(result$summary) > 0) {
    expect_true(all(result$summary$from_class == "Trees"))
  }
})

test_that("very large patch_area_min removes all changes", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  # 1e9 m² is larger than any patch — removes all changes
  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                patch_area_min = 1e9)

  # All transitions should be same-class (no actual changes survive)
  if (nrow(result$summary) > 0) {
    expect_true(all(result$summary$from_class == result$summary$to_class))
  }
})

test_that("patch_area_min returns valid structure", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                patch_area_min = 500)

  expect_type(result, "list")
  expect_named(result, c("raster", "summary", "removed"))
  expect_s4_class(result$raster, "SpatRaster")
  expect_s3_class(result$summary, "tbl_df")
  expect_true(terra::is.factor(result$raster))
})

test_that("patch_area_min validation catches bad input", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  expect_error(dft_rast_transition(classified, from = "2017", to = "2020",
                                   patch_area_min = -1),
               "non-negative")
  expect_error(dft_rast_transition(classified, from = "2017", to = "2020",
                                   patch_area_min = "500"),
               "non-negative")
  expect_error(dft_rast_transition(classified, from = "2017", to = "2020",
                                   patch_area_min = c(100, 200)),
               "non-negative")
  expect_error(dft_rast_transition(classified, from = "2017", to = "2020",
                                   patch_area_min = NA_real_),
               "non-negative")
})

# --- $removed raster tests ---

test_that("removed is NULL when no filtering applied", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020")
  expect_null(result$removed)
})

test_that("removed is NULL when patch_area_min = 0", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                patch_area_min = 0)
  expect_null(result$removed)
})

test_that("removed is a SpatRaster when patches are filtered", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  result <- dft_rast_transition(classified, from = "2017", to = "2020",
                                patch_area_min = 500)
  expect_s4_class(result$removed, "SpatRaster")
  expect_true(terra::is.factor(result$removed))
})

test_that("removed + raster account for all transition pixels", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  # Unfiltered count of changed pixels
  unfiltered <- dft_rast_transition(classified, from = "2017", to = "2020")
  v_unf <- terra::values(unfiltered$raster)[, 1]
  v_from <- terra::values(classified[["2017"]])[, 1]
  v_to <- terra::values(classified[["2020"]])[, 1]
  n_changed_unfiltered <- sum(!is.na(v_unf) & (v_from != v_to))

  # Filtered
  filtered <- dft_rast_transition(classified, from = "2017", to = "2020",
                                  patch_area_min = 500)
  v_filt <- terra::values(filtered$raster)[, 1]
  v_rem <- terra::values(filtered$removed)[, 1]
  n_kept <- sum(!is.na(v_filt) & (v_from != v_to))
  n_removed <- sum(!is.na(v_rem))

  expect_equal(n_kept + n_removed, n_changed_unfiltered)
})

# Golden-output contract for the #34 terra-native rewrite. Captures the full
# behavior (summary tibble + raster factor levels/frequencies + removed raster)
# across the parameter matrix as a snapshot, so the memory rewrite can be proven
# byte-identical. Digest is canonicalized (sorted) so it pins content, not the
# internal cell/tie order.
test_that("dft_rast_transition output is stable across the terra-native rewrite (#34)", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

  # both helpers normalize the empty/all-NA raster (cats()[[1]] is NULL and
  # freq() errors there) to a canonical empty frame so old and new agree.
  freq_df <- function(r) {
    f <- tryCatch(terra::freq(r), error = function(e) NULL)
    if (is.null(f) || nrow(f) == 0) {
      return(data.frame(value = character(0), count = integer(0)))
    }
    f <- f[!is.na(f$value), c("value", "count"), drop = FALSE]
    f <- f[order(as.character(f$value)), , drop = FALSE]
    rownames(f) <- NULL
    f
  }
  cats_df <- function(r) {
    ct <- terra::cats(r)[[1]]
    if (is.null(ct) || nrow(ct) == 0) {
      return(data.frame(id = integer(0), transition = character(0)))
    }
    ct <- ct[order(ct$id), , drop = FALSE]
    rownames(ct) <- NULL
    ct
  }
  digest <- function(res) {
    summ <- as.data.frame(
      res$summary[order(res$summary$from_class, res$summary$to_class), , drop = FALSE]
    )
    rownames(summ) <- NULL
    list(
      summary     = summ,
      raster_cats = cats_df(res$raster),
      raster_freq = freq_df(res$raster),
      removed     = if (is.null(res$removed)) "NULL"
                    else list(cats = cats_df(res$removed), freq = freq_df(res$removed))
    )
  }

  cases <- list(
    default      = list(),
    from_trees   = list(from_class = "Trees"),
    both_filters = list(from_class = "Trees",
                        to_class = c("Crops", "Rangeland", "Bare Ground")),
    pmin_0       = list(patch_area_min = 0),
    pmin_500     = list(patch_area_min = 500),
    pmin_1000    = list(patch_area_min = 1000),
    pmin_huge    = list(patch_area_min = 1e9),
    impossible   = list(from_class = "NoSuchClass")
  )

  digests <- lapply(cases, function(args) {
    res <- do.call(dft_rast_transition,
                   c(list(classified, from = "2017", to = "2020"), args))
    digest(res)
  })

  expect_snapshot_value(digests, style = "serialize", tolerance = 1e-8)
})

# --- #19: labels come from class_table, source, or the rasters' own levels ----

custom_factor <- function(m, ids, labs) {
  r <- artifact_class_rast(m)
  terra::set.cats(r, layer = 1, value = data.frame(id = ids, class_name = labs))
  r
}

test_that("raw integers with no class_table or source are an error (#19)", {
  x <- list(a = artifact_class_rast(matrix(c(1L, 2L, 1L, 2L), 2)),
            b = artifact_class_rast(matrix(c(2L, 2L, 1L, 1L), 2)))
  err <- expect_error(dft_rast_transition(x, from = "a", to = "b"))
  expect_match(conditionMessage(err), "dft_rast_classify")
  expect_match(conditionMessage(err), "set.cats")
})

test_that("raw integers with an explicit source still decode (#19)", {
  x <- list(a = artifact_class_rast(matrix(c(1L, 2L, 1L, 2L), 2)),
            b = artifact_class_rast(matrix(c(2L, 2L, 1L, 1L), 2)))
  res <- dft_rast_transition(x, from = "a", to = "b", source = "io-lulc")
  expect_setequal(res$summary$from_class, c("Water", "Trees"))
})

test_that("a factor with its own codes and labels needs no class_table (#19)", {
  m_from <- matrix(c(101L, 101L, 102L, 103L), 2)
  m_to   <- matrix(c(101L, 102L, 102L, 101L), 2)
  ids <- 101:103
  labs <- c("Bog", "Fen", "Marsh")
  x <- list(a = custom_factor(m_from, ids, labs), b = custom_factor(m_to, ids, labs))
  res <- dft_rast_transition(x, from = "a", to = "b")
  expect_false(anyNA(res$summary$from_class))
  expect_false(anyNA(res$summary$to_class))
  expect_setequal(paste(res$summary$from_class, res$summary$to_class),
                  c("Bog Bog", "Bog Fen", "Fen Fen", "Marsh Bog"))
  expect_setequal(terra::cats(res$raster)[[1]]$transition,
                  c("Bog -> Bog", "Bog -> Fen", "Fen -> Fen", "Marsh -> Bog"))
  # filters take the level names
  bog <- dft_rast_transition(x, from = "a", to = "b", from_class = "Bog", to_class = "Fen")
  expect_equal(bog$summary$n_cells, 1L)
})

test_that("a remap-classified pair is labelled by its own levels (#19)", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
  cl <- dft_rast_classify(list("2017" = r17, "2023" = r23), source = "io-lulc",
                          remap = list(Vegetation = c("Trees", "Rangeland")))
  res <- dft_rast_transition(cl, from = "2017", to = "2023")
  expect_true("Vegetation" %in% res$summary$from_class)
  expect_false(any(c("Trees", "Rangeland") %in% c(res$summary$from_class,
                                                  res$summary$to_class)))
  veg <- dft_rast_transition(cl, from = "2017", to = "2023", from_class = "Vegetation")
  expect_gt(nrow(veg$summary), 0)
})

test_that("class_table and an explicit source each win over the levels (#19)", {
  m <- matrix(c(1L, 2L, 1L, 2L), 2)
  x <- list(a = custom_factor(m, 1:2, c("p", "q")), b = custom_factor(m, 1:2, c("p", "q")))
  ct <- tibble::tibble(code = 1:2, class_name = c("One", "Two"), color = "#000000")
  expect_setequal(dft_rast_transition(x, "a", "b", class_table = ct)$summary$from_class,
                  c("One", "Two"))
  expect_setequal(dft_rast_transition(x, "a", "b", source = "io-lulc")$summary$from_class,
                  c("Water", "Trees"))
  # and the caller's rasters keep their own levels
  expect_equal(terra::levels(x$a)[[1]]$class_name, c("p", "q"))
})

cols_artifact <- c("width_m", "width_px", "flag_sliver",
                   "boundary_frac", "flag_boundary",
                   "reciprocal_id", "reciprocal_dist_m", "flag_reciprocal")

# ---- fixture premises ------------------------------------------------------

test_that("fixtures produce the patches the tests reason about", {
  a <- dft_transition_vectors(artifact_fixture_shift()$raster, changes_only = TRUE)
  expect_identical(nrow(a), 1L)
  expect_identical(a$transition, "Trees -> Rangeland")
  expect_equal(a$area_ha * 1e4 / 100, 40)

  b <- dft_transition_vectors(artifact_fixture_river()$raster, changes_only = TRUE)
  expect_identical(nrow(b), 2L)
  expect_setequal(b$transition, c("Water -> Trees", "Trees -> Water"))
  expect_equal(b$area_ha * 1e4 / 100, c(40, 40))

  c <- dft_transition_vectors(artifact_fixture_road()$raster, changes_only = TRUE)
  expect_identical(nrow(c), 4L)
  expect_identical(sum(c$transition == "Trees -> Rangeland"), 2L)
  expect_identical(sum(c$transition == "Trees -> Bare"), 1L)
  expect_identical(sum(c$transition == "Rangeland -> Bare"), 1L)

  d <- dft_transition_vectors(artifact_fixture_blob()$raster, changes_only = TRUE)
  expect_identical(nrow(d), 1L)
  # to-classes of C and D exist in the from epoch (see helper-artifact.R)
  expect_true("Bare -> Bare" %in% terra::cats(artifact_fixture_road()$raster)[[1]]$transition)
  expect_true("Rangeland -> Rangeland" %in%
                terra::cats(artifact_fixture_blob()$raster)[[1]]$transition)
  expect_equal(d$area_ha * 1e4 / 100, 400)
})

# ---- width -----------------------------------------------------------------

test_that("effective width 2A/P reproduces known shapes in metres and pixels", {
  from <- matrix(2L, nrow = 40, ncol = 40)

  to <- from
  to[5, 5] <- 3L                                  # single pixel
  px1 <- make_transition(from, to)
  a1 <- dft_transition_artifact(
    dft_transition_vectors(px1$raster, changes_only = TRUE), px1$raster
  )
  expect_equal(a1$width_m, 5)
  expect_equal(a1$width_px, 0.5)

  to <- from
  to[5, 1:20] <- 3L                               # 1 x 20 sliver
  sl <- make_transition(from, to)
  a2 <- dft_transition_artifact(
    dft_transition_vectors(sl$raster, changes_only = TRUE), sl$raster
  )
  expect_equal(a2$width_px, 2 * 2000 / 420 / 10, tolerance = 1e-6)
  expect_equal(round(a2$width_px, 2), 0.95)

  blob <- artifact_fixture_blob()                 # 20 x 20 blob
  a3 <- dft_transition_artifact(
    dft_transition_vectors(blob$raster, changes_only = TRUE), blob$raster
  )
  expect_equal(a3$width_m, 100)
  expect_equal(a3$width_px, 10)
})

test_that("width_max sets flag_sliver and is respected when changed", {
  res <- artifact_fixture_shift()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)

  out <- dft_transition_artifact(p, res$raster)
  expect_true(out$flag_sliver)
  expect_lt(out$width_px, 1)

  strict <- dft_transition_artifact(p, res$raster, width_max = 0.9)
  expect_false(strict$flag_sliver)
})

# ---- one-sided shift (Fixture A) ----------------------------------------------

test_that("a one-sided 1-px boundary shift is a boundary-hugging sliver with no partner", {
  res <- artifact_fixture_shift()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  out <- dft_transition_artifact(p, res$raster)

  expect_s3_class(out, "sf")
  expect_true(all(cols_artifact %in% names(out)))
  expect_identical(nrow(out), 1L)
  expect_true(out$flag_sliver)
  expect_equal(out$boundary_frac, 1)
  expect_true(out$flag_boundary)
  expect_true(is.na(out$reciprocal_id))
  expect_true(is.na(out$reciprocal_dist_m))
  expect_false(out$flag_reciprocal)
})

test_that("boundary_dist_max widens the interface: a 2-px band goes 0.5 -> 1", {
  from <- artifact_base_from()
  to <- from
  to[, 19:20] <- 3L                                # 2-px Trees -> Rangeland band
  res <- make_transition(from, to)
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  expect_identical(nrow(p), 1L)

  d1 <- dft_transition_artifact(p, res$raster, boundary_dist_max = 1)
  d2 <- dft_transition_artifact(p, res$raster, boundary_dist_max = 2)
  expect_equal(d1$boundary_frac, 0.5)
  expect_equal(d2$boundary_frac, 1)
  expect_true(d1$flag_boundary)     # the rule is >= 0.5, so exactly 0.5 flags
  expect_true(d2$flag_boundary)
})

# ---- reciprocal river shift (Fixture B) --------------------------------------

test_that("opposite-bank bands 4 px apart are reciprocal partners of each other", {
  res <- artifact_fixture_river()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  out <- dft_transition_artifact(p, res$raster)

  expect_true(all(out$flag_sliver))
  expect_true(all(out$flag_boundary))
  expect_equal(out$boundary_frac, c(1, 1))
  expect_true(all(out$flag_reciprocal))
  wt <- out[out$transition == "Water -> Trees", ]
  tw <- out[out$transition == "Trees -> Water", ]
  expect_identical(wt$reciprocal_id, tw$patch_id)
  expect_identical(tw$reciprocal_id, wt$patch_id)
  expect_equal(out$reciprocal_dist_m, c(40, 40))
})

test_that("reciprocal_dist_max below the channel width finds no partner", {
  res <- artifact_fixture_river()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  out <- dft_transition_artifact(p, res$raster, reciprocal_dist_max = 3)

  expect_false(any(out$flag_reciprocal))
  expect_true(all(is.na(out$reciprocal_id)))
  expect_true(all(is.na(out$reciprocal_dist_m)))
  # the other signatures are untouched
  expect_true(all(out$flag_sliver))
  expect_true(all(out$flag_boundary))
})

test_that("reciprocal_area_ratio_min rejects a partner of incomparable area", {
  res <- artifact_fixture_river(to_rows = 1:10)     # Trees -> Water is 10 cells
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  expect_equal(sort(p$area_ha * 1e4 / 100), c(10, 40))

  out <- dft_transition_artifact(p, res$raster)     # ratio 0.25 < 0.5
  expect_false(any(out$flag_reciprocal))
  expect_true(all(is.na(out$reciprocal_id)))

  loose <- dft_transition_artifact(p, res$raster, reciprocal_area_ratio_min = 0.2)
  expect_true(all(loose$flag_reciprocal))
})

test_that("reciprocal = FALSE skips the pairwise step and returns NA columns", {
  res <- artifact_fixture_river()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  out <- dft_transition_artifact(p, res$raster, reciprocal = FALSE)

  expect_true(all(cols_artifact %in% names(out)))
  expect_true(all(is.na(out$reciprocal_id)))
  expect_true(all(is.na(out$reciprocal_dist_m)))
  expect_true(all(is.na(out$flag_reciprocal)))
  expect_true(all(out$flag_sliver))
})

# ---- a real thin change crossing the boundary (Fixture C) --------------------

test_that("a road cutting across classes is a sliver but not boundary-hugging", {
  res <- artifact_fixture_road()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  out <- dft_transition_artifact(p, res$raster)

  road <- out[out$transition %in% c("Trees -> Bare", "Rangeland -> Bare"), ]
  band <- out[out$transition == "Trees -> Rangeland", ]
  expect_identical(nrow(road), 2L)
  expect_identical(nrow(band), 2L)

  # the discriminator: both are thin ...
  expect_true(all(road$flag_sliver))
  expect_true(all(band$flag_sliver))
  # ... but only the shift band traces a pre-existing interface. Bare exists in
  # the from epoch (a stable block under the road's western end), so these are
  # geometric fractions, not "to-class absent": 4 of 20 Trees -> Bare cells sit
  # within one cell of that block, no Rangeland -> Bare cell does.
  tb <- road[road$transition == "Trees -> Bare", ]
  rb <- road[road$transition == "Rangeland -> Bare", ]
  expect_equal(tb$boundary_frac, 4 / 20)
  expect_equal(rb$boundary_frac, 0)
  expect_false(any(road$flag_boundary))
  expect_equal(band$boundary_frac, c(1, 1))
  expect_true(all(band$flag_boundary))
  expect_false(any(out$flag_reciprocal))
})

# ---- a real wide change (Fixture D) ------------------------------------------

test_that("an interior clearing carries no flags", {
  res <- artifact_fixture_blob()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  out <- dft_transition_artifact(p, res$raster)

  expect_false(out$flag_sliver)
  expect_equal(out$boundary_frac, 0)
  expect_false(out$flag_boundary)
  expect_false(out$flag_reciprocal)
})

# ---- stable rows, empty input, schema ----------------------------------------

test_that("stable (from == to) patches get width only; the rest is NA", {
  res <- artifact_fixture_shift()
  p <- dft_transition_vectors(res$raster)            # includes stable patches
  out <- dft_transition_artifact(p, res$raster)

  stable <- out[out$transition %in% c("Trees -> Trees", "Rangeland -> Rangeland"), ]
  expect_identical(nrow(stable), 2L)
  expect_false(anyNA(stable$width_m))
  expect_false(anyNA(stable$flag_sliver))
  expect_true(all(is.na(stable$boundary_frac)))
  expect_true(all(is.na(stable$flag_boundary)))
  expect_true(all(is.na(stable$reciprocal_id)))
  expect_true(all(is.na(stable$reciprocal_dist_m)))
  expect_true(all(is.na(stable$flag_reciprocal)))

  # the change row is still fully evaluated alongside them
  band <- out[out$transition == "Trees -> Rangeland", ]
  expect_equal(band$boundary_frac, 1)
  expect_true(band$flag_boundary)
})

test_that("input columns and row order are preserved", {
  res <- artifact_fixture_road()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  p$note <- letters[seq_len(nrow(p))]
  out <- dft_transition_artifact(p, res$raster)

  expect_identical(out$patch_id, p$patch_id)
  expect_identical(out$note, p$note)
  expect_identical(names(out)[seq_len(ncol(p) - 1)],
                   setdiff(names(p), attr(p, "sf_column")))
  expect_identical(sf::st_geometry(out), sf::st_geometry(p))
})

test_that("zero-row patches return the full typed schema", {
  res <- artifact_fixture_shift()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)[0, ]
  out <- dft_transition_artifact(p, res$raster)

  expect_s3_class(out, "sf")
  expect_identical(nrow(out), 0L)
  expect_true(all(cols_artifact %in% names(out)))
  expect_type(out$width_m, "double")
  expect_type(out$width_px, "double")
  expect_type(out$flag_sliver, "logical")
  expect_type(out$boundary_frac, "double")
  expect_type(out$flag_boundary, "logical")
  expect_type(out$reciprocal_id, "integer")
  expect_type(out$reciprocal_dist_m, "double")
  expect_type(out$flag_reciprocal, "logical")
})

test_that("column types match between the populated and zero-row paths", {
  res <- artifact_fixture_river()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  full <- sf::st_drop_geometry(dft_transition_artifact(p, res$raster))
  empty <- sf::st_drop_geometry(dft_transition_artifact(p[0, ], res$raster))
  expect_identical(vapply(full[cols_artifact], typeof, ""),
                   vapply(empty[cols_artifact], typeof, ""))
})

# ---- bundled data --------------------------------------------------------------

test_that("bundled 2017->2023 tile: 75 of 93 change patches are under 1.5 px wide", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2023" = r23), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2023")
  p <- dft_transition_vectors(result$raster, changes_only = TRUE)
  expect_identical(nrow(p), 93L)

  out <- dft_transition_artifact(p, result$raster)
  expect_identical(nrow(out), 93L)
  expect_identical(sum(out$width_px < 1.5), 75L)
  expect_identical(sum(out$flag_sliver), 75L)
  # slivers are most of the patches but a minority of the area (issue #44)
  expect_lt(sum(out$area_ha[out$flag_sliver]) / sum(out$area_ha), 0.25)
  expect_true(all(out$boundary_frac >= 0 & out$boundary_frac <= 1))
})

test_that("bundled tile: a Trees -> Rangeland sliver survives patch_area_min = 5000", {
  r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
  r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
  classified <- dft_rast_classify(list("2017" = r17, "2023" = r23), source = "io-lulc")
  result <- dft_rast_transition(classified, from = "2017", to = "2023")
  p <- dft_transition_vectors(result$raster, changes_only = TRUE,
                              patch_area_min = 5000)
  out <- dft_transition_artifact(p, result$raster)

  sliver <- out[out$flag_sliver, ]
  expect_identical(nrow(sliver), 1L)
  expect_identical(sliver$transition, "Trees -> Rangeland")
  expect_equal(sliver$area_ha, 0.75)
  expect_equal(round(sliver$width_px, 2), 1.44)
})

test_that("does not pull in lwgeom (sf::st_perimeter would, on projected data)", {
  if ("lwgeom" %in% loadedNamespaces()) try(unloadNamespace("lwgeom"), silent = TRUE)
  skip_if("lwgeom" %in% loadedNamespaces())    # could not unload; nothing to prove
  res <- artifact_fixture_river()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  out <- dft_transition_artifact(p, res$raster)
  expect_false("lwgeom" %in% loadedNamespaces())
  expect_equal(out$width_px, c(2 * 4000 / 820 / 10, 2 * 4000 / 820 / 10))
})

test_that("levels table is read by position for the id, by name for the label", {
  res <- artifact_fixture_shift()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)
  ct <- terra::cats(res$raster)[[1]]
  r2 <- res$raster
  names(ct)[1] <- "value"                        # a user raster's id column name
  terra::set.cats(r2, layer = 1, value = ct)
  out <- dft_transition_artifact(p, r2)
  expect_equal(out$boundary_frac, 1)

  ct2 <- ct
  names(ct2)[2] <- "label"
  terra::set.cats(r2, layer = 1, value = ct2)
  # "level column" pins THIS guard; a bare "transition" also matches the
  # unknown-label abort that fires when the guard is deleted (round-3 review)
  expect_error(dft_transition_artifact(p, r2), "level column")
})

# ---- validation ----------------------------------------------------------------

test_that("errors on bad inputs", {
  res <- artifact_fixture_shift()
  p <- dft_transition_vectors(res$raster, changes_only = TRUE)

  expect_error(dft_transition_artifact(data.frame(x = 1), res$raster), "sf")
  expect_error(dft_transition_artifact(p, "not a raster"), "SpatRaster")
  expect_error(dft_transition_artifact(p, res$raster * 1L), "factor")

  p_missing <- p
  p_missing$transition <- NULL
  expect_error(dft_transition_artifact(p_missing, res$raster), "transition")

  dup <- rbind(p, p)
  expect_error(dft_transition_artifact(dup, res$raster), "patch_id")

  p_3005 <- sf::st_transform(p, 3005)
  expect_error(dft_transition_artifact(p_3005, res$raster), "CRS")

  other <- artifact_fixture_blob()
  p_other <- dft_transition_vectors(other$raster, changes_only = TRUE)
  p_other$transition <- "Bare -> Water"           # label absent from the raster's levels
  expect_error(dft_transition_artifact(p_other, other$raster), "levels")

  expect_error(dft_transition_artifact(p, res$raster, width_max = -1), "width_max")
  expect_error(dft_transition_artifact(p, res$raster, width_max = "a"), "width_max")
  expect_error(dft_transition_artifact(p, res$raster, boundary_dist_max = 0.5),
               "boundary_dist_max")
  expect_error(dft_transition_artifact(p, res$raster, reciprocal = NA), "reciprocal")
  expect_error(dft_transition_artifact(p, res$raster, reciprocal_dist_max = -1),
               "reciprocal_dist_max")
  expect_error(dft_transition_artifact(p, res$raster, reciprocal_area_ratio_min = 2),
               "reciprocal_area_ratio_min")
})

tile <- function(yr = 2017) {
  terra::rast(system.file("extdata", paste0("example_", yr, ".tif"),
                          package = "drift"))
}
r17 <- tile(2017)
# classes 4 and 9 have 2 cells each on this tile, so n = 5 censuses them
alloc <- 5
draw <- function(...) suppressMessages(dft_accuracy_sample(...))

test_that("a seeded draw is pinned: same seed, same points, on any terra", {
  s <- draw(r17, n = alloc, seed = 81)
  # Golden values. If this fails, the draw moved: a change to the RNG
  # handling, the stream seeds, cell order, or the resolver -- every stored
  # sample.gpkg drawn before the change no longer redraws. Do not re-pin
  # without saying so in NEWS.
  expect_identical(
    s$points$cell[s$points$stratum == 2],
    c(33234, 46009, 26228, 28183, 27211)
  )
  expect_identical(utils::head(s$points$point_id, 3),
                   c("1_00001", "1_00002", "1_00003"))
  expect_identical(draw(r17, n = alloc, seed = 81)$points$cell, s$points$cell)
  expect_false(identical(draw(r17, n = alloc, seed = 82)$points$cell,
                         s$points$cell))
})

test_that("strata carry counts, areas and weights that match the raster", {
  s <- draw(r17, n = alloc, seed = 1)
  tab <- table(terra::values(r17)[, 1])
  expect_identical(s$strata$stratum, as.numeric(names(tab)))
  expect_equal(s$strata$n_cells, as.vector(tab))
  expect_equal(sum(s$strata$weight), 1)
  summ <- dft_rast_summarize(r17, source = "io-lulc", unit = "ha")
  expect_equal(sum(s$strata$area), sum(summ$area))
  expect_equal(s$strata$n, pmin(alloc, as.vector(tab)))
  expect_true(all(is.na(s$strata$stratum_label)))
})

test_that("points fall in their stratum, never on NA, one per cell", {
  s <- draw(r17, n = 30, seed = 3)
  v <- terra::values(r17)[s$points$cell, 1]
  expect_false(anyNA(v))
  expect_equal(v, s$points$stratum)
  expect_false(anyDuplicated(s$points$cell) > 0)
  expect_false(anyDuplicated(s$points$point_id) > 0)
  xy <- sf::st_coordinates(s$points)
  expect_equal(terra::cellFromXY(r17, xy), s$points$cell)
  expect_identical(sf::st_crs(s$points)$wkt, sf::st_crs(terra::crs(r17))$wkt)
})

test_that("the chunked resolver matches brute force at every chunk size", {
  # the tile fits one default chunk, so force the block-boundary carry
  ref <- draw(r17, n = 30, seed = 7)
  for (rows in c(1L, 7L, 50L, 314L)) {
    withr::local_options(drift.accuracy_rows_chunk = rows)
    got <- draw(r17, n = 30, seed = 7)
    expect_identical(got$points$cell, ref$points$cell, info = paste("rows", rows))
    expect_identical(got$strata, ref$strata, info = paste("rows", rows))
  }
  # brute force: the k-th cell of a stratum in cell order is which(v == h)[k],
  # so the drawn ranks, resolved by which(), must give exactly these cells
  v <- terra::values(r17)[, 1]
  ranks <- drift:::accuracy_draw(ref$strata$stratum, ref$strata$n_cells,
                                 ref$strata$n, seed = 7)
  for (i in seq_along(ranks)) {
    h <- ref$strata$stratum[i]
    expect_identical(ref$points$cell[ref$points$stratum == h],
                     as.numeric(which(v == h)[ranks[[i]]]),
                     info = paste("stratum", h))
  }
})

test_that("a larger n extends the pilot, and other strata do not move", {
  s30 <- draw(r17, n = 30, seed = 11)
  s50 <- draw(r17, n = 50, seed = 11)
  for (h in s30$strata$stratum) {
    a <- s30$points[s30$points$stratum == h, ]
    b <- s50$points[s50$points$stratum == h, ]
    k <- nrow(a)
    expect_identical(b$cell[seq_len(k)], a$cell, info = paste("stratum", h))
    expect_identical(b$point_id[seq_len(k)], a$point_id, info = paste("stratum", h))
  }
  # raising one stratum's n leaves the others' draws alone
  n1 <- stats::setNames(rep(30, nrow(s30$strata)), s30$strata$stratum)
  n1["11"] <- 60
  s_mix <- draw(r17, n = n1, seed = 11)
  keep <- s30$points$stratum != 11
  expect_identical(s_mix$points$cell[s_mix$points$stratum != 11],
                   s30$points$cell[keep])
})

test_that("a stratum tipped into a census by a larger n keeps its pilot ids", {
  # a 40-cell stratum: drawn at n = 30, taken whole at n = 50
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100, ymin = 0,
                   ymax = 100, crs = "EPSG:32609",
                   vals = rep(c(1, 2), times = c(40, 60)))
  p30 <- draw(r, n = 30, seed = 81)
  p50 <- draw(r, n = 50, seed = 81)
  a <- p30$points[p30$points$stratum == 1, ]
  b <- p50$points[p50$points$stratum == 1, ]
  expect_equal(nrow(b), 40)
  expect_identical(b$cell[match(a$point_id, b$point_id)], a$cell)
})

test_that("the caller's RNG state is restored, or left absent", {
  set.seed(123)
  before <- .Random.seed
  draw(r17, n = alloc, seed = 1)
  expect_identical(.Random.seed, before)

  withr::local_seed(1)   # restored at the end of this test
  rm(".Random.seed", envir = globalenv())
  draw(r17, n = alloc, seed = 1)
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))

  set.seed(5, kind = "L'Ecuyer-CMRG")
  kind_before <- RNGkind()
  seed_before <- .Random.seed
  s1 <- draw(r17, n = alloc, seed = 1)
  expect_identical(RNGkind(), kind_before)
  expect_identical(.Random.seed, seed_before)
  # and the caller's generator kind does not change the draw
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rounding"))
  expect_identical(suppressWarnings(draw(r17, n = alloc, seed = 1))$points$cell,
                   s1$points$cell)
  RNGkind("default", "default", "default")
})

test_that("a stratum no larger than its allocation is taken whole, with a message", {
  expect_message(s <- dft_accuracy_sample(r17, n = alloc, seed = 1),
                 "census.*4 \\(2\\), 9 \\(2\\)")
  expect_equal(s$strata$n[s$strata$stratum %in% c(4, 9)], c(2, 2))
  expect_identical(s$design$census, c(4, 9))
})

test_that("a factor transition raster keeps codes as stratum and labels alongside", {
  cl <- dft_rast_classify(list("2017" = tile(2017), "2023" = tile(2023)),
                          source = "io-lulc")
  tr <- dft_rast_transition(cl, from = "2017", to = "2023")$raster
  s <- draw(tr, n = 4, seed = 2, map = tr)
  lv <- terra::levels(tr)[[1]]
  expect_true(all(s$strata$stratum %in% lv[[1]]))
  expect_identical(s$strata$stratum_label,
                   as.character(lv[[2]][match(s$strata$stratum, lv[[1]])]))
  expect_true("Water -> Water" %in% s$strata$stratum_label)
  # map values are raw codes, so a transition map's class is its id
  expect_identical(s$points$map_class, s$points$stratum)
  expect_equal(sum(s$strata$n_cells), sum(!is.na(terra::values(tr))))
})

test_that("map values are read at the sampled cells, as one column or a series", {
  r23 <- tile(2023)
  s <- draw(r17, n = 10, seed = 4, map = list(`2017` = r17, `2023` = r23))
  expect_equal(s$points$map_2017, terra::values(r17)[s$points$cell, 1])
  expect_equal(s$points$map_2023, terra::values(r23)[s$points$cell, 1])
  stack <- c(r17, r23)
  # both tiles' layers are called "data", which would collide
  expect_error(draw(r17, n = 10, seed = 4, map = stack), "names must be unique")
  names(stack) <- c("y2017", "y2023")
  s2 <- draw(r17, n = 10, seed = 4, map = stack)
  expect_equal(s2$points$map_y2023, s$points$map_2023)
  shifted <- terra::shift(r23, dx = 10)
  expect_error(draw(r17, n = 10, seed = 4, map = shifted), "not on the `strata` grid")
})

test_that("draws within a stratum are uniform over its cells", {
  # a 2-class raster: stratum 1 is 1000 cells; draw 100 each time and count
  # how often each cell is picked over many seeds
  r <- terra::rast(nrows = 40, ncols = 50, xmin = 0, xmax = 500, ymin = 0,
                   ymax = 400, crs = "EPSG:32609", vals = rep(1:2, each = 1000))
  hits <- integer(1000)
  for (sd in 1:200) {
    s <- draw(r, n = 100, seed = sd)
    c1 <- s$points$cell[s$points$stratum == 1]
    hits <- hits + tabulate(c1, 1000)
  }
  # expected 20 per cell; a chi-square on 999 df
  p <- stats::pchisq(sum((hits - 20)^2 / 20), df = 999, lower.tail = FALSE)
  expect_gt(p, 0.001)
  # and the first and last cells are reachable
  expect_gt(hits[1], 0)
  expect_gt(hits[1000], 0)
})

test_that("an allocation named the way setNames() writes a number still matches", {
  big <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100, ymin = 0,
                     ymax = 100, crs = "EPSG:32609",
                     vals = rep(c(2, 100000), each = 50))
  n <- stats::setNames(c(5, 5), c(2, 100000))     # names "2", "1e+05"
  expect_identical(names(n)[2], "1e+05")
  s <- draw(big, n = n, seed = 1)
  expect_equal(s$strata$n, c(5, 5))
  expect_true(all(startsWith(s$points$point_id[s$points$stratum == 100000],
                             "100000_")))
})

test_that("the design record carries what a redraw needs", {
  s <- draw(r17, n = alloc, seed = 81)
  d <- s$design
  expect_identical(d$seed, 81)
  expect_identical(unname(d$dims), c(terra::nrow(r17), terra::ncol(r17)))
  expect_identical(d$terra_version, as.character(utils::packageVersion("terra")))
  expect_identical(unname(d$rng_kind), c("Mersenne-Twister", "Inversion", "Rejection"))
})

test_that("bad inputs are refused, naming the fault", {
  expect_error(draw(r17, n = alloc), "`seed` must be a single whole number")
  expect_error(draw(r17, n = alloc, seed = 1.5), "`seed` must be")
  expect_error(draw(c(r17, r17), n = alloc, seed = 1), "one layer; it has 2")
  ll <- terra::project(r17, "EPSG:4326", method = "near")
  expect_error(draw(ll, n = alloc, seed = 1), "projected CRS")
  fl <- r17 + 0.5
  expect_error(draw(fl, n = alloc, seed = 1), "integer stratum codes")
  expect_error(draw(r17, n = 1, seed = 1), "at least 2 points")
  expect_error(draw(r17, n = c(`1` = 5, `2` = 5), seed = 1),
               "no allocation for stratum/strata present in `strata`: 4, 5, 7, 9, 11")
  full <- stats::setNames(rep(5, 7), c(1, 2, 4, 5, 7, 9, 11))
  expect_error(draw(r17, n = c(full, `3` = 5), seed = 1), "no cells in `strata`: 3")
  empty <- terra::rast(r17)
  terra::values(empty) <- NA
  expect_error(draw(empty, n = alloc, seed = 1), "no non-NA cells")
  expect_error(draw(r17, n = alloc, seed = 1, map = "x"), "SpatRaster or a named list")
})

test_that("the sample feeds the estimator end to end", {
  # reference = 2023 read at the points, map = 2017
  r23 <- tile(2023)
  s <- draw(r17, n = 30, seed = 9, map = r17)
  pts <- sf::st_drop_geometry(s$points)
  pts$ref_class <- terra::values(r23)[pts$cell, 1]
  pts <- pts[!is.na(pts$ref_class), ]
  res <- dft_accuracy_estimate(pts, s$strata)
  expect_equal(sum(res$area$area), sum(s$strata$area))
})

# Census oracle: the tiles are small enough to know the truth. Take 2017 as
# the map and 2023 as "reference", draw many stratified samples, and check the
# estimator against the population -- unbiased, SEs that match the spread of
# the estimates, and intervals that cover at close to the nominal rate. The
# truth comes from every cell, not from the code under test.
census_oracle <- function(strata, reps = 300, n = 25) {
  ref <- tile(2023)
  sv <- terra::values(strata)[, 1]
  rv <- terra::values(ref)[, 1]
  pop <- !is.na(sv)
  truth <- table(rv[pop]) / sum(pop)
  big <- names(truth)[truth > 0.02]          # Wald intervals need some mass
  est <- se <- matrix(NA_real_, reps, length(big), dimnames = list(NULL, big))
  for (i in seq_len(reps)) {
    s <- draw(strata, n = n, seed = i, map = r17)
    pts <- sf::st_drop_geometry(s$points)
    pts$ref_class <- rv[pts$cell]
    a <- dft_accuracy_estimate(pts, s$strata)$area
    k <- match(as.numeric(big), a$class)
    est[i, ] <- ifelse(is.na(k), 0, a$proportion[k])
    se[i, ] <- ifelse(is.na(k), 0, a$proportion_se[k])
  }
  z <- stats::qnorm(0.975)
  tr <- as.vector(truth[big])
  list(
    bias_z   = (colMeans(est) - tr) / (apply(est, 2, stats::sd) / sqrt(reps)),
    se_ratio = colMeans(se) / apply(est, 2, stats::sd),
    coverage = colMeans(abs(est - rep(tr, each = reps)) <= z * se)
  )
}

test_that("census oracle: strata are the map classes", {
  skip_on_cran()
  # 98 of the 7,127 map-Trees cells are reference Water (1.4%). At n = 25 a
  # draw expects 0.34 of them, most draws see none, the stratum's variance is
  # estimated as 0, and Water's interval covered 61% (SE ratio 0.76) while the
  # estimate stayed unbiased. Coverage was 83% at n = 75 and 89% at n = 150:
  # the Wald interval's small-sample weakness, documented on the estimator.
  o <- census_oracle(r17, n = 150)
  expect_true(all(abs(o$bias_z) < 4), info = paste(round(o$bias_z, 2), collapse = " "))
  expect_true(all(o$se_ratio > 0.8 & o$se_ratio < 1.25),
              info = paste(round(o$se_ratio, 3), collapse = " "))
  expect_true(all(o$coverage > 0.85 & o$coverage < 0.99),
              info = paste(round(o$coverage, 3), collapse = " "))
})

test_that("census oracle: strata are not the map classes (changed / stable)", {
  skip_on_cran()
  # strata from a different pair of years than the map-vs-reference one, so
  # they cut across the map classes
  chg <- terra::ifel(r17 != tile(2019), 1L, 0L)
  o <- census_oracle(chg, n = 60)
  expect_true(all(abs(o$bias_z) < 4), info = paste(round(o$bias_z, 2), collapse = " "))
  expect_true(all(o$se_ratio > 0.8 & o$se_ratio < 1.25),
              info = paste(round(o$se_ratio, 3), collapse = " "))
  expect_true(all(o$coverage > 0.88 & o$coverage < 0.99),
              info = paste(round(o$coverage, 3), collapse = " "))
})

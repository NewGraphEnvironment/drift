years <- 2017:2023
cases <- break_series_cases()
x_cases <- break_series_list(cases, years)
res_cases <- dft_rast_break_class(x_cases, class_table = artifact_class_table())

# per-pixel evidence as a data.frame with one row per case, in fixture order
evidence <- function(res) {
  v <- terra::values(res$breaks)
  df <- as.data.frame(v)
  df$transition <- terra::values(res$raster)[, 1]
  df
}
ev <- evidence(res_cases)
rownames(ev) <- rownames(cases)

test_that("return shape: raster, breaks, summary", {
  expect_type(res_cases, "list")
  expect_named(res_cases, c("raster", "breaks", "summary"))
  expect_s4_class(res_cases$raster, "SpatRaster")
  expect_equal(terra::nlyr(res_cases$raster), 1)
  expect_true(terra::is.factor(res_cases$raster))
  expect_equal(names(res_cases$raster), "transition")
  expect_s4_class(res_cases$breaks, "SpatRaster")
  expect_equal(names(res_cases$breaks),
               c("break_year", "n_before", "n_after", "n_flips"))
  expect_false(any(terra::is.factor(res_cases$breaks)))
  expect_s3_class(res_cases$summary, "tbl_df")
})

test_that("a clean switch at each possible year is dated with n_before/n_after", {
  for (yr in 2018:2023) {
    row <- ev[paste0("switch_", yr), ]
    idx <- match(yr, years)
    expect_equal(row$n_flips, 1, info = as.character(yr))
    expect_equal(row$break_year, yr, info = as.character(yr))
    expect_equal(row$n_before, idx - 1, info = as.character(yr))
    expect_equal(row$n_after, length(years) - idx + 1, info = as.character(yr))
    expect_equal(row$transition, 2 * 1000 + 3, info = as.character(yr))
  }
  # the two endpoint-odd-year-out cases are clean breaks with a 1 on one side
  expect_equal(ev["switch_2018", "n_before"], 1)
  expect_equal(ev["switch_2023", "n_after"], 1)
  expect_equal(sum(ev$n_before + ev$n_after == length(years), na.rm = TRUE), 6)
})

test_that("a stable series has no break and a from == to code", {
  row <- ev["stable", ]
  expect_equal(row$n_flips, 0)
  expect_true(is.na(row$break_year))
  expect_true(is.na(row$n_before))
  expect_true(is.na(row$n_after))
  expect_equal(row$transition, 2002)
})

test_that("flicker and settling series count flips and carry no break", {
  expect_equal(ev["flicker", "n_flips"], 6)
  expect_equal(ev["flicker_diff", "n_flips"], 5)
  expect_equal(ev["settling", "n_flips"], 3)
  for (nm in c("flicker", "flicker_diff", "settling")) {
    expect_true(is.na(ev[nm, "break_year"]), info = nm)
    expect_true(is.na(ev[nm, "n_before"]), info = nm)
    expect_true(is.na(ev[nm, "n_after"]), info = nm)
  }
  # the transition layer is the two-epoch comparison regardless of the path
  expect_equal(ev["flicker", "transition"], 2002)
  expect_equal(ev["flicker_diff", "transition"], 2003)
  expect_equal(ev["settling", "transition"], 2003)
})

test_that("an interior NA blanks the evidence but keeps the two-epoch transition", {
  row <- ev["na_year", ]
  expect_true(all(is.na(row[c("break_year", "n_before", "n_after", "n_flips")])))
  expect_equal(row$transition, 2003)
  expect_true(all(is.na(unlist(ev["all_na", ]))))
})

test_that("transition layer equals dft_rast_transition() on the endpoints", {
  ref <- dft_rast_transition(x_cases, from = "2017", to = "2023",
                             class_table = artifact_class_table())
  a <- terra::values(res_cases$raster)[, 1]
  b <- terra::values(ref$raster)[, 1]
  expect_equal(is.na(a), is.na(b))
  expect_equal(a[!is.na(a)], b[!is.na(b)])
  expect_equal(terra::cats(res_cases$raster)[[1]], terra::cats(ref$raster)[[1]])
  expect_equal(terra::crs(res_cases$raster), terra::crs(ref$raster))
})

test_that("summary reconciles to the pixel count and labels every status", {
  s <- res_cases$summary
  expect_named(s, c("from_class", "to_class", "status", "break_year",
                    "n_cells", "area", "pct"))
  expect_setequal(unique(s$status), c("stable", "break", "flicker", NA))
  # 12 pixels, 1 all-NA -> 11 with a transition; 1 of those has an interior NA
  expect_equal(sum(s$n_cells), 11L)
  expect_equal(s$n_cells[is.na(s$status)], 1L)
  expect_true(is.na(s$break_year[is.na(s$status)]))
  expect_equal(sum(s$pct), 100, tolerance = 1e-3)  # pct is rounded to 2 dp
  # one break row per break year, each with one cell
  brk <- s[s$status %in% "break", ]
  expect_setequal(brk$break_year, 2018:2023)
  expect_true(all(brk$n_cells == 1L))
  expect_true(all(brk$from_class == "Trees" & brk$to_class == "Rangeland"))
  # stable and flicker rows carry NA break_year
  expect_true(all(is.na(s$break_year[!(s$status %in% "break")])))
  # flicker: Trees -> Trees (1 cell) and Trees -> Rangeland (2 cells)
  flk <- s[s$status %in% "flicker", ]
  expect_equal(flk$n_cells[flk$to_class == "Trees"], 1L)
  expect_equal(flk$n_cells[flk$to_class == "Rangeland"], 2L)
  # area: 10 m cells -> 100 m2 -> 0.01 ha each
  expect_equal(sum(s$area), 11 * 0.01)
  s_m2 <- dft_rast_break_class(x_cases, class_table = artifact_class_table(),
                               unit = "m2")$summary
  expect_equal(sum(s_m2$area), 1100)
})

test_that("output interoperates with dft_transition_vectors() and dft_transition_artifact()", {
  # a 40 x 40 grid: Trees left, Rangeland right; the boundary shifts one column
  # in 2020 and stays (a clean break), plus one flickering column at col 5
  base <- artifact_base_from()
  shifted <- base
  shifted[, 20] <- 3L
  flick <- base
  flick[, 5] <- 3L
  mats <- list(base, base, base, shifted, shifted, shifted, shifted)
  mats[[2]] <- flick
  mats[[4]][, 5] <- 3L
  x <- lapply(mats, function(m) {
    dft_rast_classify(artifact_class_rast(m), class_table = artifact_class_table())
  })
  names(x) <- years
  res <- dft_rast_break_class(x, class_table = artifact_class_table())

  patches <- dft_transition_vectors(res$raster, changes_only = TRUE)
  expect_s3_class(patches, "sf")
  expect_equal(nrow(patches), 1L)
  expect_equal(patches$transition, "Trees -> Rangeland")
  tagged <- dft_transition_artifact(patches, res$raster)
  expect_true(all(c("flag_sliver", "boundary_frac", "flag_reciprocal") %in% names(tagged)))
  expect_true(tagged$flag_sliver)

  # the break-year layer zonal'd by patch gives the patch its date
  pid <- terra::rasterize(terra::vect(patches), res$raster, field = "patch_id")
  z <- terra::zonal(res$breaks[["break_year"]], pid, fun = "mean", na.rm = TRUE)
  expect_equal(z$break_year, 2020)
  # the flickering column is 2 flips (col 5: base, flick, base, flick, base...)
  nf <- terra::values(res$breaks[["n_flips"]])[, 1]
  expect_equal(max(nf), 4)
  expect_equal(sum(nf == 4), 40)
})

test_that("input guards", {
  ct <- artifact_class_table()
  r <- x_cases[[1]]
  expect_error(dft_rast_break_class(r, class_table = ct), "named list")
  expect_error(dft_rast_break_class(x_cases[1], class_table = ct), "at least 2")
  bad <- x_cases
  names(bad)[3] <- "twenty19"
  expect_error(dft_rast_break_class(bad, class_table = ct), "year")
  dup <- x_cases
  names(dup)[3] <- "2018"
  expect_error(dft_rast_break_class(dup, class_table = ct), "unique")
  ll <- lapply(x_cases, function(r) {
    r2 <- terra::deepcopy(r)
    terra::crs(r2) <- "EPSG:4326"
    r2
  })
  expect_error(dft_rast_break_class(ll, class_table = ct), "projected CRS")
  # a different projected CRS is refused, not silently stacked by cell position
  mixed <- x_cases
  r2 <- terra::deepcopy(mixed[[4]])
  terra::crs(r2) <- "EPSG:32610"
  mixed[[4]] <- r2
  expect_error(dft_rast_break_class(mixed, class_table = ct), "share the CRS")
  # a multi-layer element is refused
  multi <- x_cases
  multi[[2]] <- c(multi[[2]], multi[[2]])
  expect_error(dft_rast_break_class(multi, class_table = ct), "single-layer")
})

test_that("class codes above 32 (ESA WorldCover range) survive the encoding", {
  # from * 1000 + to exceeds INT2S at from >= 33; the transition layer must
  # still equal dft_rast_transition() and the summary must count every pixel
  ct <- tibble::tibble(code = c(10L, 40L, 95L, 100L),
                       class_name = c("Tree cover", "Cropland", "Mangroves", "Moss"),
                       color = c("#006400", "#f096ff", "#00cf75", "#fae6a0"))
  m <- rbind(c(10, 10, 10, 40, 40, 40, 40),
             c(95, 95, 95, 95, 95, 95, 100),
             c(100, 100, 100, 100, 100, 100, 100),
             c(40, 95, 40, 95, 40, 95, 10))
  x <- lapply(seq_len(7), function(j) {
    dft_rast_classify(artifact_class_rast(matrix(m[, j], nrow = 1)), class_table = ct)
  })
  names(x) <- 2017:2023
  res <- dft_rast_break_class(x, class_table = ct)
  ref <- dft_rast_transition(x, from = "2017", to = "2023", class_table = ct)
  expect_equal(terra::values(res$raster)[, 1], c(10040, 95100, 100100, 40010))
  expect_equal(terra::values(res$raster)[, 1], terra::values(ref$raster)[, 1])
  expect_equal(terra::cats(res$raster)[[1]], terra::cats(ref$raster)[[1]])
  expect_equal(sum(res$summary$n_cells), 4L)
  expect_equal(terra::values(res$breaks[["n_flips"]])[, 1], c(1, 1, 0, 6))
})

test_that("unsorted names are sorted by year, not an error", {
  shuffled <- x_cases[c(3, 1, 7, 2, 6, 4, 5)]
  res <- dft_rast_break_class(shuffled, class_table = artifact_class_table())
  expect_equal(evidence(res), ev, ignore_attr = TRUE)
})

test_that("rasters on a different grid are resampled to the first", {
  x <- x_cases
  r <- x[[4]]
  # a finer copy of year 4 (2020): same extent, half the cell size
  fine <- terra::disagg(r, 2)
  x[[4]] <- fine
  before <- list.files(tempdir(), pattern = "^dft_break_class_", full.names = TRUE)
  res <- dft_rast_break_class(x, class_table = artifact_class_table())
  expect_true(terra::compareGeom(res$raster, x_cases[[1]]))
  expect_equal(evidence(res), ev, ignore_attr = TRUE)
  # the resample intermediate of a factor input is written with a RAT sidecar
  # (.tif.aux.xml); the cleanup must not leave it behind -- exactly one new
  # tempdir entry, the output
  after <- list.files(tempdir(), pattern = "^dft_break_class_", full.names = TRUE)
  expect_length(setdiff(after, before), 1L)
  expect_match(setdiff(after, before), "\\.tif$")
})

test_that("a classified file-backed series runs without warning", {
  # in-memory inputs are pre-stripped by the spill; the strip on the stack is
  # what a factor read from disk relies on (app() warns 'factors are coerced')
  ct <- artifact_class_table()
  fx <- lapply(x_cases, function(r) {
    f <- tempfile(fileext = ".tif")
    terra::writeRaster(r, f, datatype = "INT1U")
    dft_rast_classify(terra::rast(f), class_table = ct)
  })
  names(fx) <- years
  expect_false(any(vapply(fx, terra::inMemory, logical(1))))
  expect_no_warning(res <- dft_rast_break_class(fx, class_table = ct))
  expect_equal(evidence(res), ev, ignore_attr = TRUE)
  expect_true(all(vapply(fx, terra::is.factor, logical(1))))
})

test_that("outputs are file-backed, not in memory", {
  expect_false(any(terra::inMemory(res_cases$raster)))
  expect_false(any(terra::inMemory(res_cases$breaks)))
  expect_true(all(terra::datatype(res_cases$breaks) == "INT4S"))
})

test_that("two-layer minimum works and every non-stable pixel is a one-flip break", {
  x2 <- x_cases[c("2017", "2023")]
  res <- dft_rast_break_class(x2, class_table = artifact_class_table())
  e <- evidence(res)
  ok <- !is.na(e$n_flips)
  expect_true(all(e$n_flips[ok] %in% c(0, 1)))
  expect_true(all(e$break_year[ok & e$n_flips == 1] == 2023))
  expect_true(all(e$n_before[ok & e$n_flips == 1] == 1))
})

test_that("the scan closure refuses a bare vector so terra::app() takes the vectorised path", {
  # terra::app() tries apply(chunk, 1, fun) first and only falls back to
  # fun(chunk) when that errors; a fun that accepts a vector runs once per cell
  f <- break_class_scan(7L, 2017:2023)
  expect_error(f(c(2, 2, 2, 3, 3, 3, 3)), "matrix chunks only")
  m <- rbind(c(2, 2, 2, 3, 3, 3, 3), c(2, 2, 2, 2, 2, 2, 2), c(2, 3, 2, 3, 2, 3, 2))
  out <- f(m)
  expect_true(is.matrix(out))
  expect_equal(dim(out), c(3L, 5L))
  expect_equal(colnames(out), c("transition", "break_year", "n_before", "n_after", "n_flips"))
  expect_equal(unname(out[1, ]), c(2003, 2020, 3, 4, 1))
  expect_equal(unname(out[2, ]), c(2002, NA, NA, NA, 0))
  expect_equal(unname(out[3, ]), c(2002, NA, NA, NA, 6))
  # a single-cell chunk is a 1 x n matrix, not a vector
  expect_equal(dim(f(m[1, , drop = FALSE])), c(1L, 5L))
  # file-backed integer sources arrive as an INTEGER matrix: the encoding must
  # not overflow in R (3e6 * 1000L is NA with a warning) before terra sees it
  mi <- matrix(c(3000000L, 1L, 1L, 1L, 1L, 1L, 3000000L), nrow = 1)
  expect_no_warning(oi <- f(mi))
  expect_equal(unname(oi[1, "transition"]), 3e6 * 1000 + 3e6)
})

test_that("an abort inside the scan (a real overflow) strands no output file", {
  # from * 1000 + to passes INT4S at a code of 3e6; terra warns from
  # writeValues() before writeStop(), the handler aborts, and the partial
  # output must be unlinked. Plain code rasters are accepted, so no factor.
  big <- lapply(2017:2019, function(y) {
    r <- terra::rast(matrix(c(3e6, 1, 2, 3e6), 1))
    terra::ext(r) <- c(0, 40, 0, 10)
    terra::crs(r) <- "EPSG:32609"
    r
  })
  names(big) <- 2017:2019
  ct <- tibble::tibble(code = c(1, 2, 3e6), class_name = c("a", "b", "c"),
                       color = "#000000")
  before <- list.files(tempdir(), pattern = "^dft_break_class_", full.names = TRUE)
  expect_error(dft_rast_break_class(big, class_table = ct), "overflow the transition encoding")
  after <- list.files(tempdir(), pattern = "^dft_break_class_", full.names = TRUE)
  expect_setequal(setdiff(after, before), character(0))
})

test_that("a raster exactly 5 columns wide is not scrambled by app()'s shape heuristic", {
  # terra::app() takes a 5-column return on a 5-column raster as transposed
  ct <- artifact_class_table()
  for (nc in c(4L, 5L, 6L)) {
    m <- matrix(2L, nrow = 4, ncol = nc)
    mats <- list(m, m, m, `[<-`(m, , , 3L), `[<-`(m, , , 3L), `[<-`(m, , , 3L), `[<-`(m, , , 3L))
    mats[[5]][1, 1] <- 2L   # one flickering cell
    x <- lapply(mats, function(mm) dft_rast_classify(artifact_class_rast(mm), class_table = ct))
    names(x) <- years
    res <- dft_rast_break_class(x, class_table = ct)
    ref <- dft_rast_transition(x, from = "2017", to = "2023", class_table = ct)
    expect_equal(terra::values(res$raster)[, 1], terra::values(ref$raster)[, 1],
                 info = as.character(nc))
    expect_true(terra::compareGeom(res$raster, x[[1]]), info = as.character(nc))
    ev <- terra::values(res$breaks)
    expect_equal(sum(ev[, "n_flips"] == 1), 4 * nc - 1, info = as.character(nc))
    expect_equal(sum(ev[, "n_flips"] == 3), 1, info = as.character(nc))
    expect_true(all(ev[ev[, "n_flips"] == 1, "break_year"] == 2020), info = as.character(nc))
    expect_equal(res$summary$n_cells[res$summary$status %in% "break"], 4L * nc - 1L,
                 info = as.character(nc))
  }
})

test_that("the caller's rasters keep their levels and colours, and no warning is raised", {
  # levels are stripped in place (set.cats(NULL)) on the stack rast(list)
  # builds, never on the caller's objects -- set.cats() applied to a caller's
  # raster WOULD flip it (unlike `levels<-`, which copies first), so this
  # guards the placement; the pad path writes the stack, so a surviving
  # palette would make GDAL warn on every 5-column call
  ct <- artifact_class_table()
  m <- matrix(2L, nrow = 4, ncol = 5)
  mats <- list(m, m, m, `[<-`(m, , , 3L), `[<-`(m, , , 3L), `[<-`(m, , , 3L), `[<-`(m, , , 3L))
  x <- lapply(mats, function(mm) dft_rast_classify(artifact_class_rast(mm), class_table = ct))
  names(x) <- years
  cats_before <- lapply(x, function(r) terra::cats(r)[[1]])
  cols_before <- lapply(x, function(r) terra::coltab(r)[[1]])
  expect_true(all(vapply(x, terra::is.factor, logical(1))))
  expect_true(all(vapply(x, terra::has.colors, logical(1))))
  before <- list.files(tempdir(), pattern = "^dft_break_class_", full.names = TRUE)
  expect_no_warning(res <- dft_rast_break_class(x, class_table = ct))
  # the spill writes each in-memory layer: no RAT sidecar may survive
  after <- list.files(tempdir(), pattern = "^dft_break_class_", full.names = TRUE)
  expect_length(setdiff(after, before), 1L)
  expect_true(all(vapply(x, terra::is.factor, logical(1))))
  expect_true(all(vapply(x, terra::has.colors, logical(1))))
  expect_equal(lapply(x, function(r) terra::cats(r)[[1]]), cats_before)
  expect_equal(lapply(x, function(r) terra::coltab(r)[[1]]), cols_before)
  expect_no_warning(dft_rast_break_class(x_cases, class_table = ct))
})

test_that("an abort before any temp file exists deletes nothing in the working directory", {
  # paste0(character(0), ".aux.xml") is ".aux.xml": an unguarded cleanup would
  # unlink that name in getwd(). Reach the one such path: first raster
  # file-backed (no spill), a later one in a different CRS.
  ct <- artifact_class_table()
  d <- withr::local_tempdir()
  withr::local_dir(d)
  writeLines("not ours", ".aux.xml")
  fx <- x_cases
  f <- tempfile(fileext = ".tif")
  terra::writeRaster(fx[[1]], f, datatype = "INT1U")
  fx[[1]] <- dft_rast_classify(terra::rast(f), class_table = ct)
  r2 <- terra::deepcopy(fx[[4]])
  terra::crs(r2) <- "EPSG:32610"
  fx[[4]] <- r2
  expect_error(dft_rast_break_class(fx, class_table = ct), "share the CRS")
  expect_true(file.exists(".aux.xml"))
})

test_that("bundled seven-year series: pinned numbers", {
  # inst/extdata/example_{2017..2023}.tif on one grid (data-raw/example_years_extend.R).
  # Live IO LULC data: re-pin deliberately if the bundled files are regenerated.
  years7 <- 2017:2023
  x <- lapply(years7, function(yr) {
    terra::rast(system.file("extdata", paste0("example_", yr, ".tif"), package = "drift"))
  })
  names(x) <- years7
  x <- dft_rast_classify(x, source = "io-lulc")
  res <- dft_rast_break_class(x)
  s <- res$summary
  chg <- s[s$from_class != s$to_class, ]
  expect_equal(sum(chg$n_cells), 3403L)                       # #44: 93 patches / 34.03 ha
  expect_equal(sum(chg$n_cells[chg$status %in% "break"]), 2138L)
  expect_equal(sum(chg$n_cells[chg$status %in% "flicker"]), 1265L)
  expect_equal(sum(s$n_cells[s$status %in% "flicker" & s$from_class == s$to_class]), 2791L)
  ev <- terra::values(res$breaks)
  one <- !is.na(ev[, "n_flips"]) & ev[, "n_flips"] == 1
  expect_equal(sum(one), 2138L)
  expect_equal(sum(one & pmin(ev[, "n_before"], ev[, "n_after"]) >= 2), 1098L)
  expect_equal(sum(one & ev[, "n_after"] == 1), 776L)
  expect_equal(sum(one & ev[, "n_before"] == 1), 264L)
  byyr <- tapply(s$area[s$status %in% "break"], s$break_year[s$status %in% "break"], sum)
  expect_equal(as.vector(byyr[c("2018", "2020", "2023")]), c(2.64, 7.12, 7.76))
  patches <- dft_transition_vectors(res$raster, changes_only = TRUE)
  expect_equal(nrow(patches), 93L)
  expect_equal(sum(patches$area_ha), 34.03, tolerance = 1e-6)
})

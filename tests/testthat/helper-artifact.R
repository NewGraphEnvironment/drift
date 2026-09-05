# Synthetic transition fixtures for dft_transition_artifact() tests. Two integer
# class matrices (from, to) on a 10 m projected grid (EPSG:32609) become a
# classified list and run through dft_rast_transition() with a synthetic
# 4-class table — so the tests prove "any factor transition raster", not IO LULC.
#
# codes: 1 = Water, 2 = Trees, 3 = Rangeland, 4 = Bare

artifact_class_table <- function() {
  tibble::tibble(
    code = 1:4,
    class_name = c("Water", "Trees", "Rangeland", "Bare"),
    color = c("#419bdf", "#397d49", "#e3e2c3", "#a59b8f")
  )
}

artifact_class_rast <- function(m, res = 10) {
  r <- terra::rast(m)
  terra::ext(r) <- c(0, ncol(m) * res, 0, nrow(m) * res)
  terra::crs(r) <- "EPSG:32609"
  r
}

# returns the dft_rast_transition() result list (raster, summary, removed)
make_transition <- function(from_mat, to_mat, res = 10) {
  x <- list(
    "t1" = artifact_class_rast(from_mat, res),
    "t2" = artifact_class_rast(to_mat, res)
  )
  dft_rast_transition(x, from = "t1", to = "t2",
                      class_table = artifact_class_table())
}

# A 40 x 40 grid: Trees on the left 20 columns, Rangeland on the right 20
artifact_base_from <- function(n = 40) {
  m <- matrix(2L, nrow = n, ncol = n)
  m[, 21:n] <- 3L
  m
}

# Fixture A: the Trees|Rangeland boundary shifts one column left between
# epochs -> a 1-px "Trees -> Rangeland" band at column 20 (40 cells)
artifact_fixture_shift <- function() {
  from <- artifact_base_from()
  to <- from
  to[, 20] <- 3L
  make_transition(from, to)
}

# Fixture B: a 5-px river (Water, cols 18:22) through Trees shifts one column
# right -> "Water -> Trees" at col 18 and "Trees -> Water" at col 23, 40 cells
# each, separated by four stable Water columns
artifact_fixture_river <- function(to_rows = 1:40) {
  from <- matrix(2L, nrow = 40, ncol = 40)
  from[, 18:22] <- 1L
  to <- from
  to[, 18] <- 2L
  to[to_rows, 23] <- 1L
  make_transition(from, to)
}

# Fixture C: Fixture A plus a 1-px road (Bare) along row 20 crossing the whole
# grid -> "Trees -> Bare" (cols 1:20) and "Rangeland -> Bare" (cols 21:40),
# and the shift band split into two halves by the road. A stable Bare block
# (rows 21:25, cols 1:3) exists in BOTH epochs so that Bare is present in the
# from epoch: the road's low boundary_frac must come from geometry, not from
# the to-class being absent. Road cells at cols 1:4 are within one cell of
# that block (col 4 diagonally), so "Trees -> Bare" scores exactly 4 / 20.
artifact_fixture_road <- function() {
  from <- artifact_base_from()
  from[21:25, 1:3] <- 4L
  to <- from
  to[, 20] <- 3L
  to[20, ] <- 4L
  make_transition(from, to)
}

# Fixture D: a 20 x 20 clearing in the interior of a Trees block. Column 40 is
# stable Rangeland in both epochs so the to-class exists in the from epoch,
# nine cells away from the clearing's edge — boundary_frac is 0 by distance.
artifact_fixture_blob <- function() {
  from <- matrix(2L, nrow = 40, ncol = 40)
  from[, 40] <- 3L
  to <- from
  to[11:30, 11:30] <- 3L
  make_transition(from, to)
}

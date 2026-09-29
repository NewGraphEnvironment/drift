#' Draw a stratified random sample of points for accuracy assessment
#'
#' Draw random cells within each stratum of a raster -- the map classes, a
#' transition map, or strata the caller built, such as "change attributed to
#' fire / unattributed / stable" -- as the sample design behind
#' [dft_accuracy_estimate()], following Olofsson et al. (2014).
#'
#' Points, not patches: sampling patches over-weights large ones, and area is
#' the quantity being estimated.
#'
#' @param strata A single-layer [terra::SpatRaster] of integer stratum codes
#'   in a projected CRS. `NA` cells are outside the population. A factor
#'   raster (e.g. `$raster` from [dft_rast_transition()] or
#'   [dft_rast_break_class()]) keeps its codes as `stratum` and its labels as
#'   `stratum_label`.
#' @param n Sample size per stratum: a single number for equal allocation, or
#'   a vector named by stratum code (e.g. from [dft_accuracy_size()]) covering
#'   every stratum present. Each must be at least 2.
#' @param seed Integer seed. Required: the draw is part of the record, and a
#'   sample nobody can redraw cannot be audited.
#' @param map Optional. The map being assessed, on the same grid as `strata`:
#'   a single-layer SpatRaster (becomes `map_class`), a multi-layer SpatRaster
#'   or a named list of single-layer SpatRasters (become `map_<name>`, e.g.
#'   `map_2017` for a series). Values are read as raw codes, so a transition
#'   map gives its `from * 1000 + to` id.
#'
#' @return A list:
#' - `points` -- `sf` points at cell centres: `point_id`, `stratum`,
#'   `stratum_label`, `cell`, and any `map_*` columns. The geometry is the
#'   location; there are no coordinate columns to disagree with it.
#' - `strata` -- tibble: `stratum`, `stratum_label`, `n_cells` (`N_h`), `area`
#'   (ha), `weight` (`N_h / N`), `n` (points drawn). This is the `strata`
#'   argument [dft_accuracy_estimate()] takes.
#' - `design` -- list recording how to redraw it: seed, RNG kinds, allocation
#'   requested, census strata, R and terra versions, and the grid's
#'   dimensions, extent and CRS.
#'
#' @section Reproducible, and extensible from a pilot:
#' The draw uses only R's own random number generator and the raster's cell
#' order -- not [terra::spatSample()], whose output is not promised stable
#' across terra versions. Each stratum gets its own random stream, seeded from
#' `seed` and the stratum code, with the generator kinds pinned
#' (Mersenne-Twister, Inversion, Rejection), so:
#' - the same `seed`, `n` and raster give the same points on any machine;
#' - **raising `n` extends the sample**: the first 30 points of a stratum at
#'   `n = 50` are the 30 points drawn at `n = 30`, so labels from a pilot
#'   carry into the full sample (`point_id` is stable too);
#' - changing one stratum's `n`, or adding a stratum, leaves every other
#'   stratum's points unchanged.
#'
#' The caller's random number state is restored afterwards.
#'
#' `cell` is a cell number on this grid. Cropping or extending the raster
#' renumbers cells, so draw from the grid the map is on and keep it.
#'
#' @section Small strata:
#' A stratum with no more cells than its allocation is taken whole -- a
#' census -- and a message names it. Transition strata with a handful of cells
#' are normal. [dft_accuracy_estimate()] applies the finite population
#' correction, so a census stratum contributes no variance.
#'
#' @section Memory:
#' The raster is read twice in row chunks of about ten million cells -- once
#' to count cells per stratum, once to find the drawn cells -- so a
#' floodplain-scale raster is never held in memory whole.
#'
#' @section Polygon strata:
#' Rasterise onto the map's grid first, in memory, and mask to the map's
#' footprint so the population is the mapped area:
#' `strata <- terra::mask(terra::rasterize(polys, map, field = "stratum"), map)`.
#' Do not rasterise straight to a file with an integer `datatype`: terra then
#' writes cells no polygon covers as 0 rather than `NA`, and 0 becomes a
#' stratum.
#'
#' @references
#' Olofsson, P., Foody, G.M., Herold, M., Stehman, S.V., Woodcock, C.E. and
#' Wulder, M.A. (2014). Good practices for estimating area and assessing
#' accuracy of land change. *Remote Sensing of Environment* 148, 42-57.
#' \doi{10.1016/j.rse.2014.02.015}
#'
#' @seealso [dft_accuracy_estimate()], [dft_accuracy_size()],
#'   [dft_accuracy_labels()].
#'
#' @export
#' @examples
#' map <- terra::rast(system.file("extdata", "example_2017.tif",
#'                                package = "drift"))
#'
#' # strata are the map classes; two strata here have only 2 cells, which are
#' # taken whole
#' s <- dft_accuracy_sample(map, n = 20, seed = 81, map = map)
#' s$strata
#' head(s$points)
#'
#' # a pilot of 20 per stratum extends to 40 without moving the first 20
#' s40 <- dft_accuracy_sample(map, n = 40, seed = 81)
#' all(s$points$cell %in% s40$points$cell)
dft_accuracy_sample <- function(strata, n, seed, map = NULL) {
  if (!inherits(strata, "SpatRaster")) {
    stop("`strata` must be a SpatRaster.", call. = FALSE)
  }
  if (terra::nlyr(strata) != 1L) {
    stop("`strata` must have one layer; it has ", terra::nlyr(strata), ".",
         call. = FALSE)
  }
  dft_check_crs(strata, "dft_accuracy_sample")
  if (missing(seed) || !is.numeric(seed) || length(seed) != 1L ||
        is.na(seed) || seed != trunc(seed)) {
    stop("`seed` must be a single whole number; it is required so the ",
         "sample can be redrawn.", call. = FALSE)
  }
  map_list <- accuracy_map_list(map, strata)

  # pass 1: cells per stratum, and a refusal of non-integer codes
  counts <- accuracy_scan(strata, function(v, cell0, acc) {
    v <- v[!is.na(v)]
    if (length(v) == 0L) return(acc)
    if (any(v != round(v))) {
      stop("`strata` must hold integer stratum codes; found ",
           v[v != round(v)][1], ".", call. = FALSE)
    }
    u <- unique(v)
    new <- setdiff(u, acc$code)
    acc$code <- c(acc$code, new)
    acc$count <- c(acc$count, numeric(length(new)))
    acc$count <- acc$count + tabulate(match(v, acc$code), length(acc$code))
    acc
  }, list(code = numeric(0), count = numeric(0)))
  if (length(counts$code) == 0L) {
    stop("`strata` has no non-NA cells.", call. = FALSE)
  }
  o <- order(counts$code)
  code <- counts$code[o]
  n_cells <- counts$count[o]

  n_req <- accuracy_allocation(n, code)
  census <- n_req >= n_cells
  n_draw <- pmin(n_req, n_cells)
  if (any(census)) {
    message("Taking all cells (a census) of ", sum(census),
            " stratum/strata with no more cells than allocated: ",
            paste0(code[census], " (", n_cells[census], ")", collapse = ", "),
            ".")
  }

  ranks <- accuracy_draw(code, n_cells, n_draw, seed)

  # pass 2: resolve each stratum's within-stratum ranks to cell numbers
  wanted <- lapply(ranks, sort)
  found <- accuracy_scan(strata, function(v, cell0, acc) {
    keep <- which(!is.na(v))
    vv <- v[keep]
    in_chunk <- tabulate(match(vv, code), length(code))
    lo <- acc$seen
    hi <- acc$seen + in_chunk
    hit <- vapply(seq_along(code), function(h) {
      w <- wanted[[h]]
      any(w > lo[h] & w <= hi[h])
    }, logical(1))
    if (any(hit)) {
      ord <- order(vv, method = "radix")
      start <- match(code, vv[ord])
      for (h in which(hit)) {
        w <- wanted[[h]]
        local <- w[w > lo[h] & w <= hi[h]] - lo[h]
        pos <- keep[ord[start[h] + local - 1L]]
        acc$cells[[h]] <- c(acc$cells[[h]], cell0 + pos)
        acc$rank[[h]] <- c(acc$rank[[h]], local + lo[h])
      }
    }
    acc$seen <- hi
    acc
  }, list(seen = numeric(length(code)),
          cells = vector("list", length(code)),
          rank = vector("list", length(code))))
  if (!identical(as.numeric(found$seen), as.numeric(n_cells))) {
    stop("Internal error: the two passes over `strata` counted different ",
         "cells. Was the raster modified during the draw?", call. = FALSE)
  }

  labels <- accuracy_stratum_labels(strata, code)
  pts <- lapply(seq_along(code), function(h) {
    # back to draw order, so point_id k is the k-th point drawn in its stratum
    cells <- found$cells[[h]][match(ranks[[h]], found$rank[[h]])]
    data.frame(
      point_id      = sprintf("%s_%05d", accuracy_key(code[h]),
                              seq_along(cells)),
      stratum       = code[h],
      stratum_label = labels[h],
      cell          = cells,
      stringsAsFactors = FALSE
    )
  })
  pts <- do.call(rbind, pts)
  for (nm in names(map_list)) {
    pts[[nm]] <- as.vector(terra::extract(map_list[[nm]], pts$cell,
                                          raw = TRUE)[, 1])
  }
  xy <- terra::xyFromCell(strata, pts$cell)
  points <- sf::st_as_sf(
    cbind(pts, x = xy[, 1], y = xy[, 2]),
    coords = c("x", "y"),
    crs = terra::crs(strata)
  )

  cell_area_ha <- prod(terra::res(strata)) * 1e-4
  strata_tbl <- tibble::tibble(
    stratum       = code,
    stratum_label = labels,
    n_cells       = n_cells,
    area          = n_cells * cell_area_ha,
    weight        = n_cells / sum(n_cells),
    n             = n_draw
  )

  design <- list(
    seed          = seed,
    rng_kind      = c(kind = "Mersenne-Twister", normal.kind = "Inversion",
                      sample.kind = "Rejection"),
    n_requested   = stats::setNames(n_req, accuracy_key(code)),
    census        = code[census],
    r_version     = R.version.string,
    terra_version = as.character(utils::packageVersion("terra")),
    dims          = c(nrow = terra::nrow(strata), ncol = terra::ncol(strata)),
    extent        = as.vector(terra::ext(strata)),
    crs           = terra::crs(strata)
  )

  list(points = points, strata = strata_tbl, design = design)
}

# Read a single-layer raster in row chunks, folding `fun(values, cell0, acc)`
# over them. cell0 is the cell number before the chunk's first cell.
accuracy_scan <- function(r, fun, acc) {
  nr <- terra::nrow(r)
  nc <- terra::ncol(r)
  rows <- getOption("drift.accuracy_rows_chunk",
                    max(1L, floor(1e7 / nc)))
  terra::readStart(r)
  on.exit(terra::readStop(r), add = TRUE)
  row <- 1L
  while (row <= nr) {
    k <- min(rows, nr - row + 1L)
    v <- terra::readValues(r, row = row, nrows = k)
    acc <- fun(v, (row - 1) * nc, acc)
    row <- row + k
  }
  acc
}

# Resolve `n` to one allocation per stratum code
accuracy_allocation <- function(n, code) {
  if (!is.numeric(n) || anyNA(n) || any(n != trunc(n))) {
    stop("`n` must be whole numbers.", call. = FALSE)
  }
  key <- accuracy_key(code)
  if (length(n) == 1L && is.null(names(n))) {
    out <- rep(n, length(code))
  } else {
    if (is.null(names(n)) || anyNA(names(n)) || anyDuplicated(names(n))) {
      stop("A per-stratum `n` must be named by stratum code, uniquely.",
           call. = FALSE)
    }
    # names are strings already: normalise numeric-looking ones through the
    # same key, so a name written "1e+05" by setNames() still finds 100000
    nn <- names(n)
    num <- suppressWarnings(as.numeric(nn))
    nn[!is.na(num)] <- accuracy_key(num[!is.na(num)])
    if (anyDuplicated(nn)) {
      stop("A per-stratum `n` names one stratum twice.", call. = FALSE)
    }
    names(n) <- nn
    absent <- setdiff(key, names(n))
    if (length(absent) > 0L) {
      stop("`n` has no allocation for stratum/strata present in `strata`: ",
           paste(absent, collapse = ", "), ". Every stratum with cells must ",
           "be sampled, or the estimate cannot cover it.", call. = FALSE)
    }
    extra <- setdiff(names(n), key)
    if (length(extra) > 0L) {
      stop("`n` names stratum/strata with no cells in `strata`: ",
           paste(extra, collapse = ", "), ".", call. = FALSE)
    }
    out <- unname(n[key])
  }
  if (any(out < 2)) {
    stop("Every stratum needs at least 2 points (its variance is undefined ",
         "with 1).", call. = FALSE)
  }
  as.numeric(out)
}

# One independent, pinned random stream per stratum. Restores the caller's
# RNG state, including its kinds, or removes .Random.seed if there was none.
accuracy_draw <- function(code, n_cells, n_draw, seed) {
  env <- globalenv()
  had_seed <- exists(".Random.seed", envir = env, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = env, inherits = FALSE)
  old_kind <- RNGkind()
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = env) # nolint: object_name_linter. R's own name
    } else {
      RNGkind(old_kind[1], old_kind[2], old_kind[3])
      if (exists(".Random.seed", envir = env, inherits = FALSE)) {
        rm(".Random.seed", envir = env)
      }
    }
  }, add = TRUE)
  lapply(seq_along(code), function(h) {
    # a census still comes from the stream: returning cell order here would
    # renumber a stratum's points once a larger n tipped it into a census,
    # and pilot labels joined by point_id would land on other cells
    set.seed(accuracy_stream_seed(seed, code[h]), kind = "Mersenne-Twister",
             normal.kind = "Inversion", sample.kind = "Rejection")
    # useHash pinned: by default sample.int() switches algorithm on n and
    # size, which would move a draw when a pilot's n grows. The non-hash path
    # is a partial shuffle, so a larger size extends a smaller one; it holds
    # N_h integers, a few MB at floodplain scale
    sample.int(n_cells[h], n_draw[h], useHash = FALSE)
  })
}

# A stratum's stream seed: a stable 32-bit hash of the seed and the code
accuracy_stream_seed <- function(seed, code) {
  digest::digest2int(paste0("drift-accuracy:", accuracy_key(seed), ":",
                            accuracy_key(code)))
}

accuracy_stratum_labels <- function(strata, code) {
  if (!terra::is.factor(strata)[1]) return(rep(NA_character_, length(code)))
  lv <- terra::levels(strata)[[1]]
  as.character(lv[[2]][match(code, lv[[1]])])
}

# Normalise `map` to a named list of single-layer rasters on the strata grid
accuracy_map_list <- function(map, strata) {
  if (is.null(map)) return(list())
  if (inherits(map, "SpatRaster")) {
    if (terra::nlyr(map) == 1L) {
      out <- list(map_class = map)
    } else {
      out <- terra::as.list(map)
      names(out) <- paste0("map_", names(map))
    }
  } else if (is.list(map) && length(map) > 0L && !is.null(names(map)) &&
               all(nzchar(names(map))) &&
               all(vapply(map, inherits, logical(1), "SpatRaster"))) {
    out <- map
    names(out) <- paste0("map_", names(map))
  } else {
    stop("`map` must be a SpatRaster or a named list of SpatRasters.",
         call. = FALSE)
  }
  if (anyDuplicated(names(out))) {
    stop("`map` layer names must be unique.", call. = FALSE)
  }
  for (nm in names(out)) {
    if (terra::nlyr(out[[nm]]) != 1L) {
      stop("Each raster in a `map` list must have one layer.", call. = FALSE)
    }
    if (!isTRUE(terra::compareGeom(strata, out[[nm]], stopOnError = FALSE))) {
      stop("`map` (", nm, ") is not on the `strata` grid; cell numbers would ",
           "point at different ground.", call. = FALSE)
    }
  }
  out
}

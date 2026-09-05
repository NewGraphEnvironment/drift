#' Tag transition patches with geometric misregistration evidence
#'
#' Year-to-year classified land cover carries geometric artifacts that read as
#' real transitions but are misalignment: a boundary that moved by a pixel
#' between epochs leaves a thin band of "change" along one side of it, and a
#' channel that shifted leaves `Trees -> Water` on one bank and
#' `Water -> Trees` on the other. Both inflate reported change, and both
#' concentrate on the long linear boundaries (banks, forest edges, field
#' margins) that riparian work is about. `patch_area_min` cannot separate them
#' from real change — a one-pixel band along a 5 km bank is 15 ha — because
#' area is width times length and the artifact is pathological in *width*.
#'
#' This function adds evidence columns to the patches from
#' [dft_transition_vectors()] and lets the caller decide. It drops nothing.
#' Every signature is derived from the transition raster alone, so it costs
#' no extra fetch and works on any factor transition raster.
#'
#' @param patches An `sf` object of transition patches from
#'   [dft_transition_vectors()], with columns `patch_id` (unique),
#'   `transition` and `area_ha`. Run this **before** zone attribution or
#'   [dft_transition_attribute()] with `match_mode = "all"`: zone intersection
#'   splits patch geometry and `"all"` mode duplicates `patch_id`, and both
#'   change what "a patch" means to the metrics below.
#' @param transition The factor `SpatRaster` the patches were vectorized from
#'   (the `$raster` element of [dft_rast_transition()]). Must be the
#'   **unfiltered** raster — one produced without `from_class` / `to_class` —
#'   because the boundary signature reads the from-epoch class of the cells
#'   *around* each patch, and a filtered raster is `NA` there.
#' @param width_max Numeric, in pixels. A patch whose effective width
#'   `2 * area / perimeter` is below this is flagged as a sliver. The default
#'   `1.5` catches a one-pixel band (0.5–1 px by this metric) and clears a
#'   two-pixel-wide strip.
#' @param boundary_dist_max Positive whole number, in pixels. A patch cell
#'   counts as boundary-hugging when a from-epoch cell of the patch's *to*
#'   class lies within this many cells of it (a square window). `1` means
#'   8-neighbour adjacency.
#' @param reciprocal Logical. Search for reciprocal partners? `FALSE` skips the
#'   pairwise step and returns `NA` in the three `reciprocal*` columns, for
#'   very large patch sets where the search is not wanted.
#' @param reciprocal_dist_max Numeric, in pixels. How far from an `A -> B`
#'   patch to look for a `B -> A` partner. Opposite-bank bands are separated
#'   by the stable channel between them, so this must exceed the channel
#'   width in pixels; the default `5` covers a 50 m river at 10 m.
#' @param reciprocal_area_ratio_min Numeric in `[0, 1]`. A candidate partner
#'   must have `min(area) / max(area)` at least this large — a compensating
#'   shift moves about the same area in each direction.
#'
#' @details
#' Three signatures, each reported as a measurement plus a flag:
#'
#' **Sliver width.** Effective width `2 * area / perimeter` — for a rectangle
#' of sides `a << b` this is close to `a`. On a 10 m grid a single pixel
#' scores 0.5 px, a 1 x 20 pixel band 0.95 px, a 20 x 20 block 10 px. Width
#' is orthogonal to `patch_area_min`: a 15 ha sliver and a 15 ha clearing are
#' identical on the area axis and ~80x apart on this one.
#'
#' **Boundary-hugging.** The share of a patch's cells that lie within
#' `boundary_dist_max` cells of a from-epoch cell of the patch's *to* class —
#' that is, of the pre-existing interface between the two classes. This is the
#' disambiguator width alone cannot supply: a registration artifact *traces*
#' an existing boundary, while a real thin change (a new road, a harvested
#' buffer strip) *cuts across* one and scores near zero. `flag_boundary` is
#' `boundary_frac >= 0.5`.
#'
#' **Reciprocity.** Whether an `A -> B` patch has a `B -> A` partner of
#' comparable area within `reciprocal_dist_max`. Along a channel that shifted
#' by a pixel, one bank maps `Water -> Trees` and the other `Trees -> Water`;
#' the net change is ~zero and the two bands are separated by the stable
#' channel, so the test is proximity rather than adjacency. The partner
#' recorded is the nearest one that meets the area criterion (ties to the
#' larger). This is a geometric relationship between two patches and is
#' unavailable to any per-pixel method, including the spectral check.
#'
#' Stable patches (`A -> A`, present when `changes_only = FALSE`) get the
#' width columns — those are geometry only — and `NA` for everything else.
#' `NA` there means *not applicable*, not "checked and clean".
#'
#' No composed `flag_artifact` is returned: which signatures matter depends on
#' the AOI, and real changes are sometimes genuinely thin. Compose it yourself,
#' e.g. `flag_sliver & (flag_boundary | flag_reciprocal)`.
#'
#' The independent confirmation route is spectral: [dft_rast_break()] on a
#' Sentinel-2 index cube, described in the *Trajectories as a Check on
#' Land-Cover Change* vignette, where a mapped transition with no spectral
#' break is read as a label change rather than real change. That route needs
#' a cube and cannot see the reciprocal relationship; this one is free and
#' categorical-only. They are complements.
#'
#' @section Memory:
#' The boundary signature is computed with streamed `terra` operations —
#' `segregate` into one layer per distinct *to* class among the change
#' patches, a single `focal` pass over that stack, `rasterize` + `zonal` for
#' the per-patch fraction — with every intermediate written to a temporary
#' file so nothing full-grid is held in memory or pulled into R. Measured on
#' a 169M-cell floodplain grid (the BULK watershed group at 10 m). The
#' reciprocal search is an `sf` spatial-index query per transition pair.
#'
#' @return `patches` with eight columns appended (geometry stays last):
#'   - `width_m`, `width_px` (numeric) — effective width `2 * area / perimeter`
#'   - `flag_sliver` (logical) — `width_px < width_max`
#'   - `boundary_frac` (numeric, 0–1) — share of cells within
#'     `boundary_dist_max` of the from-epoch interface; `NA` for stable patches
#'   - `flag_boundary` (logical) — `boundary_frac >= 0.5`; `NA` for stable
#'   - `reciprocal_id` — `patch_id` of the partner, or `NA`
#'   - `reciprocal_dist_m` (numeric) — distance to it (`0` when touching)
#'   - `flag_reciprocal` (logical) — a partner was found; `NA` for stable
#'     patches or when `reciprocal = FALSE`
#'
#' @seealso [dft_transition_vectors()] for producing the input patches and its
#'   `patch_area_min` for the area axis; [dft_transition_attribute()] to tag
#'   patches from an overlay layer once artifacts are flagged;
#'   [dft_rast_break()] for the spectral confirmation route.
#'
#' @export
#' @examples
#' r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
#' r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
#' classified <- dft_rast_classify(list("2017" = r17, "2023" = r23), source = "io-lulc")
#' result <- dft_rast_transition(classified, from = "2017", to = "2023")
#' patches <- dft_transition_vectors(result$raster, changes_only = TRUE)
#'
#' tagged <- dft_transition_artifact(patches, result$raster)
#'
#' # most patches are slivers, but they hold a minority of the change area
#' table(tagged$flag_sliver)
#' tapply(tagged$area_ha, tagged$flag_sliver, sum)
#'
#' # a sliver that also traces a pre-existing boundary is the artifact shape;
#' # compose the verdict yourself and keep the evidence
#' tagged$flag_artifact <- tagged$flag_sliver &
#'   (tagged$flag_boundary | tagged$flag_reciprocal)
#' head(sf::st_drop_geometry(tagged[tagged$flag_artifact, ]))
#'
#' # the sliver that walks through patch_area_min = 5000 (0.75 ha, 1.4 px wide)
#' large <- dft_transition_vectors(result$raster, changes_only = TRUE,
#'                                 patch_area_min = 5000)
#' large <- dft_transition_artifact(large, result$raster)
#' sf::st_drop_geometry(large[large$flag_sliver, ])
dft_transition_artifact <- function(patches,
                                    transition,
                                    width_max = 1.5,
                                    boundary_dist_max = 1,
                                    reciprocal = TRUE,
                                    reciprocal_dist_max = 5,
                                    reciprocal_area_ratio_min = 0.5) {
  if (!inherits(patches, "sf")) {
    cli::cli_abort(c(
      "{.arg patches} must be an {.cls sf} object.",
      "i" = "Use {.fn dft_transition_vectors} to create transition patches."
    ))
  }
  if (!inherits(transition, "SpatRaster")) {
    cli::cli_abort(
      "{.arg transition} must be a {.cls SpatRaster} (e.g. {.code dft_rast_transition()$raster})."
    )
  }
  if (!terra::is.factor(transition)) {
    cli::cli_abort(
      "{.arg transition} must be a factor {.cls SpatRaster} with transition labels."
    )
  }
  dft_check_crs(transition, "dft_transition_artifact")

  cols_req <- c("patch_id", "transition", "area_ha")
  cols_missing <- setdiff(cols_req, names(patches))
  if (length(cols_missing) > 0) {
    cli::cli_abort(c(
      "{.arg patches} is missing column{?s} {.val {cols_missing}}.",
      "i" = "Use {.fn dft_transition_vectors} to create transition patches."
    ))
  }
  if (anyDuplicated(patches$patch_id) > 0) {
    cli::cli_abort(c(
      "{.arg patches} must have a unique {.field patch_id} per row.",
      "i" = "Tag artifacts on the {.fn dft_transition_vectors} output before
             zone attribution or {.code dft_transition_attribute(match_mode = \"all\")}."
    ))
  }
  if (is.na(sf::st_crs(patches)) ||
        sf::st_crs(patches) != sf::st_crs(terra::crs(transition))) {
    cli::cli_abort(
      "{.arg patches} and {.arg transition} must share a CRS."
    )
  }
  check_num1 <- function(x, nm, lower = 0, upper = Inf) {
    if (!is.numeric(x) || length(x) != 1 || is.na(x) || x < lower || x > upper) {
      cli::cli_abort(
        "{.arg {nm}} must be a single number in [{lower}, {upper}]."
      )
    }
  }
  check_num1(width_max, "width_max")
  check_num1(boundary_dist_max, "boundary_dist_max", lower = 1)
  if (boundary_dist_max != round(boundary_dist_max)) {
    cli::cli_abort("{.arg boundary_dist_max} must be a whole number of pixels.")
  }
  if (!is.logical(reciprocal) || length(reciprocal) != 1 || is.na(reciprocal)) {
    cli::cli_abort("{.arg reciprocal} must be {.code TRUE} or {.code FALSE}.")
  }
  check_num1(reciprocal_dist_max, "reciprocal_dist_max")
  check_num1(reciprocal_area_ratio_min, "reciprocal_area_ratio_min", upper = 1)

  # Resolve each patch label to its from/to codes through the raster's own
  # levels (id = from * 1000 + to), rather than parsing the label string.
  # terra's contract is that the FIRST cats column is the id; the label column
  # is drift's own ("transition", set by dft_rast_transition()).
  ct <- terra::cats(transition)[[1]]
  if (!"transition" %in% names(ct)) {
    cli::cli_abort(c(
      "{.arg transition} has no {.field transition} level column.",
      "i" = "Pass the {.code $raster} element of {.fn dft_rast_transition}."
    ))
  }
  lab_idx <- match(patches$transition, ct[["transition"]])
  if (anyNA(lab_idx)) {
    bad <- unique(patches$transition[is.na(lab_idx)])
    cli::cli_abort(c(
      "{.arg patches} carries {cli::qty(length(bad))}transition{?s} not among
       the levels of {.arg transition}: {.val {bad}}.",
      "i" = "Pass the raster the patches were vectorized from."
    ))
  }
  ids <- ct[[1]][lab_idx]
  from_code <- ids %/% 1000L
  to_code <- ids %% 1000L
  is_change <- from_code != to_code
  n <- nrow(patches)
  cell_size <- mean(terra::res(transition))

  # 1. Effective width (geometry only; defined for stable patches too)
  area_m2 <- as.numeric(sf::st_area(patches))
  # st_length(st_boundary()) rather than st_perimeter(): the latter delegates to
  # lwgeom for projected data, which is not a dependency. Measured identical on
  # the bundled patches (multipolygons and holes included).
  perim_m <- as.numeric(sf::st_length(sf::st_boundary(sf::st_geometry(patches))))
  width_m <- 2 * area_m2 / perim_m
  width_m[!(perim_m > 0)] <- NA_real_   # (ifelse() on length 0 would return logical)
  width_px <- width_m / cell_size
  flag_sliver <- width_px < width_max

  # 2. Boundary-hugging (change patches only)
  boundary_frac <- rep(NA_real_, n)
  if (any(is_change)) {
    boundary_frac[is_change] <- artifact_boundary_frac(
      patches[is_change, ], transition, to_code[is_change], boundary_dist_max
    )
  }
  flag_boundary <- ifelse(is.na(boundary_frac), NA, boundary_frac >= 0.5)

  # 3. Reciprocity (change patches only, optional)
  reciprocal_id <- patches$patch_id[rep(NA_integer_, n)]   # typed like patch_id
  reciprocal_dist_m <- rep(NA_real_, n)
  flag_reciprocal <- rep(NA, n)
  if (isTRUE(reciprocal)) {
    if (any(is_change)) {
      rec <- artifact_reciprocal(
        patches, from_code, to_code, is_change, area_m2,
        dist_m = reciprocal_dist_max * cell_size,
        ratio_min = reciprocal_area_ratio_min
      )
      reciprocal_id <- rec$id
      reciprocal_dist_m <- rec$dist
    }
    flag_reciprocal <- ifelse(is_change, !is.na(reciprocal_id), NA)
  }

  out <- patches
  out$width_m <- width_m
  out$width_px <- width_px
  out$flag_sliver <- flag_sliver
  out$boundary_frac <- boundary_frac
  out$flag_boundary <- flag_boundary
  out$reciprocal_id <- reciprocal_id
  out$reciprocal_dist_m <- reciprocal_dist_m
  out$flag_reciprocal <- flag_reciprocal

  # keep the geometry column last, as dft_transition_vectors() returns it
  geom_col <- attr(out, "sf_column")
  out[c(setdiff(names(out), geom_col), geom_col)]
}

#' Share of each change patch lying within `dist` cells of the from-epoch
#' interface with its to-class
#'
#' One 0/1 layer per distinct to-class among the patches (`segregate`), a single
#' focal-max pass over that stack marking the cells within `dist` of a
#' from-epoch cell of each class, and a single `zonal` over a rasterized
#' patch-id layer (which round-trips the raster-aligned polygons exactly).
#' Restricted to a patch — whose cells are all its from-class — the layer for
#' its to-class is exactly "from-class cells adjacent to the to-class in the
#' from epoch".
#'
#' Every intermediate is written to a temp file rather than held in memory:
#' each one is a full-grid raster, and on a floodplain-scale grid (BULK,
#' 169M cells) holding them in memory peaked at 11 GB for a single class and
#' was killed at eight. Disk-backed, terra streams them in chunks.
#' @noRd
artifact_boundary_frac <- function(patches_chg, transition, to_code, dist) {
  files <- character(0)
  on.exit(unlink(files), add = TRUE)
  tmpf <- function() {
    f <- tempfile(pattern = "dft_artifact_", fileext = ".tif")
    files <<- c(files, f)
    f
  }

  # from-epoch class codes (id %/% 1000), as a plain (non-factor) raster on disk
  codes <- terra::deepcopy(transition)
  levels(codes) <- NULL
  code_from <- terra::app(codes, fun = function(x) x %/% 1000L, filename = tmpf())

  pid <- terra::rasterize(terra::vect(patches_chg), transition,
                          field = "patch_id", filename = tmpf())

  ks <- sort(unique(to_code))
  # one 0/1 layer per to-class; NA stays NA where the raster is NA
  seg <- terra::segregate(code_from, classes = ks, other = 0L, filename = tmpf())
  w <- 2L * as.integer(dist) + 1L
  near <- terra::focal(seg, w = w, fun = "max", na.rm = TRUE, filename = tmpf())
  z <- terra::zonal(near, pid, fun = "mean", na.rm = TRUE)   # patch_id, then one col per class

  frac <- rep(NA_real_, nrow(patches_chg))
  row <- match(patches_chg$patch_id, z[[1]])
  for (i in seq_along(ks)) {
    sel <- to_code == ks[i]
    frac[sel] <- z[[i + 1L]][row[sel]]
  }
  frac
}

#' Nearest reverse-transition partner of comparable area for each change patch
#'
#' For each transition pair `A -> B` with a `B -> A` group present, a single
#' spatial-index query (`st_is_within_distance`) finds candidates within
#' `dist_m`; the area-ratio criterion is applied, then exact distances are
#' computed only for the survivors. Returns `id` (typed like `patch_id`) and
#' `dist`, `NA` where no partner qualifies.
#' @noRd
artifact_reciprocal <- function(patches, from_code, to_code, is_change,
                                area_m2, dist_m, ratio_min) {
  n <- nrow(patches)
  id <- patches$patch_id[rep(NA_integer_, n)]
  dist <- rep(NA_real_, n)
  geom <- sf::st_geometry(patches)

  key <- paste(from_code, to_code)
  rkey <- paste(to_code, from_code)
  for (g in unique(key[is_change])) {
    fwd <- which(is_change & key == g)
    rev <- which(is_change & key == rkey[fwd[1]])
    if (length(rev) == 0) next
    hits <- sf::st_is_within_distance(geom[fwd], geom[rev], dist = dist_m)
    for (a in seq_along(fwd)) {
      i <- fwd[a]
      j <- rev[hits[[a]]]
      if (length(j) == 0) next
      ratio <- pmin(area_m2[i], area_m2[j]) / pmax(area_m2[i], area_m2[j])
      j <- j[ratio >= ratio_min]
      if (length(j) == 0) next
      d <- as.numeric(sf::st_distance(geom[i], geom[j]))
      best <- order(d, -area_m2[j])[1]
      id[i] <- patches$patch_id[j[best]]
      dist[i] <- d[best]
    }
  }
  list(id = id, dist = dist)
}

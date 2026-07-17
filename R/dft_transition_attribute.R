#' Attribute transition patches from an overlay polygon layer
#'
#' Tag change patches (from [dft_transition_vectors()]) with columns from any
#' overlay polygon layer — fire perimeters, cutblocks, roads, tenures — to help
#' separate mapped transitions by cause. Generic by design: drift carries no
#' domain knowledge; the caller supplies the overlay, the columns to carry, and
#' (optionally) the temporal filter.
#'
#' The overlay is transformed to the CRS of `patches` before joining, and run
#' through [sf::st_make_valid()] first — real-world disturbance perimeters
#' routinely fail GEOS validity checks, which would otherwise break the
#' largest-overlap computation.
#'
#' @param patches An `sf` object of change patches, typically from
#'   [dft_transition_vectors()].
#' @param overlay An `sf` polygon layer to attribute from (e.g. fire
#'   perimeters, consolidated cutblocks).
#' @param cols Character vector of `overlay` column names to carry onto each
#'   patch. Must not collide with existing `patches` column names.
#' @param predicate Spatial predicate function used to match patches to
#'   overlay features, e.g. [sf::st_intersects()] (default) or
#'   [sf::st_within()]. Only applies with `match_mode = "all"`:
#'   largest-overlap assignment is inherently intersection-based
#'   (`sf::st_join(largest = TRUE)` ignores the join predicate), so combining
#'   a custom predicate with `match_mode = "largest"` is an error.
#' @param match_mode How a patch is assigned when it matches more than one
#'   overlay feature:
#'   - `"all"` (default) — plain left join; a patch straddling k overlay
#'     features appears k times (`patch_id` repeats).
#'   - `"largest"` — exactly one row per patch, assigned to the overlay
#'     feature with the greatest intersection area (via
#'     `sf::st_join(largest = TRUE)`; matching is by intersection, see
#'     `predicate`).
#' @param year_col Character or `NULL`. Name of a numeric year column in
#'   `overlay` used for temporal filtering. Must be supplied together with
#'   `interval`. For `Date` columns, extract a numeric year first.
#' @param interval Length-2 numeric or `NULL`. The transition interval, e.g.
#'   `c(2017, 2023)`. Overlay features whose `year_col` falls outside the
#'   interval (bounds inclusive) are dropped before joining; features with an
#'   `NA` year are also dropped. Patches from [dft_transition_vectors()] carry
#'   no interval columns, so the interval is always supplied explicitly.
#'
#' @return `patches` with the `cols` columns joined on (`NA` where a patch
#'   matches no overlay feature). Under `match_mode = "all"` a patch matching
#'   several overlay features is duplicated, one row per match; under
#'   `"largest"` the result has exactly one row per input patch.
#'
#' @seealso [dft_transition_vectors()] for producing the input patches.
#'
#' @export
#' @examples
#' r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
#' r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
#' classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
#' result <- dft_rast_transition(classified, from = "2017", to = "2020")
#' patches <- dft_transition_vectors(result$raster, changes_only = TRUE)
#'
#' # synthetic disturbance overlay covering the western half of the AOI
#' bb <- sf::st_bbox(patches)
#' west <- sf::st_sf(
#'   fire_year = 2018,
#'   geometry = sf::st_as_sfc(
#'     sf::st_bbox(c(bb["xmin"], bb["ymin"],
#'                   xmax = unname((bb["xmin"] + bb["xmax"]) / 2), bb["ymax"]),
#'                 crs = sf::st_crs(patches))
#'   )
#' )
#'
#' # tag each patch with the fire year where it overlaps (NA elsewhere)
#' tagged <- dft_transition_attribute(patches, west, cols = "fire_year",
#'                                    match_mode = "largest")
#' table(tagged$fire_year, useNA = "ifany")
#'
#' # temporal filter: only overlay features within the transition interval
#' tagged_2017_2020 <- dft_transition_attribute(
#'   patches, west, cols = "fire_year", match_mode = "largest",
#'   year_col = "fire_year", interval = c(2017, 2020)
#' )
dft_transition_attribute <- function(patches,
                                     overlay,
                                     cols,
                                     predicate = sf::st_intersects,
                                     match_mode = c("all", "largest"),
                                     year_col = NULL,
                                     interval = NULL) {
  match_mode <- match.arg(match_mode)

  if (!inherits(patches, "sf")) {
    cli::cli_abort(c(
      "{.arg patches} must be an {.cls sf} object.",
      "i" = "Use {.fn dft_transition_vectors} to create change patches."
    ))
  }
  if (!inherits(overlay, "sf")) {
    cli::cli_abort("{.arg overlay} must be an {.cls sf} object.")
  }
  if (!is.function(predicate)) {
    cli::cli_abort(
      "{.arg predicate} must be a function, e.g. {.fn sf::st_intersects}."
    )
  }
  if (identical(match_mode, "largest") &&
        !identical(predicate, sf::st_intersects)) {
    cli::cli_abort(c(
      "{.arg predicate} cannot be combined with {.code match_mode = \"largest\"}.",
      "i" = "Largest-overlap assignment is intersection-based:
             {.code sf::st_join(largest = TRUE)} ignores the join predicate."
    ))
  }
  if (!is.character(cols) || length(cols) == 0 || anyNA(cols)) {
    cli::cli_abort(
      "{.arg cols} must be a non-empty character vector of {.arg overlay} column names."
    )
  }
  cols_missing <- setdiff(cols, names(overlay))
  if (length(cols_missing) > 0) {
    cli::cli_abort(
      "{.arg cols} not found in {.arg overlay}: {.val {cols_missing}}."
    )
  }
  if (attr(overlay, "sf_column") %in% cols) {
    cli::cli_abort(
      "{.arg cols} must not include the {.arg overlay} geometry column
       {.val {attr(overlay, 'sf_column')}}."
    )
  }
  cols_clash <- intersect(cols, names(patches))
  if (length(cols_clash) > 0) {
    cli::cli_abort(c(
      "{.arg cols} collide with existing {.arg patches} columns: {.val {cols_clash}}.",
      "i" = "Rename the overlay columns before attributing."
    ))
  }
  if (is.na(sf::st_crs(patches)) || is.na(sf::st_crs(overlay))) {
    cli::cli_abort("Both {.arg patches} and {.arg overlay} must have a CRS.")
  }
  if (is.null(year_col) != is.null(interval)) {
    cli::cli_abort(
      "{.arg year_col} and {.arg interval} must be supplied together."
    )
  }

  # Temporal filter: keep overlay features whose year falls within the
  # transition interval (bounds inclusive); NA years are dropped
  if (!is.null(year_col)) {
    if (!is.character(year_col) || length(year_col) != 1 ||
          !year_col %in% names(overlay)) {
      cli::cli_abort(
        "{.arg year_col} must name a single column in {.arg overlay}."
      )
    }
    if (!is.numeric(interval) || length(interval) != 2 || anyNA(interval)) {
      cli::cli_abort(
        "{.arg interval} must be a length-2 numeric vector with no NA."
      )
    }
    if (interval[1] > interval[2]) {
      cli::cli_abort(
        "{.arg interval} must be increasing, got {.val {interval[1]}} > {.val {interval[2]}}."
      )
    }
    if (!is.numeric(overlay[[year_col]])) {
      cli::cli_abort(c(
        "{.arg overlay} column {.val {year_col}} must be numeric.",
        "i" = "Extract a numeric year first, e.g. with {.code as.numeric(format(date, \"%Y\"))}."
      ))
    }
    yr <- overlay[[year_col]]
    overlay <- overlay[!is.na(yr) & yr >= interval[1] & yr <= interval[2], ]
  }

  # Nothing to join: return patches with typed-NA cols so the schema matches
  # the joined path (indexing with NA preserves each column's type)
  if (nrow(patches) == 0 || nrow(overlay) == 0) {
    for (col in cols) {
      patches[[col]] <- overlay[[col]][rep(NA_integer_, nrow(patches))]
    }
    return(patches)
  }

  overlay_sel <- sf::st_make_valid(
    sf::st_transform(overlay[, cols], sf::st_crs(patches))
  )
  suppressWarnings(sf::st_join(
    patches, overlay_sel,
    join = predicate,
    left = TRUE,
    largest = identical(match_mode, "largest")
  ))
}

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
#' @param time_col Character or `NULL`. Name of a **numeric** time column in
#'   `overlay` used for temporal filtering (e.g. `FIRE_YEAR`, `HARVEST_YEAR`).
#'   Must be supplied together with `time_interval`, and both must be on the
#'   **same numeric scale** (see Details). `NULL` (default) skips the filter.
#' @param time_interval Length-2 numeric or `NULL`. The transition interval on
#'   the same scale as `time_col`, e.g. `c(2017, 2023)` for calendar years.
#'   Overlay features whose `time_col` falls outside the interval (both bounds
#'   inclusive) are dropped before joining; features with an `NA` time are also
#'   dropped. Patches from [dft_transition_vectors()] carry no time columns, so
#'   the interval is always supplied explicitly.
#'
#' @details
#' # Temporal filter — how `time_col` and `time_interval` must be presented
#'
#' The filter is a plain numeric comparison
#' (`overlay[[time_col]] >= time_interval[1] & <= time_interval[2]`), so it is
#' scale-agnostic — the numbers may be calendar years, decimal years, months,
#' or epoch offsets — but **both arguments must be numeric and on the same
#' scale**. `time_col` must name a `numeric` (integer or double) column;
#' passing a `Date` or `POSIXct` column is a hard error, not a silent
#' mis-comparison. Values are not coerced or rounded: a decimal year like
#' `2018.5` is compared as-is.
#'
#' To filter on dates, convert to a numeric axis first, on **both** the column
#' and the interval:
#'
#' - Calendar year (simplest for annual disturbance data):
#'   ```
#'   overlay$yr <- as.numeric(format(overlay$burn_date, "%Y"))
#'   dft_transition_attribute(..., time_col = "yr", time_interval = c(2017, 2023))
#'   ```
#' - Epoch days (`Date` stores days since 1970-01-01, so `as.numeric()` is the
#'   coercion):
#'   ```
#'   overlay$t <- as.numeric(overlay$burn_date)               # days since epoch
#'   dft_transition_attribute(..., time_col = "t",
#'     time_interval = as.numeric(as.Date(c("2017-01-01", "2023-12-31"))))
#'   ```
#'   (`POSIXct` coerces to *seconds* since epoch — keep the interval in seconds
#'   to match.)
#'
#' Mixing scales (e.g. epoch-day column against a `c(2017, 2023)` year
#' interval) does not error — it silently matches nothing. Keep both on one
#' axis.
#'
#' @section Limitations:
#' - `overlay` is treated as a polygon layer. Passing point or line geometries
#'   is not supported: `match_mode = "largest"` compares intersection *area*,
#'   which is zero for non-polygon overlays. Use a point-in-polygon join
#'   directly for such cases.
#' - Temporal filtering is numeric-only; `Date`/`POSIXct` columns must be
#'   coerced by the caller (see Details).
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
#'   time_col = "fire_year", time_interval = c(2017, 2020)
#' )
dft_transition_attribute <- function(patches,
                                     overlay,
                                     cols,
                                     predicate = sf::st_intersects,
                                     match_mode = c("all", "largest"),
                                     time_col = NULL,
                                     time_interval = NULL) {
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
  if (is.null(time_col) != is.null(time_interval)) {
    cli::cli_abort(
      "{.arg time_col} and {.arg time_interval} must be supplied together."
    )
  }

  # Temporal filter: keep overlay features whose time falls within the
  # transition interval (bounds inclusive); NA times are dropped
  if (!is.null(time_col)) {
    if (!is.character(time_col) || length(time_col) != 1 ||
          !time_col %in% names(overlay)) {
      cli::cli_abort(
        "{.arg time_col} must name a single column in {.arg overlay}."
      )
    }
    if (!is.numeric(time_interval) || length(time_interval) != 2 ||
          anyNA(time_interval)) {
      cli::cli_abort(
        "{.arg time_interval} must be a length-2 numeric vector with no NA."
      )
    }
    if (time_interval[1] > time_interval[2]) {
      cli::cli_abort(
        "{.arg time_interval} must be increasing, got {.val {time_interval[1]}} > {.val {time_interval[2]}}."
      )
    }
    if (!is.numeric(overlay[[time_col]])) {
      cli::cli_abort(c(
        "{.arg overlay} column {.val {time_col}} must be numeric.",
        "i" = "Convert dates to a numeric axis first, e.g.
               {.code as.numeric(format(date, \"%Y\"))} for calendar year or
               {.code as.numeric(date)} for epoch days."
      ))
    }
    tv <- overlay[[time_col]]
    overlay <- overlay[!is.na(tv) &
                         tv >= time_interval[1] & tv <= time_interval[2], ]
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

# Attribute transition patches from an overlay polygon layer

Tag change patches (from
[`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md))
with columns from any overlay polygon layer — fire perimeters,
cutblocks, roads, tenures — to help separate mapped transitions by
cause. Generic by design: drift carries no domain knowledge; the caller
supplies the overlay, the columns to carry, and (optionally) the
temporal filter.

## Usage

``` r
dft_transition_attribute(
  patches,
  overlay,
  cols,
  predicate = sf::st_intersects,
  match_mode = c("all", "largest"),
  time_col = NULL,
  time_interval = NULL
)
```

## Arguments

- patches:

  An `sf` object of change patches, typically from
  [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md).

- overlay:

  An `sf` polygon layer to attribute from (e.g. fire perimeters,
  consolidated cutblocks).

- cols:

  Character vector of `overlay` column names to carry onto each patch.
  Must not collide with existing `patches` column names.

- predicate:

  Spatial predicate function used to match patches to overlay features,
  e.g.
  [`sf::st_intersects()`](https://r-spatial.github.io/sf/reference/geos_binary_pred.html)
  (default) or
  [`sf::st_within()`](https://r-spatial.github.io/sf/reference/geos_binary_pred.html).
  Only applies with `match_mode = "all"`: largest-overlap assignment is
  inherently intersection-based (`sf::st_join(largest = TRUE)` ignores
  the join predicate), so combining a custom predicate with
  `match_mode = "largest"` is an error.

- match_mode:

  How a patch is assigned when it matches more than one overlay feature:

  - `"all"` (default) — plain left join; a patch straddling k overlay
    features appears k times (`patch_id` repeats).

  - `"largest"` — exactly one row per patch, assigned to the overlay
    feature with the greatest intersection area (via
    `sf::st_join(largest = TRUE)`; matching is by intersection, see
    `predicate`).

- time_col:

  Character or `NULL`. Name of a **numeric** time column in `overlay`
  used for temporal filtering (e.g. `FIRE_YEAR`, `HARVEST_YEAR`). Must
  be supplied together with `time_interval`, and both must be on the
  **same numeric scale** (see Details). `NULL` (default) skips the
  filter.

- time_interval:

  Length-2 numeric or `NULL`. The transition interval on the same scale
  as `time_col`, e.g. `c(2017, 2023)` for calendar years. Overlay
  features whose `time_col` falls outside the interval (both bounds
  inclusive) are dropped before joining; features with an `NA` time are
  also dropped. Patches from
  [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  carry no time columns, so the interval is always supplied explicitly.

## Value

`patches` with the `cols` columns joined on (`NA` where a patch matches
no overlay feature). Under `match_mode = "all"` a patch matching several
overlay features is duplicated, one row per match; under `"largest"` the
result has exactly one row per input patch.

## Details

The overlay is transformed to the CRS of `patches` before joining, and
run through
[`sf::st_make_valid()`](https://r-spatial.github.io/sf/reference/valid.html)
first — real-world disturbance perimeters routinely fail GEOS validity
checks, which would otherwise break the largest-overlap computation.

## Temporal filter — how `time_col` and `time_interval` must be presented

The filter is a plain numeric comparison
(`overlay[[time_col]] >= time_interval[1] & <= time_interval[2]`), so it
is scale-agnostic — the numbers may be calendar years, decimal years,
months, or epoch offsets — but **both arguments must be numeric and on
the same scale**. `time_col` must name a `numeric` (integer or double)
column; passing a `Date` or `POSIXct` column is a hard error, not a
silent mis-comparison. Values are not coerced or rounded: a decimal year
like `2018.5` is compared as-is.

To filter on dates, convert to a numeric axis first, on **both** the
column and the interval:

- Calendar year (simplest for annual disturbance data):

      overlay$yr <- as.numeric(format(overlay$burn_date, "%Y"))
      dft_transition_attribute(..., time_col = "yr", time_interval = c(2017, 2023))

- Epoch days (`Date` stores days since 1970-01-01, so
  [`as.numeric()`](https://rdrr.io/r/base/numeric.html) is the
  coercion):

      overlay$t <- as.numeric(overlay$burn_date)               # days since epoch
      dft_transition_attribute(..., time_col = "t",
        time_interval = as.numeric(as.Date(c("2017-01-01", "2023-12-31"))))

  (`POSIXct` coerces to *seconds* since epoch — keep the interval in
  seconds to match.)

Mixing scales (e.g. epoch-day column against a `c(2017, 2023)` year
interval) does not error — it silently matches nothing. Keep both on one
axis.

## Limitations

- `overlay` is treated as a polygon layer. Passing point or line
  geometries is not supported: `match_mode = "largest"` compares
  intersection *area*, which is zero for non-polygon overlays. Use a
  point-in-polygon join directly for such cases.

- Temporal filtering is numeric-only; `Date`/`POSIXct` columns must be
  coerced by the caller (see Details).

## See also

[`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
for producing the input patches.

## Examples

``` r
r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
result <- dft_rast_transition(classified, from = "2017", to = "2020")
patches <- dft_transition_vectors(result$raster, changes_only = TRUE)

# synthetic disturbance overlay covering the western half of the AOI
bb <- sf::st_bbox(patches)
west <- sf::st_sf(
  fire_year = 2018,
  geometry = sf::st_as_sfc(
    sf::st_bbox(c(bb["xmin"], bb["ymin"],
                  xmax = unname((bb["xmin"] + bb["xmax"]) / 2), bb["ymax"]),
                crs = sf::st_crs(patches))
  )
)

# tag each patch with the fire year where it overlaps (NA elsewhere)
tagged <- dft_transition_attribute(patches, west, cols = "fire_year",
                                   match_mode = "largest")
table(tagged$fire_year, useNA = "ifany")
#> 
#> 2018 <NA> 
#>   46   73 

# temporal filter: only overlay features within the transition interval
tagged_2017_2020 <- dft_transition_attribute(
  patches, west, cols = "fire_year", match_mode = "largest",
  time_col = "fire_year", time_interval = c(2017, 2020)
)
```

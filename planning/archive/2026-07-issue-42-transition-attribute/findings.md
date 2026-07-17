# Findings — dft_transition_attribute(): tag transition patches from an overlay layer (optional temporal filter) (#42)

## Issue context

### Problem

`dft_transition_vectors()` produces per-patch change polygons (from_class -> to_class, area,
optional zone), but there is no way to attribute *why* a change happened. A driver that wants to
separate fire from harvest from classification noise has to hand-roll spatial joins against
external overlays (fire perimeters, cutblocks, roads) every time.

### Proposed Solution

A generic helper that tags transition patches from an overlay polygon layer — no domain context,
reusable for any disturbance/context source:

```r
dft_transition_attribute(patches, overlay, cols = ..., predicate = st_intersects,
                         year_col = NULL, interval = NULL)
```

- `patches` — sf from `dft_transition_vectors()`.
- `overlay` — any polygon sf.
- `cols` — overlay columns to carry onto each patch (e.g. `fire_year`, `burn_severity`).
- `predicate` / area-majority option — how a patch is assigned when it straddles overlay polys.
- `year_col` + `interval` — optional temporal filter: keep only overlay features whose year
  falls within the transition interval (e.g. a fire in 2022 attributes a 2017->2023 loss; a 2012
  fire does not).

Returns `patches` with the overlay columns joined (NA where no overlap).

### Why generic (not fire-specific)

The same call attributes fire (`prot_historical_fire_polys` + `FIRE_YEAR`), harvest
(consolidated cutblocks + `HARVEST_YEAR`), roads, tenures, any context layer. drift stays free
of BC/domain knowledge; the driver supplies the tables + interval logic. Surfaced from the
floodplains driver (PCEA: 28% of loss is a 2022 burn; confined-valley groups: <1%).

## spacehakr evaluation (rejected as dependency)

- `spacehakr::spk_join()` covers ~60-70% of the need: predicate `st_join`, mask column
  selection, left-join-NA contract. But:
  - Its temporal filtering is `%in%`-membership on one column — cannot express an interval,
    and cannot express per-row join conditions.
  - Its one-to-many `collapse` option `toString()`-concatenates duplicate values into a comma
    string (with type-change warning) — exactly wrong for attribution. No area-majority logic.
  - The reusable part is a thin veneer over `sf::st_join` + dplyr, both already in drift Imports.
- Taking an Imports on an experimental, barely-used, GitHub-only package couples released drift
  to spacehakr's uncertain fate. Decision: implement natively; steal the left-join-NA contract
  and predicate-as-function *patterns* only.
- spacehakr fate (side note, user-level): pre-drift grab-bag; audit `grep -r "spk_"` across
  repos, hoist live functions, likely archive. Not part of this issue.

## Codebase exploration (2026-07-17)

- `dft_transition_vectors()` (R/dft_transition_vectors.R) returns sf: `patch_id` (int dense
  1..n), `transition` (chr "Trees -> Rangeland"), `area_ha` (numeric,
  `as.numeric(st_area)*1e-4`), geometry (projected CRS), optional zone col. **No interval/year
  columns** — interval must be user-supplied in the new function.
- Zones pattern (dft_transition_vectors.R:163-166): `st_transform(zones[zone_col], st_crs(out))`
  then `suppressWarnings(st_intersection(...))` — precedent for silent CRS transform +
  suppressWarnings.
- No units pkg anywhere; areas are bare numerics with `switch(unit, "m2"=1, "ha"=1e-4, "km2"=1e-6)`.
- Validation style is transitional: new functions (dft_rast_break, dft_rast_trend, dft_stac_*)
  use `cli::cli_abort(c(...))` with `{.fn}`/`{.val}` markup + `match.arg()` — follow that.
- No existing predicate-arg or area-majority code. `sf::st_join(..., largest = TRUE)` natively
  implements area-majority — both match modes collapse to one st_join call.
- Roxygen: markdown on, `@seealso [fn()]` (no `@family`, no `@examplesIf`), runnable
  `@examples` off `system.file("extdata", ...)` (example_2017.tif, example_2020.tif,
  example_aoi.gpkg).
- Tests: fixture chain classify -> transition -> vectors on bundled rasters; synthetic sf from
  `terra::as.polygons(terra::ext(...))`; exact-count regression assertions; no network skips.
- `_pkgdown.yml` has no `reference:` section — auto index, no edit needed.
- `match` rejected as param name (shadows base `match()`, per code-check base-name-shadowing
  convention); user approved `match_mode` enum over sf-style `largest` logical for
  extensibility.

# Task: dft_transition_attribute(): tag transition patches from an overlay layer (optional temporal filter) (#42)

`dft_transition_vectors()` produces per-patch change polygons (from_class -> to_class, area,
optional zone), but there is no way to attribute *why* a change happened. A driver that wants to
separate fire from harvest from classification noise has to hand-roll spatial joins against
external overlays (fire perimeters, cutblocks, roads) every time.

Approved signature:

```r
dft_transition_attribute(patches, overlay, cols, predicate = sf::st_intersects,
                         match_mode = c("all", "largest"),
                         year_col = NULL, interval = NULL)
```

## Phase 1: Tests first

- [x] Create `tests/testthat/test-dft_transition_attribute.R` with shared fixture: bundled-raster chain `dft_rast_classify` -> `dft_rast_transition` -> `dft_transition_vectors(changes_only = TRUE)` (mirrors test-dft_transition_vectors.R)
- [x] Build synthetic overlay fixture: `sf::st_as_sf(terra::as.polygons(terra::ext(...)))` sub-extents with `fire_year` (numeric) + `cause` (character) cols; one adjacent-poly pair a known patch straddles unevenly
- [x] Test: returns sf; `cols` appended; `patch_id`/`transition`/`area_ha` preserved; NA cols where no overlap
- [x] Test: `match_mode = "largest"` -> exactly `nrow(patches)` rows; straddling patch gets larger-overlap poly's attribute
- [x] Test: `match_mode = "all"` duplicates straddling patch row (exact count)
- [x] Test: temporal filter — inclusive bounds at both ends; out-of-interval overlay -> all-NA cols, nrow preserved
- [x] Test: overlay in EPSG:4326 attributes identically to pre-projected overlay (silent transform)
- [x] Test: custom `predicate` (`sf::st_within`) honoured in `"all"` mode
- [x] Test: 0-row patches -> 0-row sf with correctly-typed `cols`
- [x] Test: validation errors — non-sf inputs; `cols` missing/colliding; `year_col` without `interval` (and vice versa); bad `interval` (length/type/reversed); non-numeric year column; bad `match_mode`
- [x] Confirm tests fail for the right reason (function not found)

## Phase 2: Implementation

- [x] Create `R/dft_transition_attribute.R` with approved signature
- [x] Validation block: `cli::cli_abort` with `{.fn}`/`{.val}`/`{.arg}` markup; `match.arg(match_mode)`; predicate-is-function; cols checks; paired year_col+interval; CRS present
- [x] Temporal filter (inclusive numeric interval, NA years dropped)
- [x] Short-circuit path (typed-NA cols) + join path (subset -> transform -> make_valid -> st_join)
- [x] Test file green; full `devtools::test()` no regressions

## Phase 3: Docs and examples

- [x] Roxygen: params incl. duplicate-row semantics of `"all"`, one-row guarantee of `"largest"`, inclusive bounds, numeric-years-only, silent CRS transform, `st_make_valid` in `@details`; `@seealso [dft_transition_vectors()]` + reciprocal in `R/dft_transition_vectors.R`
- [x] Runnable `@examples` from bundled data with inline synthetic overlay; with and without `interval`; no `\dontrun`
- [x] `devtools::document()`; NAMESPACE gains export
- [x] `devtools::check()` clean

## Phase 4: Release bookkeeping

- [x] NEWS.md entry (new unreleased heading): generic overlay attribution, both match modes, temporal filter, ref #42
- [x] DESCRIPTION version bump 0.7.0 -> 0.8.0 as FINAL commit

## Out of scope

Date/POSIXct year columns; multi-value aggregation (concatenating fire years); any BC/fire/harvest domain helpers; units-package areas; spacehakr dependency.

## Validation

- [x] Tests pass
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

# Task: Detect geometric edge/misregistration artifacts in transitions (sliver width, boundary-hugging, reciprocal pairs) (#44)

Year-to-year classified land cover carries geometric artifacts that look like real transitions but are misalignment, not change: one-sided edge shifts (a thin band along a boundary that moved by a pixel between epochs) and reciprocal/compensating shifts (Trees -> Water on one bank, Water -> Trees on the other). Both inflate reported change and concentrate on long linear boundaries. `patch_area_min` filters on area, which cannot separate a 15 ha sliver from a 15 ha clearing; the spectral route (#30) needs a Sentinel-2 cube and cannot express the reciprocal relationship. This adds `dft_transition_artifact()`, which **tags** patches from `dft_transition_vectors()` with geometric evidence derivable from the transition raster alone and lets the caller decide.

## Design (approved 2026-09-04)

```r
dft_transition_artifact(patches, transition,
                        width_max = 1.5,                 # px; below -> flag_sliver
                        boundary_dist_max = 1,           # px from the from-epoch A|B interface
                        reciprocal = TRUE,
                        reciprocal_dist_max = 5,         # px; partner search radius
                        reciprocal_area_ratio_min = 0.5) # min(area)/max(area) for "comparable"
```

Adds `width_m`, `width_px`, `flag_sliver`, `boundary_frac`, `flag_boundary`, `reciprocal_id`,
`reciprocal_dist_m`, `flag_reciprocal`. No composed `flag_artifact` — the caller composes.
Stable (`A -> A`) rows: width computed, everything else `NA`.

Deliberate deviation from the issue: reciprocity uses `st_is_within_distance` (partner within
`reciprocal_dist_max` px with the exact reverse label and comparable area), not "shares a
boundary" — the river case has the two bands on opposite banks separated by the stable channel,
so they touch only when the river is one pixel wide.

## Phase 1: Fixtures and failing tests
- [ ] `tests/testthat/helper-artifact.R`: `make_transition(from_mat, to_mat, res = 10)` builds a projected (EPSG:32609) two-layer classified list and returns `dft_rast_transition(...)` with a synthetic `class_table` (Trees/Rangeland/Water/Bare) — proves "any factor raster", not IO LULC
- [ ] Fixture A — one-sided 1-px shift of a Trees|Rangeland boundary → one `Trees -> Rangeland` band: `flag_sliver`, `boundary_frac == 1`, `flag_boundary`, no reciprocal
- [ ] Fixture B — 5-px river shifted 1 px → `Water -> Trees` and `Trees -> Water` bands, equal area, 4 px apart: both flagged reciprocal, each the other's `reciprocal_id`; `reciprocal_dist_max = 3` un-flags them; `reciprocal = FALSE` yields `NA` columns
- [ ] Fixture C — 1-px road (`-> Bare`) cutting across the Fixture A boundary: road patch is `flag_sliver` **but not** `flag_boundary` (`boundary_frac == 0`); the band still is
- [ ] Fixture D — 20×20 interior clearing: no flags; width 10 px
- [ ] Width metric pinned on known shapes (0.50 / 0.95 / 10.0 px); `boundary_dist_max = 2` grows `boundary_frac` on a 2-px band
- [ ] Bundled-data test: 2017→2023 `changes_only`, `expect_identical(sum(width_px < 1.5), 75L)`; with `patch_area_min = 5000` the surviving `Trees -> Rangeland` sliver has `width_px < 1.5`
- [ ] Stable rows get `NA` metrics; zero-row input returns the full schema; error paths (non-sf, non-factor raster, CRS mismatch, duplicated `patch_id`, bad params)

## Phase 2: Implement `dft_transition_artifact()`
- [ ] `R/dft_transition_artifact.R` — validation, width, boundary (focal per to-class + rasterize + zonal), reciprocity (`st_is_within_distance` on reverse-label subset), column assembly
- [ ] roxygen: params, `@return` column table, `@details` on each signature and on the unfiltered-raster requirement, `@seealso` to `dft_transition_vectors()` / `dft_transition_attribute()` and the trajectory vignette as the independent spectral route; runnable `@examples` on bundled data including the caller-composed `flag_artifact` one-liner
- [ ] `devtools::document()` — confirm exactly one new `export()` and one new `.Rd`
- [ ] All Phase 1 tests pass; `lintr::lint_package()` clean on the new file

## Phase 3: Documentation
- [ ] `vignettes/land-cover-change.Rmd`: new subsection after "Filtering Classification Noise" — table of the surviving `patch_area_min = 5000` sliver, share of patches vs share of area under 1.5 px, a map of flagged patches, and the pointer to the trajectory vignette's "outline with no red" as the spectral confirmation
- [ ] `@seealso` back-links from `dft_transition_vectors()` and `dft_transition_attribute()`
- [ ] Render the vignette locally (`devtools::install()` first) and read the output

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

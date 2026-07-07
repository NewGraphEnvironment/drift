# Task: dft_transition_vectors OOMs on large-extent rasters (processes full grid per class) (#27)

`dft_transition_vectors()` processes the **entire raster grid** rather than the ~2% of
cells that hold data, and does so **once per transition class**. On a large-extent
floodplain this exhausts memory and the R process is OOM-killed.

## Phase 1: Single-pass patches(values = TRUE) rewrite

- [x] Replace the per-class/per-patch loop (`R/dft_transition_vectors.R:68-125`) with single-pass `terra::patches(x, directions = 8, values = TRUE)` → `terra::as.polygons()` → sparse pid→label map via `terra::cells()` + `terra::extract()`; keep signature, validation, `patch_area_min` filter, zones block, and return columns unchanged; drop rows whose value has no `cats()` entry (old behavior)
- [x] Add `terra (>= 1.8-10)` floor to DESCRIPTION Imports (patches(values=TRUE) edge-wraparound bug fixed in 1.8-10 — correctness, not nicety)
- [x] New tests in `tests/testthat/test-dft_transition_vectors.R`: synthetic decomposition test (~60x80 factor raster with engineered topology — diagonal-only joins, adjacent different classes, crossed diagonals, a code-0 class, holes) asserting equal patch count / per-class counts / sorted areas vs a brute-force per-class reference computed in-test; all-NA raster returns empty sf with correct columns + CRS; fixture regression guard (185 patches / 123.11 total ha)
- [x] All 10 existing tests stay green unchanged (behavior contract)

## Phase 2: Docs + release

- [x] Roxygen: note single-pass implementation and that `patch_id` numbering is scan-order; `devtools::document()`
- [x] NEWS.md 0.2.4: OOM fix (grid-cell x n-class x n-patch churn → single pass), identical output guarantee, patch_id ordering note, new terra floor
- [x] File follow-up issue for `dft_rast_transition()`'s full-grid value pipeline (same OOM class; needs its own refactor + harness) — filed as #28
- [x] `lintr` clean + full `devtools::test()` pass (211 pass; one pre-existing vignette lint, untouched by this branch)
- [x] Version bump to 0.2.4 in DESCRIPTION as final commit

## Validation

- [x] Tests pass
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

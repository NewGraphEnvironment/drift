# Findings — dft_transition_vectors OOMs on large-extent rasters (#27)

## Issue context

### Summary

`dft_transition_vectors()` processes the **entire raster grid** rather than the ~2% of
cells that hold data, and does so **once per transition class**. On a large-extent
floodplain this exhausts memory and the R process is OOM-killed.

### Where

`R/dft_transition_vectors.R`. For each transition class in `terra::cats(x)` it:
- allocates `rep(NA_integer_, terra::ncell(x))` (a full-grid vector), and
- runs `terra::patches(r_mask, directions = 8)` over the full grid,
then finally `terra::as.polygons()` over a full-grid patch-id raster. Nothing is cropped
to the data extent, and `trim()` does not help when the data follows a mainstem across
the whole bounding box.

### Repro / evidence

Upper Fraser (UFRA) chinook `ch_ff04` floodplain via a per-area pipeline:
- transition raster: **8637 x 11875 = 102.6M cells**, extent 119 x 86 km
- non-NA (actual transitions): **1.87%** of the grid
- distinct transition classes (loop iterations): **56**
- `terra::trim(x)` returns **100%** of the grid (data spans the full bbox)

Result: OOM-killed at `dft_transition_vectors()`. The smaller MORR floodplain
(74.0M-cell grid, fewer classes) completes, so this is grid-cell-count driven, not
floodplain-area driven.

### Fix options (from issue)

1. **Tile internally**: split into column/row tiles bounded to N cells, vectorize each,
   `rbind`. (Stop-gap applied in the pipeline driver.)
2. **Work on sparse cells**: derive patch ids from `which(!is.na(vals))` indices;
   run `patches()` on a cropped/masked window per class.
3. **Single `as.polygons()` per class-set** using a combined patch-id raster built from
   sparse indices.

## Plan-mode exploration (2026-07-07)

### Failure anatomy (beyond the issue)

- The sleeper is the per-patch remap loop (`R/dft_transition_vectors.R:95-101`):
  `patch_ids[valid & p_vals == pid] <- offset` allocates TWO full-grid logical vectors
  per patch. Thousands of patches → TBs of allocation churn. The current implementation
  scales as ncell × n_patches, not just ncell × n_classes.
- Benchmarked current impl: 122 s / 4.32 GB at 24M cells (48 classes, ~2% non-NA,
  1,232 patches). Extrapolates to ~18+ GB at the real 102.6M-cell case → matches OOM.
- `dft_rast_transition()` (producer) has the same disease independently: 6+ full-grid
  R vectors including two full-grid character vectors (`name_from`/`name_to`,
  R/dft_rast_transition.R:90-109, ~800 MB each at 102.6M cells) regardless of options,
  plus a full-grid `patches()` path when `patch_area_min` is set (:118-137, :188-205).
  Needs its own refactor + correctness harness → follow-up issue, not #27 scope.

### Approach evaluation (empirical, terra 1.9.11, /usr/bin/time -l)

| Approach | 24M cells | Output vs current |
|---|---|---|
| current | 122 s / 4.32 GB | reference |
| **single-pass `patches(values = TRUE)` (chosen)** | **2.2 s / 1.94 GB** | **identical** |
| sparse + per-class window (issue opt 2) | 54 s / 7.24 GB | identical |
| `as.polygons(dissolve)` + `st_cast` explode | 2.1 s / 1.13 GB | WRONG (4-connected) |

- `terra::patches(x, directions = 8, values = TRUE)` computes 8-connected components of
  same-valued cells in one C++ pass — verified: respects class boundaries, merges
  diagonal same-class cells (incl. crossed diagonals), treats 0 as a real class,
  factor input fine, all-NA safe.
- Verified identical to current output on real fixtures (326x314, 19 classes): 185
  patches, identical per-class counts, sorted areas, total 123.11 ha, union geometry
  `st_equals`; `patch_area_min = 1000` → 57 patches both ways.
- Sparse+window degenerates on mainstem-shaped data: every class's bounding window is
  nearly the full grid, so it does full-grid work × n_classes.
- Polygonize+explode disqualified: GDAL polygonize is 4-connected (no 8-conn option in
  `terra::as.polygons`), silently splits diagonal joins (275 vs 185 patches on fixtures)
  and changes `patch_area_min` semantics.

### Load-bearing details for implementation

- **terra `(>= 1.8-10)` floor is a correctness requirement**: `values = TRUE` added in
  1.8-5; edge-wraparound bug (patches falsely connected across left/right raster edges,
  rspatial/terra#1675) fixed in 1.8-10. Older terra would silently corrupt patches.
- pid→label mapping: `terra::cells(p)` + `terra::extract()` on the factor raster touches
  only non-NA cells and returns labels straight from `cats()` — no full-grid pull, no
  label drift.
- Drop rows whose value has no `cats()` entry after mapping (old code silently skipped
  them via the `lvls` loop).
- `patch_id` numbering becomes scan-order rather than class-major — docs only promise
  "connected component ID"; no test or documented behavior depends on ordering.
- All-NA early return moves after `as.polygons()` (0 features → same empty sf).
- Bit-identical output verified under `terraOptions(memmax = 0.3)`. At the real
  102.6M-cell size expect ~7-8 GB peak (dominated by `as.polygons`) vs OOM before.

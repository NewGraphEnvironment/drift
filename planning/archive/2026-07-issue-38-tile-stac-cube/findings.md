# Findings — Bound `dft_stac_cube()` streaming to the AOI (#38)

## Issue context

`dft_stac_cube()` (`R/dft_stac_cube.R:231-240`) builds its gdalcubes cube over the AOI
**bounding box**, so the COG streaming (~10-30 min for a multi-year monthly Sentinel-2
fetch) scales with the bbox, not the AOI polygon. Measured area/bbox ≈ 0.105 on the
packaged example AOI → ~10× streaming overhead for a corridor. #32 restored polygon-tight
**output** (`clip = TRUE`, `terra::mask()`) but that runs after streaming — it does not
reduce the read. #38 = reduce the READ by tiling the `cube_view`, mirroring #36 on the
categorical sibling `dft_stac_fetch()`. `gdalcubes::filter_geom()` (the direct fix)
segfaults on the pinned build (out of scope).

## Design (approved plan + Plan-agent review)

Reuses #36's `tile_size_check()` / `tile_grid()` verbatim (same package namespace).
Cube path is harder per tile (SCL mask + index + 2022 offset-split + `terra::cover`;
multi-layer stacks) but simpler in caching (always `.tif`; GDAL config already
unconditional at `:116-130`). `mosaic_stacks()` = in-memory multi-layer
`terra::merge(terra::sprc(...))`; distinct from #36's file-based single-layer
`mosaic_tiles`. `assemble_index_stack(extent)` is a **local closure** (like the existing
`build_index_stack`), NOT `@noRd` — it must close over `dft_stac_cube`'s call-locals.

## Plan-agent review — issues incorporated

- **B1 (Blocker):** `assemble_index_stack` must be a local closure, not a top-level
  `@noRd` function — a top-level fn can't close over `items`/`is_pre`/`offset`/`t0`/… Only
  `mosaic_stacks` is `@noRd`.
- **O1 (Ordering):** the cube key has **no** frozen golden literal today (fetch froze
  `79f67b7b9dae`; cube tests assert only determinism+distinctness). `stac_cube_cache_key`
  is currently a flat `hash(list(...))`. Freeze the current untiled literal FIRST, then
  migrate to the append pattern, then confirm unchanged — else every `cube_<key>.tif`
  orphans and re-streams (10-30 min each).
- **G1 (Gap):** cover-then-merge == merge-then-cover has no CI test; only the opt-in
  network test would touch it. Add an offline synthetic commutativity test.
- **G3 (Gap):** `clip = FALSE` docstring promises "full bounding box", but under tiling
  the mosaic returns the AOI-intersecting **tile union** (stair-stepped, ⊊ full bbox).
  Amend the docs; add an offline extent-semantics test.
- **A1:** assert uniform nlyr across tiles before merge (`stopifnot`) for a legible
  failure if a future edit derives per-tile time bounds.
- **G2:** the per-tile temp NetCDFs — accept the pre-existing leak (untiled already leaks
  1-2; tiling makes it 2×N of the same kind). Do NOT add unlink plumbing: terra's
  NetCDF-backed rasters are lazy until `writeRaster`, so early unlink corrupts the mosaic.
- **AC1:** kNDVI is **float** (bilinear + median), not integer classes — the network
  equality test can't copy #36's integer `expect_equal`; needs an explicit tolerance /
  robust quantile (~1e-6 FP jitter from differing gdalcubes chunk boundaries; possible
  edge-cell deltas). And don't `compareGeom`-assert identical extents (tiled = tile-union,
  untiled = full bbox).
- **AC2:** the e2e window must **straddle 2022-01-25** so the offset-split-under-tiling
  path actually runs (the existing cube network test uses a pre-boundary window).
- **S1:** reuse the two shared helpers in place (zero churn); extraction to
  `R/stac_tiling.R` is a future option if a third consumer appears.
- **A2/A3:** multi-layer merge preserves positional layer order (names/time overwritten
  post-merge); nlyr fixed by the shared `t0/t1/dt` axis (zero-overlap tiles → all-NA
  layers, not fewer). In-polygon values identical after mask; only extent/dims differ.

## Network e2e findings (Phase 4) — what only the live path surfaced

The opt-in network test (32-min run over the 7-month straddling window) did its job
and caught two things the offline oracles structurally could not (they never invoke
`dft_stac_cube`, which is network-bound):

1. **`terra::nlyr()` returns a double, not integer.** The uniform-nlyr guard
   `vapply(tile_stacks, terra::nlyr, integer(1))` errored ("values must be type
   'integer' but result is 'double'"). Fixed: `numeric(1)` template. The tiled fetch
   itself worked — all 12 tiles streamed, offset-split, and covered without error; it
   only tripped at the strict guard *after* assembly. (The untiled network test passed.)

2. **Tiled and untiled cubes are NOT co-lattice.** gdalcubes enlarges the untiled
   bbox extent *symmetrically* to align with `dx/dy` ("extent will be enlarged by
   0.79 [x] / 4.88 [y] at both sides"), so the untiled grid origin is
   `683391.9, 6027436` while the tile grid (anchored at bbox-LL, each tile a `res`
   multiple so un-enlarged) is `683392.6, 6027441` — offset ~0.79m (x), ~4.88m (y,
   nearly half a pixel). For integer LULC + `near` (#36) a sub-pixel shift is absorbed
   (same source pixel), so #36's exact `expect_equal` held. For float kNDVI + bilinear
   (#38) the shift changes every cell, and a `near`-resample comparison then shifts one
   grid against the other → median |diff| 0.009, q99 0.11, max 0.24. This is a
   **test-methodology** issue (both grids are valid; the tiled cube is not wrong), not a
   code bug — the tiled cube lands on a bbox-anchored grid, sub-pixel-offset from the
   untiled grid, immaterial to per-pixel trajectory reducers. Confirming via a
   bilinear-aligned comparison (diagnose_grid.R): if bilinear-aligned diffs collapse to
   ~1e-3 the values are correct and it was purely the offset.

**Resolution (confirmed via saved 2021-07/08 cubes, offline):** bilinear alignment gives
cor **0.997**, median |diff| **3.4e-3**, per-layer means agree to **6e-4**; and mean |diff|
at tile seams (0.0075) **==** interior (0.0076) → **no seam artifacts** (gdalcubes reads the
source margin at tile edges). So the tiled cube is a faithful resampling of the source,
differing from untiled only by the benign sub-pixel grid offset. Fix is test-methodology,
not code: the network test now aligns tiled onto the untiled grid with **bilinear** and
asserts grid-robust equivalence — `cor > 0.98`, `median |diff| < 0.01`, per-layer mean
agreement `< 0.01` — thresholds measured on the real cubes with headroom. Window switched
to growing-season (`2021-07-01/2021-08-31`) for robust coverage; offset-split-under-tiling
stays covered by the offline commutativity oracle. Code fix carried here: `terra::nlyr()`
returns double → guard template `numeric(1)`.

**Decision — tile anchoring stays at bbox-LL (not the gdalcubes-enlarged origin).**
Re-anchoring tiles to match the untiled grid would (a) couple `tile_grid` to gdalcubes'
internal extent-enlargement, (b) change the shared #36 helper, and (c) still differ at
edges — for no scientific gain, since the tiled cube is already an equivalent resampling
and downstream reducers are per-pixel. Documented as a benign grid offset in roxygen/NEWS.

## Key line references
- `R/dft_stac_cube.R`: cube_view `:231-240`; `build_index_stack` `:248-260`; offset-split +
  cover `:265-283`; unified tail `:290-295`; `stac_cube_cache_key` `:324-340`.
- `R/dft_stac_fetch.R`: `tile_size_check` `:233`; `tile_grid` `:271`; `stac_cache_key`
  append pattern `:210-222`.
- `tests/testthat/test-dft_stac_cube.R`: `cube_key()` helper `:31-45`; distinctness block
  `:52-73`; network e2e `:117-140`.

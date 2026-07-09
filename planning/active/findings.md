# Findings — Tile dft_stac_fetch (#36)

## Issue context

`dft_stac_fetch()` builds a single gdalcubes cube over the AOI's **bounding box**
and masks to the polygon afterward. For a thin, spread-out AOI — a floodplain
following a river corridor — the bounding box is largely empty, so the download
scales with the bbox, not the AOI. Large-floodplain fetches are download-bound
(~30 min per group at 10 m × 3 yr).

Measured on an io-lulc 10 m floodplain fetch (NECR): the grid is 57.0 M cells,
of which 5.73 M (10.1%) fall inside the floodplain — a **~10× download overhead**.
Thinner / more diagonal reaches are worse.

**Distinct from #32:** #32 restores polygon-tight *compute* in `dft_stac_cube()`
via `gdalcubes::filter_geom()`, which is blocked upstream (segfault in
`gc_exec_worker`). This issue is the `filter_geom`-independent path: cut the
**download** by tiling, on the categorical `dft_stac_fetch()` (io-lulc) path.

**Proposed:** tile the AOI into a grid, fetch only tiles intersecting the AOI
(skip empty tiles), and mosaic. Peak download approaches the union of intersecting
tile bboxes — near the AOI footprint for a corridor, rather than the full bbox.
Tile size trades request count against per-request waste.

Related: #32 (`filter_geom`, blocked), #34 (transition memory fixed; fetch now
the dominant cost), #38 (same residual on the cube path).

## Design notes (from Plan-agent review, 2026-07-09)

- **Mosaic == untiled over the AOI, not raster-identical.** `st_make_grid`
  over-hangs `xmax/ymax` by up to `tile_size − remainder`, and `terra::mask()`
  does not crop — so the tiled masked raster keeps a larger extent with a wider
  NA margin. Downstream (`dft_rast_classify` on `layer=1`, `dft_rast_summarize`
  reduce-by-value) ignores the NA margin. Test oracle must crop both to their
  common AOI intersection before comparing values — NOT `all.equal` on raw
  dimensions. Inter-tile alignment is exact as long as `tile_size` is snapped to
  a multiple of `res` and the grid is anchored at `(xmin, ymin)`; gdalcubes
  streams whatever source COG pixels each output window needs (incl. just outside
  the tile edge), so even bilinear edges match — no seams.
- **BLOCKER → write the tiled mosaic as `.tif`, not `.nc`.** terra's NetCDF
  *write* is fragile on the pinned stack (gotchas note: terra↔NetCDF round-trip,
  layer naming, NoData differ). The sibling `dft_stac_cube` writes
  `terra::writeRaster(stk, ...)` to `.tif` — proven precedent. Derive the cache
  extension from `is.null(tile_size)` so lookup + writer agree. Downstream is
  layer-name-agnostic (`dft_rast_classify` uses `layer=1`; `stac_items` attr set
  on the list), so `.nc`-vs-`.tif` read differences don't matter.
- **Leave boundary tiles un-trimmed.** Clipping the max-edge tiles to the bbox
  would make their span not a multiple of `res`, breaking congruence/alignment.
  The `< tile_size` overhang is masked away — bounded waste, worth it.
- **Cache-key conditional-append is safe** iff one normalized `is.null(tile_size)`
  predicate drives both the path gate and the key-append (satisfies the #32
  normalize-once convention). Snap `tile_size` BEFORE hashing so `504`/`500`
  (res 10) → same key. Add a golden regression freezing `cache_key(NULL)` to the
  current hash — that test is the guardian of legacy-cache preservation.
- **Guards:** validate `tile_size` is NULL or one positive finite numeric (abort
  on `NA`/`0`/negative/`Inf`/non-scalar/non-numeric); after snapping require
  `>= res` (guards `tile_size < res/2` → 0 → degenerate grid). Empty intersecting
  set aborts. Single-tile (`tile_size ≥ bbox`) proceeds through the tiled path
  (one tile) — do NOT reroute to untiled (would desync key/format).
- **GDAL `/vsicurl` config on the tiled path.** `dft_stac_fetch` doesn't set the
  `GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR` / `VSI_CACHE` / HTTP-multiplex config
  that `dft_stac_cube` sets. Tiling multiplies per-item COG opens, so set it (with
  `on.exit` restore) or small tiles trade data volume for open latency.
- **tile_size units** = CRS units (metres for the default UTM CRS), same as `res`.
- **tempfile hygiene:** unique `tempfile()` per (year × tile); `unlink()` after
  each year's merge. terra rasters are disk-backed + merge streams → bounded RAM.

## Key code locations

- `R/dft_stac_fetch.R:122-151` — per-year fetch loop (cube_view over bbox_target,
  raster_cube, write_ncdf to `<yr>_<key>.nc`, read back, mask). The download is
  `write_ncdf`.
- `R/dft_stac_fetch.R:169-179` — `stac_cache_key()` (9 hashed params).
- `R/dft_stac_cube.R:231-294` — sibling: cube_view, `terra::cover` assembly,
  `terra::writeRaster → .tif` cache, GDAL config, `st_union` query. Reference.
- `tests/testthat/test-dft_stac_fetch.R:43-72` — `cache_key()` helper + "changes
  with each fetch-affecting parameter" block to extend.
- `tests/testthat/test-dft_stac_cube.R:115-140` — `DRIFT_TEST_NETWORK` gate to
  mirror for the opt-in e2e.

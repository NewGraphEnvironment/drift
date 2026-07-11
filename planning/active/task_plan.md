# Task: Bound `dft_stac_cube()` streaming to the AOI (#38)

`dft_stac_cube()` builds its gdalcubes cube over the AOI **bounding box**
(`cube_view(extent = bbox_target)`), so the COG streaming — the dominant cost,
~10-30 min for a multi-year monthly Sentinel-2 fetch — scales with the bbox, not the
AOI polygon. For a thin corridor floodplain the bbox is ~90% empty (area/bbox ≈ 0.105
on the packaged example AOI → ~10× streaming overhead). #32 restored polygon-tight
**output** via `terra::mask()` but that runs *after* streaming — it does not reduce the
read. #38 reduces the **read** by tiling the `cube_view` (mirroring #36 for the
categorical sibling `dft_stac_fetch()`): stream only tiles intersecting the AOI polygon,
then mosaic. Opt-in `tile_size = NULL` default = today's behavior, byte-for-byte.

Reuses #36's `tile_size_check()` / `tile_grid()` (`R/dft_stac_fetch.R`) in place. The
cube path is harder (per-tile SCL mask + index + 2022 offset-split + `terra::cover`;
multi-layer stacks) but simpler in caching (always `.tif`; GDAL config already
unconditional — no `.nc`/`.tif` routing).

## Phase 1: cube cache key — golden guardian first, then conditional `tile_size` (offline, tests-first)
- [ ] compute the current untiled `stac_cube_cache_key()` for `cube_key()`'s fixed inputs; freeze as `expect_equal(cube_key(), "<frozen 12-char>")` — authored **before** touching the function
- [ ] extend the `cube_key()` helper with `tile_size = NULL` (pass through to `stac_cube_cache_key`)
- [ ] distinctness: `cube_key(tile_size = 500) != cube_key()`; distinct sizes → distinct keys; snap-before-key (`504` and `500` at res 10 → same key)
- [ ] refactor `stac_cube_cache_key` to the append-only shape; append `tile_size` only when non-NULL; **confirm the frozen literal is unchanged** (byte-preserving)
- [ ] call site passes `tile_size = tile_size`; normalize `tile_size` once via `tile_size_check` at the top of `dft_stac_cube`

## Phase 2: `mosaic_stacks` + multi-layer merge / commutativity / extent oracles (offline, tests-first)
- [ ] multi-layer merge oracle: reference multi-layer SpatRaster → split into res-aligned non-overlapping tiles → `mosaic_stacks` → `all.equal` per layer; nlyr + layer order preserved
- [ ] **commutativity:** synthetic multi-layer `pre`/`post` stacks with a known NA pattern → `mosaic_stacks(lapply(tiles, \(t) terra::cover(terra::crop(pre,t), terra::crop(post,t))))` equals `terra::cover(pre, post)` cell-for-cell (cover-then-merge == merge-then-cover, in CI)
- [ ] **extent semantics:** `mosaic_stacks` over `tile_grid`-derived synthetic tiles for the example AOI yields the tile-union extent (⊇ polygon, generally ⊊ full bbox) — documents the `clip = FALSE` + `tile_size` narrowing
- [ ] implement `mosaic_stacks()` `@noRd`; tests green

## Phase 3: tile the cube read — refactor + wire `tile_size` end-to-end
- [ ] `build_index_stack` gains `v`; add local closure `assemble_index_stack(extent)` (moves cube_view + offset-split + cover inside); untiled routes through it over `bbox_ext` — identical output
- [ ] tiled branch: `tile_grid` → per-tile `assemble_index_stack` → uniform-nlyr `stopifnot` → `mosaic_stacks`; unified clip/time/names/`.tif` tail; reuse #36 helpers in place (comment)
- [ ] roxygen `@param tile_size` + amended clip/read caveat (`clip=FALSE`+`tile_size` = tile-union extent) + cache-doc `tile_size` note
- [ ] `devtools::document()`; `lintr::lint_package()` clean; `devtools::test()` green (offline)

## Phase 4: opt-in network e2e (`DRIFT_TEST_NETWORK`)
- [ ] window **straddling 2022-01-25** (e.g. `2021-10-01/2022-04-30`, `dt = "P1M"`) so the offset-split-under-tiling path runs on the tiled side
- [ ] fetch untiled + tiled (small `tile_size`); assert both `SpatRaster`, equal nlyr, time set, tiled cached as one `cube_<key>.tif`, kept-tile count ≪ full grid
- [ ] tiled ≈ untiled over common AOI cells **per layer** via `terra::resample(tiled, untiled, method = "near")` then abs-diff with an **explicit tolerance / robust quantile** (float kNDVI — no integer `expect_equal`; no `compareGeom` on extents)

## Phase 5: docs + gotchas + NEWS + version
- [ ] `inst/notes/gdalcubes-pc-gotchas.md`: flip the #38 residual to resolved-via-cube-tiling; update the #36 bullet's "#38 for the cube-path twin" cross-ref
- [ ] `NEWS.md` `# drift 0.7.0` — `dft_stac_cube()` gains `tile_size` (opt-in, default `NULL` = unchanged; bounds the read for sparse AOIs; always caches `.tif`); Closes #38
- [ ] `DESCRIPTION` `0.6.0 → 0.7.0` + `Date` (final commit)

## Phase 6: validate, archive, PR, release
- [ ] `devtools::test()` / `lint` / `document` / `check` clean (network tests skip)
- [ ] `/planning-archive`; `/gh-pr-push` (`Fixes #38`, `Relates to NewGraphEnvironment/sred-2025-2026#16`)
- [ ] `/gh-pr-merge` → release v0.7.0

## Validation
- [ ] Tests pass (`devtools::test()`); network tests skip cleanly
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

# Task: Tile dft_stac_fetch to bound download over sparse-floodplain bounding boxes (#36)

`dft_stac_fetch()` builds one gdalcubes cube over the AOI's **bounding box** and
masks to the polygon only after the pixels are streamed. For a thin, diagonal
floodplain corridor the bbox is largely empty, so the download scales with the
bbox, not the AOI (~10× overhead measured on a real io-lulc floodplain: 10.1% of
bbox cells inside the polygon). `gdalcubes::filter_geom()` (the polygon clip that
would fix this) segfaults on the pinned build, so it stays blocked. Fix: add an
opt-in `tile_size` that tiles the AOI bbox into a res-aligned grid, fetches only
tiles intersecting the AOI polygon, and mosaics. Default `NULL` = today's
single-cube behavior, existing caches preserved. Sibling cube-path residual is
tracked separately as #38 (out of scope).

## Phase 1: `tile_grid()` + `tile_size` normalization (offline, tests first)
- [x] validation aborts: `NA`, `0`, negative, `Inf`, `c(1,2)`, `"500"`, snapped `< res`
- [x] snapping: non-multiple snaps to nearest multiple of `res`, messages, snapped value used
- [x] intersecting subset: a diagonal/L-shaped AOI in a known bbox keeps exactly the expected tiles, drops empty ones, kept-count ≪ full grid (the efficiency mechanism, offline)
- [x] res-alignment: every extent's `left-xmin`, width, height are exact multiples of `res`; first tile lower-left `== (xmin, ymin)`; single-tile when `tile_size ≥ bbox`; empty/degenerate AOI aborts
- [x] implement `tile_grid()` + normalization; new tests green

## Phase 2: cache key — conditional `tile_size` append (offline)
- [x] golden regression: `cache_key(tile_size = NULL)` == frozen `79f67b7b9dae` for fixed inputs (guards legacy-cache preservation)
- [x] `cache_key(tile_size = 500) != cache_key(tile_size = NULL)`; distinct sizes → distinct keys; snap-before-key: `504` and `500` (res 10) → same key
- [x] `stac_cache_key()` gains `tile_size = NULL`; appends only when non-NULL (real call-site wiring lands in Phase 4 with the fetch param); tests green

## Phase 3: extract `fetch_extent_to()`, refactor untiled path (behavior-preserving)
- [x] extract helper; untiled path routes through it, writing straight to `<yr>_<key>.nc` — identical filename/format
- [x] existing offline tests green (45/1 skip); faithful code-motion (cube_view built identically); the Phase 4 network e2e exercises the shared primitive end-to-end

## Phase 4: tiled branch — mosaic assembly + wire `tile_size` end-to-end
- [ ] offline merge oracle: reference SpatRaster split into res-lattice tiles → `terra::merge()` → `all.equal(values(merged), values(reference))`; masked mosaic == masked reference over AOI; `.tif` round-trip preserves single-layer integer codes
- [ ] add `tile_size` to `dft_stac_fetch`; tiled branch (per-tile fetch → merge → `.tif` → read → mask); extension from `is.null(tile_size)`; GDAL config + `on.exit`; tempfile `unlink`
- [ ] roxygen `@param tile_size` + `\dontrun` example + cache-doc `.tif` note
- [ ] opt-in network e2e (`DRIFT_TEST_NETWORK`): fetch example AOI untiled and with a small `tile_size`; assert tiled is a per-year list of single-layer SpatRasters with `stac_items` attr, and **tiled == untiled over cropped common AOI cells** (not raw dimensions)
- [ ] `devtools::document()`; `lintr::lint_package()` clean; `devtools::test()` green

## Phase 5: docs + gotchas note + NEWS + version
- [ ] `inst/notes/gdalcubes-pc-gotchas.md`: tiling entry (fetch download bounded by tiling the cube_view; tiled mosaic cached as `.tif` via terra; #36)
- [ ] `NEWS.md` `# drift 0.6.0` — `tile_size` (opt-in, default `NULL` = unchanged; bounds download for sparse AOIs; tiled fetches cache as `.tif`); Closes #36
- [ ] `DESCRIPTION` `0.5.0 → 0.6.0` + `Date` (final commit)

## Phase 6: validate, archive, PR, release
- [ ] `devtools::test()` / `lint` / `document` / `check` clean (network tests skip)
- [ ] `/planning-archive`; `/gh-pr-push` (`Fixes #36`, `Relates to NewGraphEnvironment/sred-2025-2026#16`)
- [ ] `/gh-pr-merge` → release v0.6.0

## Validation
- [ ] Tests pass (`devtools::test()`); network tests skip cleanly
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

# Task: dft_stac_cube — restore AOI-polygon clip (filter_geom segfault workaround) (#32)

`dft_stac_cube()` originally clipped its STAC index cube to the AOI polygon with
`gdalcubes::filter_geom()`, which segfaults / returns an all-NA cube on the pinned
gdalcubes 0.7.3 build, so #30 removed it — the cube now spans the AOI **bounding
box**. Restore polygon-tight computation *without* `filter_geom` by masking the
assembled terra stack client-side (`terra::mask()`, the proven `dft_stac_fetch.R:150`
pattern) behind a new `clip = TRUE` default. Out-of-polygon cells become NA on every
layer, so `dft_rast_break()`/`dft_rast_trend()` skip them via their existing
`rowSums(!is.na) >= min_obs` gate.

Honest scope: the dominant cost (streaming the full bbox of COGs via
`cube_view(extent = bbox_target)`) is unchanged — a post-hoc mask can't push the AOI
into the read. Real wins: polygon-tight output by default + a modest reducer speedup.
Fetch-time streaming stays bbox-bound (documented residual).

## Phase 1: Test contract (failing first)
- [ ] `cube_key()` helper gains `clip`; `cube_key(clip = FALSE) != base` assertion added
- [ ] `stac_cube_clip()` offline masking unit test (synthetic raster + polygon)
- [ ] opt-in network e2e asserts a bbox-corner cell is all-`NA` under default clip
- [ ] confirm the new tests FAIL against current code

## Phase 2: Implement clip
- [ ] `clip = TRUE` param + `stac_cube_clip()` helper + apply after stk assembly
- [ ] `clip` threaded into `stac_cube_cache_key()` (hash) AND the call site
- [ ] roxygen `@param clip` + `@return` rewrite + `filter_geom` comment updates
- [ ] `devtools::document()`; `lintr::lint_package()` clean; `devtools::test()` green

## Phase 3: Docs + gotchas note + NEWS + version
- [ ] update `inst/notes/gdalcubes-pc-gotchas.md` filter_geom bullet (#32 resolved + residual)
- [ ] `NEWS.md` 0.5.0 entry (behavior change + cache rebuild + Closes #32)
- [ ] `DESCRIPTION` 0.4.0 → 0.5.0 + Date (final commit)

## Phase 4: Validate, archive, PR, release
- [ ] `devtools::test()` / `lint` / `document` / `check` clean (network tests skip)
- [ ] `/planning-archive`; `/gh-pr-push` (`Fixes #32`, `Relates to NewGraphEnvironment/sred-2025-2026#16`)
- [ ] `/gh-pr-merge` → release v0.5.0

## Validation
- [ ] Tests pass (`devtools::test()`); network/bfast tests skip cleanly
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

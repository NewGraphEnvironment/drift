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
- [x] `cube_key()` helper gains `clip`; `cube_key(clip = FALSE) != base` assertion added
- [x] `stac_cube_clip()` offline masking unit test (synthetic raster + polygon)
- [x] opt-in network e2e asserts a bbox-corner cell is all-`NA` under default clip
- [x] confirm the new tests FAIL against current code (FAIL 6 | SKIP 2 | PASS 1)

## Phase 2: Implement clip
- [x] `clip = TRUE` param + `stac_cube_clip()` helper + apply after stk assembly
- [x] `clip` threaded into `stac_cube_cache_key()` (hash) AND the call site
- [x] roxygen `@param clip` + `@return` rewrite + `filter_geom` comment updates
- [x] `devtools::document()`; `lintr::lint_package()` clean; `devtools::test()` green (319 pass)
- [x] `/code-check`: normalize `clip <- isTRUE(as.logical(clip))` once so the mask gate
      and cache key can't disagree for truthy-but-non-TRUE inputs (silent wrong-extent fix)

## Phase 3: Docs + gotchas note + NEWS
- [x] update `inst/notes/gdalcubes-pc-gotchas.md` filter_geom bullet (#32 resolved + residual)
- [x] `NEWS.md` 0.5.0 entry (behavior change + cache rebuild + Closes #32)

## Phase 4: Validate, bump, archive, PR, release
- [x] `devtools::test()` / `lint` / `document` / `check` clean (check: 0E/0W/0N; suite 319 pass)
- [x] `DESCRIPTION` 0.4.0 → 0.5.0 + Date, committed as `Release v0.5.0` (final code commit)
- [ ] `/planning-archive`; `/gh-pr-push` (`Fixes #32`, `Relates to NewGraphEnvironment/sred-2025-2026#16`)
- [ ] `/gh-pr-merge` → tag v0.5.0

## Validation
- [ ] Tests pass (`devtools::test()`); network/bfast tests skip cleanly
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

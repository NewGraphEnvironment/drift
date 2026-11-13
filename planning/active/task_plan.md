# Task: MODIS vegetation indices (MOD13Q1) as a cube source from Planetary Computer (#115)

`dft_stac_cube()` has one source, `sentinel-2-l2a`, available from 2017. A site-level covariate for a survey run before 2017 (here, camera stations surveyed every year from 2008 to 2017) has no index from drift for most of its years. MODIS Terra/Aqua vegetation indices (MOD13Q1 v6.1) cover 2000 to the present, and Planetary Computer holds them as the STAC collection `modis-13Q1-061`, as Cloud Optimized GeoTIFFs. #82 (HLS) is the 30 m route from 2013 and needs Earthdata Login; this one needs no account.

## Decided at the gate

- **Index route (owner, 2026-11-13, at the plan gate):** compute `ndvi`/`kndvi` from the red and NIR roles, as for Sentinel-2. **Add `evi` to the registry** over `nir`/`red`/`blue` (`2.5 * (nir - red) / (nir + 6 * red - 7.5 * blue + 1)`), so both sources get EVI. The published NDVI/EVI assets are not read.
- **Cloud filter (mechanism, by me):** `cloud_cover_max` keeps its signature and its defaults (60 in the cube, 20 in the composite). For a source with no `eo:cloud_cover`, `missing(cloud_cover_max)` means the filter is skipped. A value passed explicitly is refused, naming the source. The Sentinel-2 cache keys do not move.
- **Resolution (mechanism, by me):** same `missing()` pattern. A source can carry a native `res` (MODIS 250), used when `res` is not passed. This avoids a default 10 m cube of 250 m data (625x the cells). Sentinel-2 still defaults to 10, so its keys do not move.
- **Window-only items (mechanism, by me):** normalise once, in `stac_cube_items()`. An item with a null `datetime` and both `start_`/`end_datetime` is given `datetime` = the window midpoint, in UTC ISO 8601. That is the rule gdalcubes itself applies (`duration = "center"`). One value then feeds the `months` filter, the offset split and gdalcubes, and the gdalcubes branch that needs `lubridate` (not declared in drift) is never reached.

## What exploration found (2026-11-13; live probe over the packaged AOI, 2017-06/09)

- **`cloud_cover_max` on MODIS returns 0 items, which then aborts as `drift_no_items` ("No STAC items found").** It is neither silent nor accurate: a filter on a missing property drops everything.
- **The `months` filter drops every MODIS item.** `stac_cube_items()` reads `f$properties$datetime` (`R/dft_stac_cube.R:514`), which is NULL, so every month is NA. The same read feeds the offset split (`:542`); MODIS has no `offset_boundary`.
- The search matches by window overlap: 18 items for Jun–Sep, including one starting 05-17 and one starting 09-30. Their midpoints fall outside the cube's t0/t1, so the cube view excludes them. Terra (MOD) and Aqua (MYD) are interleaved 8 days apart, about 4 composites per month.
- `gdalcubes::stac_image_collection()` (0.7.5) accepts `proj:wkt2` when there is no `proj:epsg`. It falls back to `start_datetime` only through `lubridate`, and when that fails it **skips the item with a warning**.
- **The fill differs from the STAC metadata:** `pixel_reliability` is `Byte` on disk with NoData **255** (STAC says `int8`; the issue assumed -1). Red and NIR are `Int16`, NoData -1000, 512x512 blocks, 4800x4800 tiles.
- An index whose role MODIS lacks (`ndmi`/`mndwi` → `swir16`, and `ndwi` → `green`) is caught by `index_resolve_expr()` only **after** the STAC query (`band_assets` silently drops the NULL role). `dft_stac_composite()` already refuses an unknown band role (`composite_band_assets()`).
- Reuse: `stac_cube_items()` is shared by the cube and the composite, so the datetime normalisation and the cloud refusal cover both.

## Phase 1: Tests first (red)

- [x] `test-dft_stac_config.R`: `modis-13Q1-061` is a cube source; roles red/nir/blue/mask map to `250m_16_days_red_reflectance` / `_NIR_` / `_blue_` / `_pixel_reliability`; no `swir16`/`green`; scale 1e-4, offset 0; `available_datetime` starts `2000-02-18`; `res` 250; and it is marked as having no cloud-cover property.
- [x] Fixture item test (no network): a MODIS-shaped feature list (null `datetime`, start/end window, no `eo:cloud_cover`, `proj:wkt2` only) goes through `stac_cube_items()`, with `rstac` mocked to stop by default (`code-check-r.md`, "A fetcher's test helper must make the network fail"). Asserts: the midpoint is set, `months` keeps the right items, `is_pre` is all FALSE, and an S2-shaped item is unchanged.
- [x] Refusals before any network call: explicit `cloud_cover_max` on MODIS (cube and composite); `index = "ndmi"` on MODIS; the S2 path still accepts both.
- [x] Cache-key invariance: the S2 key for a fixed call is identical before and after the change. Pinned at the caller instead of a golden value: a mocked key builder captures the `res` and `cloud_cover_max` that `dft_stac_cube()` and `dft_stac_composite()` hand it (10/60 and 10/20 for S2, 250/NULL for MODIS); the frozen-key guardian already pins the builder.
- [x] `test-dft_index_expr.R`: `evi` is in the registry over nir/red/blue; its resolved expression on S2 roles; and the hand-computed value on known reflectance, including the scale fold (EVI's `+ 1` makes it scale-sensitive).

## Phase 2: Source config and index registry

- [x] `dft_stac_config()`: add `"modis-13Q1-061"` to the choices and its list (roles, `mask_values = c(2L, 3L, 255L)`, scale 1e-4, offset 0, `res = 250`, `cloud_cover = FALSE`, `available_datetime = "2000-02-18/2025-12-31"`, a cost comment), plus roxygen.
- [x] `inst/indices/indices.csv`: add `evi`.

## Phase 3: Read path

- [x] `stac_cube_items()`: normalise window-only items to a midpoint `datetime` (one helper, used before the months filter and the offset split). Skip `ext_filter(eo:cloud_cover)` when the source has none.
- [x] A shared helper resolving `cloud_cover_max` per source, called from `dft_stac_cube()` and `dft_stac_composite()` with `missing()`. It refuses an explicit value on a source without the property.
- [x] `dft_stac_cube()`: `res` from `cfg$res` when missing. Refuse an index whose roles the source lacks, before the query (`index_roles()` against `cfg$roles`).
- [x] roxygen for `source`, `res` and `cloud_cover_max` in both functions; `devtools::document()`.

## Review fold-in (Plan review, 2026-11-13; `review-plan.md`)

- [x] B1/O2: one helper renames bands whose asset is not an identifier to their role name (`gdalcubes::rename_bands()`) before `apply_pixel`/`reduce_time`, used by `dft_index_expr()` and the composite's pixel functions (reflectance and count); S2 untouched. Offline fixture test with MODIS-named bands.
- [x] G3/G4: the offline fixture also carries -1000 reflectance NoData and reliability 255/3 pixels, and asserts NA there and the hand value elsewhere.
- [x] G6: drop window-only items whose midpoint falls outside the query window, in `stac_cube_items()`; tested.
- [x] A2: the cloud refusal names `NULL` as accepted; A3: midpoint test under an off-UTC timezone.
- [x] G2/G5: docs — composite bands for MODIS and what `count` counts on it; the cube/composite/items/package/index docs and the trajectory vignette stop calling Sentinel-2 the only cube source.
- [x] A4: config comment says 250 m is the product's nominal size (grid 231.656 m); A6: collection is open-ended (STAC extent `2000-02-18/null`, read 2026-11-13), so the end date is the default window, said so.
- [ ] A5 (pre-existing: monthly layer labels whatever `dt`) filed as its own issue.

## Phase 4: Live verification

- [x] An opt-in network test (`DRIFT_TEST_NETWORK=true`): the packaged AOI, MODIS, `kndvi` and `evi`, 2017-06-01/2017-09-30, `months = 6:9`. It asserts data inside the polygon on every layer, NA outside, kndvi in [0, 1), ndvi in [-1, 1], and a MODIS composite's red/nir/blue reflectance in [0, 1] (a -1000 fill is -0.1; kndvi/evi ranges cannot catch it, review G3). A pre-2017 window (2010) returns data.
- [x] Fill check: confirm that gdalcubes honours red/NIR NoData -1000 and the reliability NoData 255 (no fill value reaches the index), and record the result in `inst/notes/gdalcubes-pc-gotchas.md`.
- [x] BULK scale run: the `co_ff04` floodplain, MODIS kndvi for one decade (2008-2017, `months = 6:9`), with `/usr/bin/time -l` peak RSS and wall time recorded in the PR body (CLAUDE.md, "Scale-test raster functions").

## Phase 5: Docs and release prep

- [x] CLAUDE.md Core Pipeline gains a MODIS line (above the marker); the moved BULK item noted there. NEWS is written by `/gh-pr-merge` at the release (repo practice, `69371d8`); the draft entry goes in the PR body.
- [x] `lintr::lint_package()`, the full `devtools::test()`, `pkgdown::check_pkgdown()`.
- [x] Version bump: done by `/gh-pr-merge` in its release commit, as for v0.24.3 (`69371d8`), not on the branch.

## Owed at the end (reported, done after merge)

- [ ] Note on #82 (HLS) that MODIS covers the pre-2017 gap at 250 m with no account. HLS remains the 30 m route.

## Validation

- [x] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the fixture test fails on main for the months drop (red first); the refusal tests fail on main; the S2 golden cache key is unchanged; the live test proves data, clip, value range and pre-2017 reach; the BULK run gives the memory and time figures.


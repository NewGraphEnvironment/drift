# Findings — dft_stac_cube AOI-polygon clip (#32)

## Issue context

Restore AOI-polygon clipping in `dft_stac_cube()`. It was intended to clip the cube
to the AOI polygon with `gdalcubes::filter_geom()`; on gdalcubes 0.7.3 that yields an
entirely-NA cube and can segfault the compute worker, so #30 removed it. The cube now
spans the AOI **bounding box** and callers clip the reduced raster with
`terra::mask()`. Cost: `dft_rast_break()` reduces over the whole bbox rather than just
the floodplain polygon (a few× more pixels for a thin reach). #32 scoped to the AOI
clip only (the Sentinel-2 baseline-offset half shipped in #30).

## Exploration (2026-07-09)

- **Downstream consumers already skip NA pixels.** `dft_rast_break.R:101-102` and
  `dft_rast_trend.R:58-59` both do `vals <- terra::values(cube); usable <-
  which(rowSums(!is.na(vals)) >= min_obs)` and run the expensive per-pixel reducer
  only on `usable` rows. So masking the cube to the AOI (out-of-polygon → NA on every
  layer) makes those pixels drop out of the reducer for free — no change to break/trend.

- **Proven in-package clip pattern:** `dft_stac_fetch.R:150` —
  `terra::mask(r, terra::vect(aoi_target))` — applied client-side after reading. Mirror
  it at the cube-stack level in `dft_stac_cube()`.

- **`filter_geom` gotcha documented:** `inst/notes/gdalcubes-pc-gotchas.md:8-12`
  records the segfault (`gc_exec_worker`, `address 0x120`) and tags the fix as #32,
  recommending bbox `cube_view` + `terra::mask()`.

- **Example AOI is non-rectangular:** single MULTIPOLYGON, 2049 pts, area/bbox ≈ 0.105
  → a clipped cube has all-NA bbox corners (valid opt-in network assertion).

## Plan-agent review (key corrections adopted)

1. **Compute win is largely illusory — reframe.** `cube_view(extent = bbox_target)`
   (`dft_stac_cube.R:218-227`) still streams the full bbox of COGs (the ~10-30 min
   cost per `gotchas:40-41`); `terra::values()` still loads the full bbox matrix (peak
   memory unchanged). Only the seconds-scale per-pixel reducer loop shrinks. Lead the
   rationale with **polygon-tight output + no caller-side mask needed**; describe the
   reducer speedup as a modest secondary effect. Fetch-time pixel savings that
   `filter_geom` would have given are **not** recoverable — documented residual.

2. **Blocker — thread `clip` into BOTH the mask step and the cache key.** The key fn
   has a default, so forgetting `clip` at the call site (`:168-172`) makes `clip=TRUE`
   and `clip=FALSE` hash identically → silent wrong-extent cache hit (no error). Add
   `expect_false(cube_key(clip = FALSE) == cube_key(clip = TRUE))`.

3. **Simplify the helper** to bare `terra::vect(aoi_target)`, matching fetch — drop the
   `sf::st_as_sf()` coercion unless fetch's path proves `sfc` needs it. `terra::mask`
   with a multi-feature SpatVector masks to the union (matches the STAC `st_union`
   query at `:195`).

4. **Ordering is safe:** mask the `terra::cover(...)` result (offset-split branch) or
   the single-build result before `time`/`names`/`writeRaster`. `mask` preserves
   `nlyr`; `time` is re-derived on every read via `month_times(terra::nlyr(r))`
   (`:183`), so the cache-read path needs no change.

5. **Behavior change + cache churn:** direct cube users now get NA outside the AOI by
   default; hashing `clip` invalidates every existing 0.4.0 bbox cache (one-time
   rebuild). Both flagged in NEWS. Considered a `_clip.tif` filename suffix to spare
   `clip=FALSE` users the re-fetch — rejected as needless branching for a pre-1.0
   package with ~one cube-cache user.

6. **Vignette shielded:** `vignettes/trajectory-break-detection.Rmd` loads a committed
   `.rds` (pipeline chunk `eval = FALSE`), so the default change doesn't alter the
   rendered vignette. `data-raw/vignette_data_break.R`'s `terra::mask` becomes an
   idempotent no-op under `clip = TRUE` — leave it (defensive).

## Outcome

Restored `dft_stac_cube()`'s AOI-polygon clip (#32), removed in #30 when
`gdalcubes::filter_geom()` proved to segfault / return an all-NA cube on the
pinned gdalcubes 0.7.3 build. The clip is now done client-side: a new
`clip = TRUE` default masks the assembled terra index stack to the AOI polygon
with `terra::mask()` (helper `stac_cube_clip()`, mirroring `dft_stac_fetch()`).
Out-of-polygon cells become `NA` on every layer, so `dft_rast_break()` /
`dft_rast_trend()` skip them via their existing `rowSums(!is.na) >= min_obs` gate,
and the reduced raster is polygon-tight with no caller-side mask. `clip = FALSE`
keeps the full bbox.

Key learnings: the headline cost — streaming the full bbox of COGs via
`cube_view(extent = bbox)` — is **unchanged** (a post-hoc mask can't push the AOI
into the read), so the genuine wins are polygon-tight output + a modest reducer
speedup, not a fetch-time saving; that residual is documented in the gotchas note.
The load-bearing correctness detail was threading `clip` into **both** the mask
gate and the cache key, and normalizing `clip <- isTRUE(as.logical(clip))` once so
a truthy-but-non-`TRUE` input (e.g. `1`, `"TRUE"`) can't skip the mask yet key as
`TRUE` — which a `/code-check` fresh-eyes pass caught.

Released as **v0.5.0**. `devtools::check()` clean (0E/0W/0N); full suite 319 pass;
offline `stac_cube_clip()` masking test + `cube_key(clip=FALSE) != base` cover the
contract network-free.

Closed by: PR (Fixes #32) on branch `32-dft-stac-cube-restore-aoi-polygon-clip-f`.

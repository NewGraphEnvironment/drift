# Issue #25 — dft_stac_fetch cache key omits AOI

## Outcome

Fixed a silent wrong-data bug: `dft_stac_fetch()` cached NetCDFs as `<source>/<year>.nc`, so a
second AOI with the same source/year silently received the first AOI's raster masked to its own
extent (real occurrence: MORR got Neexdzii's rasters). Added internal `stac_cache_key()` —
`rlang::hash()` over the AOI geometry as WKB plus every fetch-affecting parameter (`res` coerced
to double, target CRS, `dt`, `aggregation`, `resampling`, post-resolution
`stac_url`/`collection`/`asset`) — giving filenames `<year>_<key>.nc`; also made `force = TRUE`
overwrite via `write_ncdf(..., overwrite = TRUE)` instead of erroring. Key learnings: hash sf
geometry as WKB, not the sfc object (PROJ-version CRS WKT drift causes spurious misses, and sf
attribute columns would leak into the key); coerce numerics before hashing (`10L` vs `10` hash
differently under `rlang::hash()`); hash post-default-resolution values, never possibly-NULL
args; and skip extent-containment checks on cache hits — gdalcubes only ever enlarges extents,
so the check validates nothing. Verified end-to-end against live Planetary Computer STAC (two
AOIs → two distinct cache files, correct extents, cache hit, force overwrite). Released as
v0.2.3.

Closed by: commits 9e2816a / 352aec9 / fc7c4e2 / b09c0fb, PR pending (branch
`25-dft-stac-fetch-cache-key-omits-aoi-secon`)

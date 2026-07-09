## Outcome

Added an opt-in `tile_size` to `dft_stac_fetch()` (#36) that bounds the STAC
download to the AOI footprint. By default `dft_stac_fetch()` streams one
gdalcubes cube over the whole AOI bounding box, so a thin, diagonal floodplain
corridor downloads ~10× more pixels than the polygon needs (measured 10.1% of
bbox cells inside a real io-lulc floodplain). When `tile_size` is set, the bbox
is split into a `res`-aligned grid, only tiles that intersect the AOI polygon
are streamed (via the shared `fetch_extent_to()` primitive), and the results are
mosaicked with `terra::merge(terra::sprc(...))` into a `.tif` cache. This is the
`filter_geom`-independent path — the polygon clip that would do this in the cube
pipeline segfaults on the pinned gdalcubes build (#32).

Delivered tests-first across five atomic phases: `tile_grid()` + `tile_size_check()`
(offline), a conditional cache-key append with a frozen golden-hash regression
(`tile_size = NULL` reproduces the exact legacy key so existing untiled caches
stay valid), extraction of the shared fetch primitive, the tiled branch with a
`.tif`/`.nc` extension split and a GDAL `/vsicurl` config scoped to the tiled
path, and the release docs.

**What was learned / decided:**
- terra's NetCDF *write* is fragile on the pinned stack, so the tiled mosaic is
  written as a GeoTIFF (mirroring `dft_stac_cube()`), not a `.nc`. Cache
  extension routes on `is.null(tile_size)`; the cache key already keys the two
  apart, so the two formats never collide.
- Tiles must be snapped to a multiple of `res` and anchored at the bbox
  lower-left so per-tile pixel grids are co-lattice — otherwise `terra::merge()`
  seams. Boundary tiles are left un-trimmed (the overhang is masked away).
- `tile_size` is normalized once up front so the path gate (`is.null`) and the
  cache-key append derive from the same snapped scalar (the #32 normalize-once
  convention — no gate/key desync).
- Two Plan/code-check agent reviews caught the `.tif`-not-`.nc` blocker and a
  sub-pixel-lattice fragility in the opt-in network test (hardened via
  near-resample onto the untiled grid).
- Fetch-time streaming on the continuous `dft_stac_cube()` path has the same
  residual, tracked separately as **#38** (unchanged by this work).

`devtools::check()` clean (0 errors / 0 warnings / 0 notes); 352 pass / 5 skip.
Released as **v0.6.0**.

Closed by: commits 127de94..135e84e on branch
`36-tile-dft-stac-fetch-to-bound-download-over-spars` / PR (Fixes #36) → v0.6.0.

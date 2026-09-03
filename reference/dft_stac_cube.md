# Fetch a masked spectral-index cube from a STAC catalog

Sibling of
[`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
for continuous change detection. Where
[`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
materializes one categorical raster per year, this builds a sub-annual
reflectance cube, masks clouds, computes a spectral index over band
roles, and returns the index time series as a `SpatRaster` (one layer
per time step) — the input to
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
for per-pixel trajectory breakpoint detection.

## Usage

``` r
dft_stac_cube(
  aoi,
  source = "sentinel-2-l2a",
  index = "kndvi",
  datetime = NULL,
  res = 10,
  crs = NULL,
  dt = "P1M",
  aggregation = "median",
  resampling = "bilinear",
  clip = TRUE,
  cloud_cover_max = 60,
  months = NULL,
  mask_values = NULL,
  tile_size = NULL,
  parallel = NULL,
  cache_dir = NULL,
  force = FALSE,
  sign_fn = rstac::sign_planetary_computer()
)
```

## Arguments

- aoi:

  An `sf` polygon defining the area of interest.

- source:

  Character. A cube source name for
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  (default `"sentinel-2-l2a"`). Must be a source with `cube = TRUE`.

- index:

  Character. Spectral index from
  [`dft_index_table()`](https://newgraphenvironment.github.io/drift/reference/dft_index_table.md)
  (default `"kndvi"`). Determines which band roles (and thus assets) are
  fetched.

- datetime:

  Character. ISO 8601 interval `"start/end"`. When `NULL`, uses
  `available_datetime` from
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md).

- res:

  Numeric. Output pixel size in CRS units (default 10).

- crs:

  Character. Target CRS as an EPSG string. When `NULL`, auto-detected
  from the AOI centroid's UTM zone.

- dt:

  Character. ISO 8601 duration for the temporal aggregation window
  (default `"P1M"`, monthly). The cadence
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)'s
  `frequency` must agree with.

- aggregation:

  Character. Temporal aggregation for multiple scenes in one `dt` window
  (default `"median"`).

- resampling:

  Character. Spatial resampling (default `"bilinear"`).

- clip:

  Logical. When `TRUE` (default), clip the returned stack to the AOI
  polygon with
  [`terra::mask()`](https://rspatial.github.io/terra/reference/mask.html),
  so
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
  /
  [`dft_rast_trend()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_trend.md)
  reduce only in-polygon pixels. The clip keeps every cell the polygon
  **touches** —
  [`terra::mask()`](https://rspatial.github.io/terra/reference/mask.html)
  defaults to `touches = TRUE` — so it is inclusive at the boundary by
  up to one cell, deliberately, so a thin corridor is not eroded. Cells
  the polygon does not touch become `NA` on every layer. That is a
  *different* rule from a cell-centre clip, and worth 15.5% of the
  analysed footprint on the packaged AOI (#47), so it matters to
  anything reporting boundary hectares. Set `FALSE` to keep the wider
  extent (e.g. for surrounding context, or to mask later with a
  different polygon). This clips the *output* — with the default
  `tile_size = NULL` the full bbox of COGs is still streamed either way,
  so `clip = FALSE` returns the full bounding box. When `tile_size` is
  set the read is tiled, so `clip = FALSE` returns the
  **AOI-intersecting tile union** (a stair-stepped superset of the
  polygon with `NA` where empty tiles were skipped), not a gap-free
  bounding box.

- cloud_cover_max:

  Numeric. Scene-level `eo:cloud_cover` maximum percent for the STAC
  pre-filter (default 60).

- months:

  Integer vector of calendar months (1-12) to keep, or `NULL` (default)
  for all. Restricting to the growing season (e.g. `6:9`) both sharpens
  the vegetation signal — snow and low-sun winter scenes carry no
  vegetation information — and cuts the number of scenes streamed.
  Months with no retained scenes become `NA` in the monthly cube, so the
  per-pixel series stays regular at `frequency = 12` for
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md).
  Prefer a longer `datetime` window when using this, so enough
  growing-season history remains to fit a stable BFAST baseline.

- mask_values:

  Integer vector of mask-band classes to exclude. When `NULL`, uses
  `mask_values` from
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  (e.g. Sentinel-2 SCL cloud / shadow / cirrus classes).

- tile_size:

  Numeric or `NULL` (default). Edge length, in CRS units (metres for the
  default UTM CRS), of the read-tiling grid (#38). When `NULL`, one cube
  is streamed over the whole AOI bounding box (the read scales with the
  bbox, not the AOI). When set, the bbox is split into a grid of
  `tile_size`-square tiles and only tiles that intersect the AOI polygon
  are streamed, then mosaicked — so a thin, diagonal AOI (e.g. a
  floodplain corridor) reads close to its footprint. Snapped to a
  multiple of `res`. Smaller tiles waste less bbox but cost more
  per-tile round trips; there is no auto-tuning. The cube always caches
  a `.tif` either way; a tiled read keys distinctly (see the caching
  note above), so untiled caches are untouched and `tile_size = NULL` is
  byte-for-byte the previous behavior. This is the continuous-path twin
  of
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)'s
  `tile_size`. Benchmarked against the alternatives on the packaged AOI
  (drift#47) it is the **slowest** option — 1263.6 s and 3213 range
  requests against an untiled 236.8 s / 462, because every tile rebuilds
  the image collection and reopens the COGs — so prefer `parallel` for
  speed and reach for `tile_size` only when peak memory, not wall clock,
  is the constraint. Because the cube resamples with bilinear, a tiled
  cube faithfully reproduces the untiled cube (the per-pixel reducers
  are unaffected) but lands on a bbox-anchored grid that is
  sub-pixel-offset from — not pixel-identical to — the untiled cube.

- parallel:

  Integer, or `NULL` (default) to auto-detect as `min(4, cores - 1)`,
  flooring to 1 where the core count is undetectable. Number of
  gdalcubes worker processes used for the read. The COG stream is the
  dominant cost and it parallelizes well: measured on the packaged AOI,
  a 4-month monthly kNDVI cube took 236.8 s at `parallel = 1`, 115.8 s
  at 4 and 96.0 s at 8 — and the output is **byte-identical** at every
  setting (correlation 1.000, max absolute difference 0), so this is a
  pure cost knob and does not enter the cache key. Capped at 4 by
  default rather than the full core count because each worker holds
  chunks in memory; raise it on a machine with headroom, or set `1` for
  the previous single-threaded behaviour. Prior to v0.9.0 drift never
  called
  [`gdalcubes::gdalcubes_options()`](https://rdrr.io/pkg/gdalcubes/man/gdalcubes_options.html)
  at all, so every fetch ran single-threaded (drift#47). gdalcubes also
  derives its default chunk size from this value, so raising it makes
  chunks finer as a side effect — measured in isolation on this AOI that
  is a *cost* (343.7 s / 693 requests at 128 px against 236.9 s / 462 at
  the default), so the speedup is attributable to concurrency. When
  `NULL` and a session-level
  [`gdalcubes::gdalcubes_options()`](https://rdrr.io/pkg/gdalcubes/man/gdalcubes_options.html)
  `parallel` above 1 is already set, that value is honoured rather than
  overridden.

- cache_dir:

  Character. Cache directory. When `NULL`, uses
  [`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md).

- force:

  Logical. Re-fetch even if cached, replacing the cached raster (default
  `FALSE`). The replacement is atomic, so an interrupted forced re-fetch
  leaves the previous entry intact rather than destroying it — which
  matters here, where rebuilding is a multi-hour stream.

- sign_fn:

  A signing function for STAC assets. Default is
  [`rstac::sign_planetary_computer()`](https://brazil-data-cube.github.io/rstac/reference/items_sign_planetary_computer.html).

## Value

A
[terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
index stack — one layer per time step, with a time value per layer —
cached as a GeoTIFF. By default (`clip = TRUE`) the stack is clipped to
the AOI polygon (cloud-masked; every cell the polygon touches is kept,
cells it does not touch are `NA` — see `clip`), so the reduced raster
from
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
is already polygon-tight; pass `clip = FALSE` for the full AOI
**bounding box** (or, with `tile_size` set, the AOI-intersecting tile
union). For sources with a reflectance-offset baseline boundary
(Sentinel-2), items are split at the boundary and offset-corrected per
side, so a series crossing it carries no artificial index step.

## Details

The index stack is materialized once to a GeoTIFF under
[`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md)
as `<source>/cube_<key>.tif`, keyed by a hash of the AOI geometry and
every cube-affecting parameter (including `clip` and `tile_size`, so a
tiled read keys apart from an untiled one). Because it is invariant to
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)'s
parameters, caching it here makes bfast parameter sweeps cheap — they
re-read the local raster instead of re-streaming COGs.

Three STAC-query specifics distinguish cube mode from
[`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md):
pagination via
[`rstac::items_fetch()`](https://brazil-data-cube.github.io/rstac/reference/items_functions.html)
is mandatory (a monthly multi-year query returns hundreds of items; a
single page silently truncates); the query uses `intersects` with the
AOI geometry, not a bounding box (floodplain polygons are highly
non-rectangular); and a scene-level `eo:cloud_cover` pre-filter shrinks
the collection before any pixel is read, complementing per-pixel mask
filtering.

## See also

[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
(the reducer that consumes this cube),
[`dft_index_expr()`](https://newgraphenvironment.github.io/drift/reference/dft_index_expr.md)
(the index applied),
[`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
(categorical sibling).

## Examples

``` r
if (FALSE) { # \dontrun{
# Monthly kNDVI cube for a floodplain reach (requires network + gdalcubes)
aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
cube <- dft_stac_cube(
  aoi,
  source   = "sentinel-2-l2a",
  index    = "kndvi",
  datetime = "2019-01-01/2023-12-31",
  dt       = "P1M"
)
breaks <- dft_rast_break(cube, start = c(2022, 1))
} # }
```

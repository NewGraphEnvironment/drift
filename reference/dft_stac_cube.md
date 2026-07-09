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
  [`terra::mask()`](https://rspatial.github.io/terra/reference/mask.html)
  (cells outside → `NA` on every layer), so
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
  /
  [`dft_rast_trend()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_trend.md)
  reduce only in-polygon pixels. Set `FALSE` to keep the full bounding
  box (e.g. for surrounding context, or to mask later with a different
  polygon). Note this clips the *output* only — the full bbox of COGs is
  still streamed either way (the AOI cannot be pushed into the read on
  the pinned gdalcubes build; see `inst/notes/gdalcubes-pc-gotchas.md`).

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

- cache_dir:

  Character. Cache directory. When `NULL`, uses
  [`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md).

- force:

  Logical. Re-fetch even if cached, overwriting the cached raster
  (default `FALSE`).

- sign_fn:

  A signing function for STAC assets. Default is
  [`rstac::sign_planetary_computer()`](https://brazil-data-cube.github.io/rstac/reference/items_sign_planetary_computer.html).

## Value

A
[terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
index stack — one layer per time step, with a time value per layer —
cached as a GeoTIFF. By default (`clip = TRUE`) the stack is clipped to
the AOI polygon (cloud-masked, cells outside the polygon `NA`), so the
reduced raster from
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
is already polygon-tight; pass `clip = FALSE` for the full AOI
**bounding box**. For sources with a reflectance-offset baseline
boundary (Sentinel-2), items are split at the boundary and
offset-corrected per side, so a series crossing it carries no artificial
index step.

## Details

The index stack is materialized once to a GeoTIFF under
[`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md)
as `<source>/cube_<key>.tif`, keyed by a hash of the AOI geometry and
every cube-affecting parameter. Because it is invariant to
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

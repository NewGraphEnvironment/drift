# Fetch STAC-hosted rasters via gdalcubes

Query a STAC catalog, build a gdalcubes image collection, and extract
per-year rasters cropped and masked to the AOI. Works with any STAC
collection hosting single-band classified rasters (IO LULC, ESA
WorldCover, custom COGs).

## Usage

``` r
dft_stac_fetch(
  aoi,
  source = "io-lulc",
  years = NULL,
  stac_url = NULL,
  collection = NULL,
  asset = NULL,
  res = 10,
  crs = NULL,
  dt = "P1Y",
  aggregation = "first",
  resampling = "near",
  cache_dir = NULL,
  force = FALSE,
  sign_fn = rstac::sign_planetary_computer()
)
```

## Arguments

- aoi:

  An `sf` polygon defining the area of interest.

- source:

  Character. A known source name passed to
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md).
  Ignored when `stac_url`, `collection`, and `asset` are all provided.

- years:

  Integer vector of years to fetch. When `NULL`, uses `available_years`
  from
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md).

- stac_url:

  Character. STAC API endpoint URL. Overrides `source`.

- collection:

  Character. STAC collection ID. Overrides `source`.

- asset:

  Character. Asset name within each STAC item. Overrides `source`.

- res:

  Numeric. Output pixel size in CRS units (default 10).

- crs:

  Character. Target CRS as an EPSG string (e.g. `"EPSG:32609"`). When
  `NULL`, auto-detected from the AOI centroid's UTM zone.

- dt:

  Character. ISO 8601 duration for the temporal aggregation window
  (default `"P1Y"`).

- aggregation:

  Character. Temporal aggregation method (default `"first"`). Use
  `"median"` for multi-scene composites.

- resampling:

  Character. Spatial resampling method (default `"near"` for categorical
  data).

- cache_dir:

  Character. Cache directory path. When `NULL`, uses
  [`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md).

- force:

  Logical. Re-fetch even if cached, overwriting the cached file (default
  `FALSE`). A raster returned by an earlier call with the same
  parameters is backed by that file and may silently pick up the
  rewritten contents.

- sign_fn:

  A signing function for STAC assets. Default is
  [`rstac::sign_planetary_computer()`](https://brazil-data-cube.github.io/rstac/reference/items_sign_planetary_computer.html).

## Value

A named list of
[terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
objects, one per year. The STAC items are attached as
`attr(, "stac_items")` for use with
[`dft_stac_classes()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_classes.md).

## Details

Fetched rasters are cached under
[`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md)
as `<source>/<year>_<key>.nc`, where `key` is a hash of the AOI geometry
and every fetch parameter that affects the output (`res`, `crs`, `dt`,
`aggregation`, `resampling`, `stac_url`, `collection`, `asset`). Repeat
calls with the same AOI and parameters reuse the cache; changing any of
them re-fetches.

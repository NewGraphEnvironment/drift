# Get STAC configuration for a known source

Returns connection details for pre-configured STAC collections. Used as
a convenience wrapper around
[`dft_stac_fetch()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_fetch.md)
(categorical sources) and
[`dft_stac_cube()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_cube.md)
(continuous index-trajectory sources) so users don't need to remember
STAC URLs, collection IDs, and band names.

## Usage

``` r
dft_stac_config(
  source = c("io-lulc", "esa-worldcover", "sentinel-2-l2a", "modis-13Q1-061")
)
```

## Arguments

- source:

  Character. One of `"io-lulc"` (Esri IO LULC annual v02),
  `"esa-worldcover"` (ESA WorldCover), `"sentinel-2-l2a"` (Sentinel-2
  L2A surface reflectance at 10 m from 2017, a cube source), or
  `"modis-13Q1-061"` (MODIS Terra/Aqua MOD13Q1 v6.1 reflectance, 16-day
  composites at 250 m from 2000-02-18, a cube source).

## Value

A list. Categorical sources have elements `stac_url`, `collection`,
`asset`, `available_years`. Cube sources have `stac_url`, `collection`,
`cube = TRUE`, `roles` (a named list mapping the roles the source has,
from `red`/`green`/`blue`/`nir`/`swir16`, and `mask`, to asset names;
MODIS has no `green` or `swir16`), `mask_values` (integer mask classes
to exclude), `scale`/`offset` (DN → reflectance affine transform), and
`available_datetime` (an ISO 8601 interval string). A cube source may
also carry `res` (its native resolution in metres, used when the caller
passes none) and `cloud_cover = FALSE` (its items have no
`eo:cloud_cover`, so no scene-level cloud filter applies). The `cube`
field is absent (not `FALSE`) for categorical sources; test with
`isTRUE(cfg$cube)`.

## Details

Sources are of two kinds. **Categorical** sources (`"io-lulc"`,
`"esa-worldcover"`) host single-band classified rasters and carry a flat
`asset` name for
[`dft_stac_fetch()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_fetch.md).
**Cube** sources (`"sentinel-2-l2a"`, `"modis-13Q1-061"`) host
multi-band reflectance imagery and instead carry a role-based band map
(some of `red`/`green`/`blue`/`nir`/`swir16`, plus `mask`), mask values,
and reflectance scale/offset for
[`dft_stac_cube()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_cube.md);
they are marked with `cube = TRUE`. The role-based schema means a new
reflectance source (e.g. Landsat C2 L2) drops in with no API change —
only the role→asset map and scale/offset differ.

## Examples

``` r
dft_stac_config("io-lulc")
#> $stac_url
#> [1] "https://planetarycomputer.microsoft.com/api/stac/v1"
#> 
#> $collection
#> [1] "io-lulc-annual-v02"
#> 
#> $asset
#> [1] "data"
#> 
#> $available_years
#> [1] 2017 2018 2019 2020 2021 2022 2023
#> 
dft_stac_config("esa-worldcover")
#> $stac_url
#> [1] "https://planetarycomputer.microsoft.com/api/stac/v1"
#> 
#> $collection
#> [1] "esa-worldcover"
#> 
#> $asset
#> [1] "map"
#> 
#> $available_years
#> [1] 2020 2021
#> 
dft_stac_config("sentinel-2-l2a")
#> $stac_url
#> [1] "https://planetarycomputer.microsoft.com/api/stac/v1"
#> 
#> $collection
#> [1] "sentinel-2-l2a"
#> 
#> $cube
#> [1] TRUE
#> 
#> $roles
#> $roles$red
#> [1] "B04"
#> 
#> $roles$green
#> [1] "B03"
#> 
#> $roles$blue
#> [1] "B02"
#> 
#> $roles$nir
#> [1] "B08"
#> 
#> $roles$swir16
#> [1] "B11"
#> 
#> $roles$mask
#> [1] "SCL"
#> 
#> 
#> $mask_values
#> [1]  3  8  9 10 11
#> 
#> $scale
#> [1] 1e-04
#> 
#> $offset
#> [1] -0.1
#> 
#> $offset_boundary
#> [1] "2022-01-25"
#> 
#> $offset_before
#> [1] 0
#> 
#> $available_datetime
#> [1] "2017-01-01/2024-12-31"
#> 
dft_stac_config("modis-13Q1-061")$roles
#> $red
#> [1] "250m_16_days_red_reflectance"
#> 
#> $nir
#> [1] "250m_16_days_NIR_reflectance"
#> 
#> $blue
#> [1] "250m_16_days_blue_reflectance"
#> 
#> $mask
#> [1] "250m_16_days_pixel_reliability"
#> 
```

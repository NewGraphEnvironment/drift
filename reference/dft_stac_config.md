# Get STAC configuration for a known source

Returns connection details for pre-configured STAC collections. Used as
a convenience wrapper around
[`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
(categorical sources) and
[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
(continuous index-trajectory sources) so users don't need to remember
STAC URLs, collection IDs, and band names.

## Usage

``` r
dft_stac_config(source = c("io-lulc", "esa-worldcover", "sentinel-2-l2a"))
```

## Arguments

- source:

  Character. One of `"io-lulc"` (Esri IO LULC annual v02),
  `"esa-worldcover"` (ESA WorldCover), or `"sentinel-2-l2a"` (Sentinel-2
  L2A surface reflectance, a cube source).

## Value

A list. Categorical sources have elements `stac_url`, `collection`,
`asset`, `available_years`. Cube sources have `stac_url`, `collection`,
`cube = TRUE`, `roles` (a named list mapping `red`/`nir`/`swir16`/`mask`
to asset names), `mask_values` (integer mask classes to exclude),
`scale`/`offset` (DN → reflectance affine transform), and
`available_datetime` (an ISO 8601 interval string). The `cube` field is
absent (not `FALSE`) for categorical sources; test with
`isTRUE(cfg$cube)`.

## Details

Sources are of two kinds. **Categorical** sources (`"io-lulc"`,
`"esa-worldcover"`) host single-band classified rasters and carry a flat
`asset` name for
[`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md).
**Cube** sources (`"sentinel-2-l2a"`) host multi-band reflectance
imagery and instead carry a role-based band map
(`red`/`nir`/`swir16`/`mask`), mask values, and reflectance scale/offset
for
[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md);
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
```

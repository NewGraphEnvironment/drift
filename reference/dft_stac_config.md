# Get STAC configuration for a known land cover source

Returns connection details for pre-configured STAC collections. Used as
a convenience wrapper around
[`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
so users don't need to remember STAC URLs and collection IDs.

## Usage

``` r
dft_stac_config(source = c("io-lulc", "esa-worldcover"))
```

## Arguments

- source:

  Character. One of `"io-lulc"` (Esri IO LULC annual v02) or
  `"esa-worldcover"` (ESA WorldCover).

## Value

A list with elements:

- stac_url:

  STAC API endpoint

- collection:

  Collection ID

- asset:

  Asset name to download

- available_years:

  Integer vector of available years

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
```

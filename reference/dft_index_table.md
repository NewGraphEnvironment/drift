# Load the shipped spectral-index registry

Reads the CSV index registry bundled with the package. Each row defines
one index as a `gdalcubes`/tinyexpr formula written over band roles.

## Usage

``` r
dft_index_table()
```

## Value

A tibble with columns `index`, `formula`, `roles` (comma-separated role
names), and `description`.

## Examples

``` r
dft_index_table()
#> # A tibble: 6 × 4
#>   index formula                                              roles   description
#>   <chr> <chr>                                                <chr>   <chr>      
#> 1 ndvi  (nir - red) / (nir + red)                            nir,red Normalized…
#> 2 kndvi tanh(pow((nir - red) / (nir + red), 2))              nir,red Kernel NDV…
#> 3 ndmi  (nir - swir16) / (nir + swir16)                      nir,sw… Normalized…
#> 4 ndwi  (green - nir) / (green + nir)                        green,… Normalized…
#> 5 mndwi (green - swir16) / (green + swir16)                  green,… Modified N…
#> 6 evi   2.5 * (nir - red) / (nir + 6 * red - 7.5 * blue + 1) nir,re… Enhanced V…
```

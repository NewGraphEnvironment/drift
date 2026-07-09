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
#> # A tibble: 3 × 4
#>   index formula                                 roles      description          
#>   <chr> <chr>                                   <chr>      <chr>                
#> 1 ndvi  (nir - red) / (nir + red)               nir,red    Normalized Differenc…
#> 2 kndvi tanh(pow((nir - red) / (nir + red), 2)) nir,red    Kernel NDVI (tanh of…
#> 3 ndmi  (nir - swir16) / (nir + swir16)         nir,swir16 Normalized Differenc…
```

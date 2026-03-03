# Load shipped class lookup table

Reads a CSV class table bundled with the package for a known source.

## Usage

``` r
dft_class_table(source = c("io-lulc", "esa-worldcover"))
```

## Arguments

- source:

  Character. One of `"io-lulc"` or `"esa-worldcover"`.

## Value

A tibble with columns `code`, `class_name`, `color`, `description`.

## Examples

``` r
dft_class_table("io-lulc")
#> # A tibble: 10 × 4
#>     code class_name         color   description                  
#>    <int> <chr>              <chr>   <chr>                        
#>  1     0 No Data            #000000 No data                      
#>  2     1 Water              #419bdf Water bodies                 
#>  3     2 Trees              #397d49 Tree cover                   
#>  4     4 Flooded Vegetation #7a87c6 Flooded vegetation / wetlands
#>  5     5 Crops              #e49635 Cropland                     
#>  6     7 Built Area         #c4281b Built-up / urban areas       
#>  7     8 Bare Ground        #a59b8f Bare ground / rock           
#>  8     9 Snow/Ice           #a8ebff Snow and ice                 
#>  9    10 Clouds             #616161 Cloud cover                  
#> 10    11 Rangeland          #e3e2c3 Grassland / shrubland        
```

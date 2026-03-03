# Summarize area by class

Compute area and percentage by class for a categorical raster,
optionally across multiple years.

## Usage

``` r
dft_rast_summarize(x, class_table = NULL, source = "io-lulc", unit = "ha")
```

## Arguments

- x:

  A
  [terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  or a named list of `SpatRaster`s. When a named list, each name is used
  as the `year` column in the output.

- class_table:

  A tibble with columns `code`, `class_name`, `color`. When `NULL`,
  loaded via
  [`dft_class_table()`](https://newgraphenvironment.github.io/drift/reference/dft_class_table.md)
  using `source`.

- source:

  Character. Used to load a shipped class table when `class_table` is
  `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.

- unit:

  Character. Area unit for the `area` column. One of `"ha"` (default),
  `"km2"`, or `"m2"`.

## Value

A tibble with columns:

- `year` (character, only when `x` is a named list)

- `code` (integer)

- `class_name` (character)

- `color` (character, hex)

- `n_cells` (integer)

- `area` (numeric, in requested `unit`)

- `pct` (numeric, percentage of total non-NA cells)

## Examples

``` r
r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
dft_rast_summarize(r, source = "io-lulc", unit = "ha")
#> # A tibble: 6 × 6
#>    code class_name color   n_cells  area   pct
#>   <int> <chr>      <chr>     <int> <dbl> <dbl>
#> 1     1 Water      #419bdf    1089 10.9   8.85
#> 2     2 Trees      #397d49    5542 55.4  45.0 
#> 3     5 Crops      #e49635     147  1.47  1.19
#> 4     7 Built Area #c4281b      10  0.1   0.08
#> 5     9 Snow/Ice   #a8ebff     185  1.85  1.5 
#> 6    11 Rangeland  #e3e2c3    5338 53.4  43.4 
```

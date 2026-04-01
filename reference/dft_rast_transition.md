# Detect land cover transitions between two time steps

Compare two classified rasters cell-by-cell and return a transition
raster and summary table. Each pixel is encoded with its from→to class
pair.

## Usage

``` r
dft_rast_transition(
  x,
  from,
  to,
  class_table = NULL,
  source = "io-lulc",
  from_class = NULL,
  to_class = NULL,
  unit = "ha",
  patch_area_min = NULL
)
```

## Arguments

- x:

  A named list of classified `SpatRaster`s (e.g. from
  [`dft_rast_classify()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_classify.md)).
  Names identify each time step (typically years).

- from:

  Character. Name of the "before" layer in `x`.

- to:

  Character. Name of the "after" layer in `x`.

- class_table:

  A tibble with columns `code`, `class_name`, `color`. When `NULL`,
  loaded via
  [`dft_class_table()`](https://newgraphenvironment.github.io/drift/reference/dft_class_table.md)
  using `source`.

- source:

  Character. Used to load a shipped class table when `class_table` is
  `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.

- from_class:

  Character vector of class names to include as "from" classes. When
  `NULL` (default), all classes are included.

- to_class:

  Character vector of class names to include as "to" classes. When
  `NULL` (default), all classes are included.

- unit:

  Character. Area unit for the summary. One of `"ha"` (default),
  `"km2"`, or `"m2"`.

- patch_area_min:

  Numeric or `NULL`. Minimum area in m² for a connected patch of changed
  pixels to be retained. Patches smaller than this threshold are set to
  `NA`. Uses 8-connected adjacency. `NULL` (default) skips filtering.

## Value

A list with three elements:

- `raster`: A `SpatRaster` with factor levels labelled
  `"from_class -> to_class"`. Filtered-out transitions are set to `NA`.

- `summary`: A tibble with columns `from_class`, `to_class`, `n_cells`,
  `area`, `pct`.

- `removed`: A `SpatRaster` of transitions removed by `patch_area_min`
  filtering, or `NULL` when no filtering is applied. Same factor
  encoding as `raster`.

## Examples

``` r
r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")

# All transitions
result <- dft_rast_transition(classified, from = "2017", to = "2020")
result$summary
#> # A tibble: 19 × 5
#>    from_class         to_class   n_cells  area   pct
#>    <chr>              <chr>        <int> <dbl> <dbl>
#>  1 Trees              Trees         5478 54.8  44.5 
#>  2 Rangeland          Rangeland     2908 29.1  23.6 
#>  3 Trees              Rangeland     1429 14.3  11.6 
#>  4 Crops              Rangeland      998  9.98  8.11
#>  5 Water              Water          940  9.4   7.64
#>  6 Rangeland          Crops          146  1.46  1.19
#>  7 Trees              Snow/Ice       121  1.21  0.98
#>  8 Trees              Water           98  0.98  0.8 
#>  9 Rangeland          Trees           62  0.62  0.5 
#> 10 Rangeland          Water           51  0.51  0.41
#> 11 Built Area         Snow/Ice        44  0.44  0.36
#> 12 Rangeland          Snow/Ice        19  0.19  0.15
#> 13 Built Area         Built Area      10  0.1   0.08
#> 14 Flooded Vegetation Rangeland        2  0.02  0.02
#> 15 Water              Rangeland        1  0.01  0.01
#> 16 Trees              Crops            1  0.01  0.01
#> 17 Built Area         Trees            1  0.01  0.01
#> 18 Snow/Ice           Trees            1  0.01  0.01
#> 19 Snow/Ice           Snow/Ice         1  0.01  0.01

# Only tree loss to agriculture
tree_loss <- dft_rast_transition(classified, from = "2017", to = "2020",
                                 from_class = "Trees",
                                 to_class = c("Crops", "Rangeland", "Bare Ground"))
tree_loss$summary
#> # A tibble: 2 × 5
#>   from_class to_class  n_cells  area   pct
#>   <chr>      <chr>       <int> <dbl> <dbl>
#> 1 Trees      Rangeland    1429 14.3  99.9 
#> 2 Trees      Crops           1  0.01  0.07

# Filter small patches (< 500 m² = 5 pixels at 10m)
filtered <- dft_rast_transition(classified, from = "2017", to = "2020",
                                patch_area_min = 500)
filtered$summary
#> # A tibble: 18 × 5
#>    from_class to_class   n_cells  area   pct
#>    <chr>      <chr>        <int> <dbl> <dbl>
#>  1 Trees      Trees         5478 54.8  44.8 
#>  2 Rangeland  Rangeland     2908 29.1  23.8 
#>  3 Trees      Rangeland     1397 14.0  11.4 
#>  4 Crops      Rangeland      998  9.98  8.15
#>  5 Water      Water          940  9.4   7.68
#>  6 Rangeland  Crops          143  1.43  1.17
#>  7 Trees      Snow/Ice       120  1.2   0.98
#>  8 Trees      Water           91  0.91  0.74
#>  9 Rangeland  Trees           47  0.47  0.38
#> 10 Built Area Snow/Ice        44  0.44  0.36
#> 11 Rangeland  Water           42  0.42  0.34
#> 12 Rangeland  Snow/Ice        19  0.19  0.16
#> 13 Built Area Built Area      10  0.1   0.08
#> 14 Water      Rangeland        1  0.01  0.01
#> 15 Trees      Crops            1  0.01  0.01
#> 16 Built Area Trees            1  0.01  0.01
#> 17 Snow/Ice   Trees            1  0.01  0.01
#> 18 Snow/Ice   Snow/Ice         1  0.01  0.01
```

# Classify a raster with factor levels and colors

Apply class names and a color table to a categorical `SpatRaster`,
optionally remapping (collapsing) classes into broader groups.

## Usage

``` r
dft_rast_classify(x, class_table = NULL, source = "io-lulc", remap = NULL)
```

## Arguments

- x:

  A
  [terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  or a named list of `SpatRaster`s (e.g. from
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)).

- class_table:

  A tibble with columns `code`, `class_name`, `color` (hex). When
  `NULL`, loaded via
  [`dft_class_table()`](https://newgraphenvironment.github.io/drift/reference/dft_class_table.md)
  using `source`.

- source:

  Character. Used to load a shipped class table when `class_table` is
  `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.

- remap:

  A named list for collapsing classes. Names are the new class names,
  values are character vectors of original `class_name`s to merge. For
  example, `list(Vegetation = c("Trees", "Rangeland"))`. When `NULL`, no
  remapping is applied.

## Value

Same structure as `x` — a `SpatRaster` or named list — with
[`terra::levels()`](https://rspatial.github.io/terra/reference/factors.html)
and
[`terra::coltab()`](https://rspatial.github.io/terra/reference/colors.html)
set.

## Examples

``` r
r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
classified <- dft_rast_classify(r, source = "io-lulc")
terra::is.factor(classified)
#> [1] TRUE
```

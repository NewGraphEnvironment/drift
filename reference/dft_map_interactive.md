# Interactive leaflet map for classified rasters

Build a toggleable leaflet map from classified `SpatRaster`s or remote
COG URLs served via titiler. Includes layer control, legend, and
fullscreen.

## Usage

``` r
dft_map_interactive(
  x,
  aoi = NULL,
  class_table = NULL,
  source = "io-lulc",
  titiler_url = getOption("drift.titiler_url"),
  basemaps = c(Light = "CartoDB.Positron", Satellite = "Esri.WorldImagery"),
  legend_position = "bottomright",
  zoom = 14
)
```

## Arguments

- x:

  A named list of classified
  [terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)s
  (e.g. from
  [`dft_rast_classify()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_classify.md))
  **or** a named character vector of COG URLs. A single `SpatRaster` or
  URL string is auto-wrapped into a length-1 list/vector. Names become
  the layer toggle labels (years, seasons, etc.).

- aoi:

  An `sf` polygon for the area of interest outline. `NULL` (default)
  omits the AOI layer.

- class_table:

  A tibble with columns `code`, `class_name`, `color` (hex). When
  `NULL`, loaded via
  [`dft_class_table()`](https://newgraphenvironment.github.io/drift/reference/dft_class_table.md)
  using `source`.

- source:

  Character. Used to load a shipped class table when `class_table` is
  `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.

- titiler_url:

  Base URL of a titiler instance (e.g. `"https://titiler.example.com"`).
  Only used when `x` contains COG URLs. Defaults to
  `getOption("drift.titiler_url")`. If `NULL` in COG mode, an error is
  raised prompting the user to set the option.

- basemaps:

  Named character vector of provider tile IDs. The first element is the
  default basemap. Names become radio button labels.

- legend_position:

  Legend placement passed to
  [`leaflet::addLegend()`](https://rstudio.github.io/leaflet/reference/addLegend.html).
  Set to `NULL` to suppress the legend.

- zoom:

  Initial zoom level.

## Value

A
[leaflet::leaflet](https://rstudio.github.io/leaflet/reference/leaflet.html)
htmlwidget. The first layer in `x` is visible by default; other layers
are hidden but toggleable.

## Examples

``` r
# Single classified raster — returns a leaflet widget
r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
classified <- dft_rast_classify(r, source = "io-lulc")
map <- dft_map_interactive(classified)
class(map)
#> [1] "leaflet"    "htmlwidget"

# Multiple years with AOI — toggle between time periods
aoi <- sf::st_read(
  system.file("extdata", "example_aoi.gpkg", package = "drift"),
  quiet = TRUE
)
files <- c("2017" = "example_2017.tif", "2020" = "example_2020.tif",
           "2023" = "example_2023.tif")
rasters <- lapply(files, function(f) {
  terra::rast(system.file("extdata", f, package = "drift"))
})
classified <- dft_rast_classify(rasters, source = "io-lulc")
map <- dft_map_interactive(classified, aoi = aoi)
if (interactive()) map

if (FALSE) { # \dontrun{
# Remote COGs via titiler (requires options(drift.titiler_url = "..."))
cogs <- c("2017" = "https://bucket.s3.amazonaws.com/lulc_2017.tif",
          "2023" = "https://bucket.s3.amazonaws.com/lulc_2023.tif")
dft_map_interactive(cogs, source = "io-lulc")
} # }
```

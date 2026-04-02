# Vectorize transition raster into individual change patches

Convert a transition `SpatRaster` (from
[`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md))
into `sf` polygons — one row per connected patch of pixels sharing the
same transition type. Useful for QA in GIS, spatial attribution to
management zones, and patch-level reporting.

## Usage

``` r
dft_transition_vectors(x, zones = NULL, zone_col = NULL, patch_area_min = NULL)
```

## Arguments

- x:

  A factor `SpatRaster` from
  [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  (the `$raster` element). Must have a projected CRS.

- zones:

  Optional `sf` polygon layer for spatial attribution. Any partitioning:
  sub-basins, parcels, climate regions, management units.

- zone_col:

  Character. Column name in `zones` identifying each zone. Required when
  `zones` is supplied.

- patch_area_min:

  Numeric or `NULL`. Minimum patch area in m². Patches smaller than this
  are dropped before returning. `NULL` (default) keeps all.

## Value

An `sf` data frame (polygon geometry) with columns:

- `patch_id` (integer) — connected component ID

- `transition` (character) — transition label (e.g. "Trees -\>
  Rangeland")

- `area_ha` (numeric) — patch area in hectares

- Zone column (if `zones` supplied) — from spatial intersection

## Examples

``` r
r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
r20 <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
classified <- dft_rast_classify(list("2017" = r17, "2020" = r20), source = "io-lulc")
result <- dft_rast_transition(classified, from = "2017", to = "2020")

# Vectorize all transition patches
patches <- dft_transition_vectors(result$raster)
head(patches)
#> Simple feature collection with 6 features and 3 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: 683391.9 ymin: 6029786 xmax: 686631.9 ymax: 6030196
#> Projected CRS: WGS 84 / UTM zone 9N
#>   patch_id         transition area_ha                       geometry
#> 1        1     Water -> Water    5.91 POLYGON ((686221.9 6030196,...
#> 2        2     Water -> Water    3.49 POLYGON ((683391.9 6030126,...
#> 3        3 Water -> Rangeland    0.01 POLYGON ((686441.9 6030106,...
#> 4        4     Trees -> Water    0.02 POLYGON ((686151.9 6030186,...
#> 5        5     Trees -> Water    0.35 MULTIPOLYGON (((686441.9 60...
#> 6        6     Trees -> Water    0.01 POLYGON ((683401.9 6030136,...

# Filter to large patches only
patches_large <- dft_transition_vectors(result$raster, patch_area_min = 1000)
head(patches_large)
#> Simple feature collection with 6 features and 3 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: 683391.9 ymin: 6029066 xmax: 686631.9 ymax: 6030576
#> Projected CRS: WGS 84 / UTM zone 9N
#>    patch_id     transition area_ha                       geometry
#> 1         1 Water -> Water    5.91 POLYGON ((686221.9 6030196,...
#> 2         2 Water -> Water    3.49 POLYGON ((683391.9 6030126,...
#> 5         5 Trees -> Water    0.35 MULTIPOLYGON (((686441.9 60...
#> 11       11 Trees -> Water    0.28 POLYGON ((683591.9 6030026,...
#> 13       13 Trees -> Water    0.12 POLYGON ((686511.9 6029836,...
#> 15       15 Trees -> Trees   24.46 MULTIPOLYGON (((685251.9 60...
```

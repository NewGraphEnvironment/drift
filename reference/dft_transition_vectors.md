# Vectorize transition raster into individual change patches

Convert a transition `SpatRaster` (from
[`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md))
into `sf` polygons — one row per connected patch of pixels sharing the
same transition type. Useful for QA in GIS, spatial attribution to
management zones, and patch-level reporting.

## Usage

``` r
dft_transition_vectors(
  x,
  zones = NULL,
  zone_col = NULL,
  patch_area_min = NULL,
  changes_only = FALSE
)
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

- changes_only:

  Logical. When `TRUE`, drop stable (`from == to`) transitions before
  polygonizing, so only actual change patches are vectorized. On a
  floodplain the stable mosaic is most of the grid, so this is the main
  memory lever for large AOIs. Default `FALSE` keeps every patch
  (including stable ones).

## Value

An `sf` data frame (polygon geometry) with columns:

- `patch_id` (integer) — connected component ID, numbered in raster scan
  order over the returned patches

- `transition` (character) — transition label (e.g. "Trees -\>
  Rangeland")

- `area_ha` (numeric) — patch area in hectares

- Zone column (if `zones` supplied) — from spatial intersection

When `patch_area_min` or `changes_only` drop patches, `patch_id` is
numbered over the surviving patches (dense `1..n`), not the pre-filter
grid.

## Details

Patches are 8-connected components of same-valued cells, computed in a
single pass over the grid, so large sparse rasters vectorize without
per-class memory cost.

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
#> Bounding box:  xmin: 683911.9 ymin: 6029066 xmax: 685681.9 ymax: 6030576
#> Projected CRS: WGS 84 / UTM zone 9N
#>   patch_id             transition area_ha                       geometry
#> 1        1         Trees -> Trees   24.46 MULTIPOLYGON (((685251.9 60...
#> 2        2 Rangeland -> Rangeland   14.72 POLYGON ((684831.9 6030566,...
#> 3        3     Rangeland -> Crops    1.16 POLYGON ((684871.9 6030566,...
#> 4        4     Rangeland -> Trees    0.01 POLYGON ((684881.9 6030566,...
#> 5        5         Trees -> Trees    0.65 MULTIPOLYGON (((684591.9 60...
#> 6        6     Rangeland -> Trees    0.04 MULTIPOLYGON (((684631.9 60...

# Filter to large patches only
patches_large <- dft_transition_vectors(result$raster, patch_area_min = 1000)
head(patches_large)
#> Simple feature collection with 6 features and 3 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: 683911.9 ymin: 6029066 xmax: 685711.9 ymax: 6030576
#> Projected CRS: WGS 84 / UTM zone 9N
#>   patch_id             transition area_ha                       geometry
#> 1        1         Trees -> Trees   24.46 MULTIPOLYGON (((685251.9 60...
#> 2        2 Rangeland -> Rangeland   14.72 POLYGON ((684831.9 6030566,...
#> 3        3     Rangeland -> Crops    1.16 POLYGON ((684871.9 6030566,...
#> 4        4         Trees -> Trees    0.65 MULTIPOLYGON (((684591.9 60...
#> 5        5 Built Area -> Snow/Ice    0.35 POLYGON ((685661.9 6030406,...
#> 6        6     Rangeland -> Crops    0.18 POLYGON ((684911.9 6030366,...

# Only actual changes (drop stable from == to patches before polygonizing)
changes <- dft_transition_vectors(result$raster, changes_only = TRUE)
head(changes)
#> Simple feature collection with 6 features and 3 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: 684631.9 ymin: 6030386 xmax: 685031.9 ymax: 6030566
#> Projected CRS: WGS 84 / UTM zone 9N
#>   patch_id         transition area_ha                       geometry
#> 1        1 Rangeland -> Crops    1.16 POLYGON ((684871.9 6030566,...
#> 2        2 Rangeland -> Trees    0.01 POLYGON ((684881.9 6030566,...
#> 3        3 Rangeland -> Trees    0.04 MULTIPOLYGON (((684631.9 60...
#> 4        4 Rangeland -> Trees    0.01 POLYGON ((684651.9 6030486,...
#> 5        5 Rangeland -> Trees    0.02 MULTIPOLYGON (((684971.9 60...
#> 6        6 Rangeland -> Trees    0.01 POLYGON ((684661.9 6030446,...
```

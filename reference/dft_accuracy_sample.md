# Draw a stratified random sample of points for accuracy assessment

Draw random cells within each stratum of a raster – the map classes, a
transition map, or strata the caller built, such as "change attributed
to fire / unattributed / stable" – as the sample design behind
[`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md),
following Olofsson et al. (2014).

## Usage

``` r
dft_accuracy_sample(strata, n, seed, map = NULL)
```

## Arguments

- strata:

  A single-layer
  [terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  of integer stratum codes in a projected CRS. `NA` cells are outside
  the population. A factor raster (e.g. `$raster` from
  [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  or
  [`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md))
  keeps its codes as `stratum` and its labels as `stratum_label`.

- n:

  Sample size per stratum: a single number for equal allocation, or a
  vector named by stratum code (e.g. from
  [`dft_accuracy_size()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_size.md))
  covering every stratum present. Each must be at least 2.

- seed:

  Integer seed. Required: the draw is part of the record, and a sample
  nobody can redraw cannot be audited.

- map:

  Optional. The map being assessed, on the same grid as `strata`: a
  single-layer SpatRaster (becomes `map_class`), a multi-layer
  SpatRaster or a named list of single-layer SpatRasters (become
  `map_<name>`, e.g. `map_2017` for a series). Values are read as raw
  codes, so a transition map gives its `from * 1000 + to` id.

## Value

A list:

- `points` – `sf` points at cell centres: `point_id`, `stratum`,
  `stratum_label`, `cell`, and any `map_*` columns. The geometry is the
  location; there are no coordinate columns to disagree with it.

- `strata` – tibble: `stratum`, `stratum_label`, `n_cells` (`N_h`),
  `area` (ha), `weight` (`N_h / N`), `n` (points drawn). This is the
  `strata` argument
  [`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md)
  takes.

- `design` – list recording how to redraw it: seed, RNG kinds,
  allocation requested, census strata, R and terra versions, and the
  grid's dimensions, extent and CRS.

## Details

Points, not patches: sampling patches over-weights large ones, and area
is the quantity being estimated.

## Reproducible, and extensible from a pilot

The draw uses only R's own random number generator and the raster's cell
order – not
[`terra::spatSample()`](https://rspatial.github.io/terra/reference/sample.html),
whose output is not promised stable across terra versions. Each stratum
gets its own random stream, seeded from `seed` and the stratum code,
with the generator kinds pinned (Mersenne-Twister, Inversion,
Rejection), so:

- the same `seed`, `n` and raster give the same points on any machine;

- **raising `n` extends the sample**: the first 30 points of a stratum
  at `n = 50` are the 30 points drawn at `n = 30`, so labels from a
  pilot carry into the full sample (`point_id` is stable too);

- changing one stratum's `n`, or adding a stratum, leaves every other
  stratum's points unchanged.

The caller's random number state is restored afterwards.

`cell` is a cell number on this grid. Cropping or extending the raster
renumbers cells, so draw from the grid the map is on and keep it.

## Small strata

A stratum with no more cells than its allocation is taken whole – a
census – and a message names it. Transition strata with a handful of
cells are normal.
[`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md)
applies the finite population correction, so a census stratum
contributes no variance.

## Memory

The raster is read twice in row chunks of about ten million cells – once
to count cells per stratum, once to find the drawn cells – so a
floodplain-scale raster is never held in memory whole.

## Polygon strata

Rasterise onto the map's grid first, in memory, and mask to the map's
footprint so the population is the mapped area:
`strata <- terra::mask(terra::rasterize(polys, map, field = "stratum"), map)`.
Do not rasterise straight to a file with an integer `datatype`: terra
then writes cells no polygon covers as 0 rather than `NA`, and 0 becomes
a stratum.

## References

Olofsson, P., Foody, G.M., Herold, M., Stehman, S.V., Woodcock, C.E. and
Wulder, M.A. (2014). Good practices for estimating area and assessing
accuracy of land change. *Remote Sensing of Environment* 148, 42-57.
[doi:10.1016/j.rse.2014.02.015](https://doi.org/10.1016/j.rse.2014.02.015)

## See also

[`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md),
[`dft_accuracy_size()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_size.md),
[`dft_accuracy_labels()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_labels.md).

## Examples

``` r
map <- terra::rast(system.file("extdata", "example_2017.tif",
                               package = "drift"))

# strata are the map classes; two strata here have only 2 cells, which are
# taken whole
s <- dft_accuracy_sample(map, n = 20, seed = 81, map = map)
#> Taking all cells (a census) of 2 stratum/strata with no more cells than allocated: 4 (2), 9 (2).
s$strata
#> # A tibble: 7 × 6
#>   stratum stratum_label n_cells  area   weight     n
#>     <dbl> <chr>           <dbl> <dbl>    <dbl> <dbl>
#> 1       1 NA                941  9.41 0.0764      20
#> 2       2 NA               7127 71.3  0.579       20
#> 3       4 NA                  2  0.02 0.000162     2
#> 4       5 NA                998  9.98 0.0811      20
#> 5       7 NA                 55  0.55 0.00447     20
#> 6       9 NA                  2  0.02 0.000162     2
#> 7      11 NA               3186 31.9  0.259       20
head(s$points)
#> Simple feature collection with 6 features and 5 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 683406.9 ymin: 6029821 xmax: 686586.9 ymax: 6030101
#> Projected CRS: WGS 84 / UTM zone 9N
#>   point_id stratum stratum_label  cell map_class                 geometry
#> 1  1_00001       1          <NA> 24767         1 POINT (686556.9 6029821)
#> 2  1_00002       1          <NA> 15642         1 POINT (686586.9 6030101)
#> 3  1_00003       1          <NA> 22807         1 POINT (686516.9 6029881)
#> 4  1_00004       1          <NA> 20214         1 POINT (683406.9 6029951)
#> 5  1_00005       1          <NA> 15635         1 POINT (686516.9 6030101)
#> 6  1_00006       1          <NA> 21214         1 POINT (683626.9 6029921)

# a pilot of 20 per stratum extends to 40 without moving the first 20
s40 <- dft_accuracy_sample(map, n = 40, seed = 81)
#> Taking all cells (a census) of 2 stratum/strata with no more cells than allocated: 4 (2), 9 (2).
all(s$points$cell %in% s40$points$cell)
#> [1] TRUE
```

# Per-pixel index trend over time

Reduce an index stack (from
[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md))
to a per-pixel **trend** — the rate at which the index rises or falls
across the whole record. Where
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
finds an abrupt structural break, this measures the slow, monotonic
direction: gradual degradation (a declining stand) or recovery (a
restoration planting greening up) that annual categorical labels cannot
show.

## Usage

``` r
dft_rast_trend(cube, min_obs = 6, cores = NULL)
```

## Arguments

- cube:

  A monthly index `SpatRaster` (the return value of
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)):
  one layer per time step, with a time value per layer.

- min_obs:

  Integer. Minimum non-`NA` observations required; pixels with fewer
  return `NA` (default 6).

- cores:

  Integer or `NULL`. Forked workers for the per-pixel reduction. When
  `NULL`, uses one fewer than the detected cores.

## Value

A two-band
[terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with layers `trend` (index change per year — negative = declining
greenness, positive = recovering) and `trend_p` (Mann-Kendall two-sided
p-value; small = a significant monotonic trend).

## Details

The slope is a **Theil-Sen** estimate — the median of all pairwise
slopes — which is resistant to a single anomalous season (e.g. a
smoke/drought year), unlike an ordinary least-squares fit. Significance
is the non-parametric **Mann-Kendall** test for a monotonic trend.

## See also

[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
(abrupt breaks),
[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md).

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
cube <- dft_stac_cube(aoi, index = "kndvi", datetime = "2017-01-01/2023-12-31")
trend <- dft_rast_trend(cube)
terra::plot(trend[["trend"]])  # negative (red) = declining, positive = recovering
} # }
```

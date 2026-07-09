# Detect per-pixel index-trajectory breakpoints

Reduce a monthly index stack (from
[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md))
over time with
[`bfast::bfastmonitor()`](https://rdrr.io/pkg/bfast/man/bfastmonitor.html),
returning a two-band `SpatRaster` of the break date and magnitude for
every pixel. Where categorical differencing compares two land-cover
labels, this asks a stronger question of a continuous index trajectory:
*when* did the pixel's spectral history break, and by how much?

## Usage

``` r
dft_rast_break(
  cube,
  history = "all",
  start = c(2022, 1),
  frequency = NULL,
  order = 3,
  level = 0.01,
  min_obs = 6,
  cores = NULL
)
```

## Arguments

- cube:

  A monthly index `SpatRaster` (the return value of
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)):
  one layer per time step, with a time value per layer.

- history:

  Character. `bfastmonitor` history-selection method: `"all"` (default),
  `"ROC"`, or `"BP"`.

- start:

  Numeric `c(year, period)`. Start of the monitoring period, in the
  stack's temporal frequency (e.g. `c(2022, 1)` = Jan 2022 for a monthly
  stack). Everything before it is the stable history.

- frequency:

  Numeric or `NULL`. Seasonal frequency of the time series (12 for
  monthly, 1 for annual). When `NULL`, derived from the layer time
  spacing; when supplied, it must agree with that spacing or the call
  errors.

- order:

  Integer. Harmonic order of the season-trend model passed to
  [`bfast::bfastmonitor()`](https://rdrr.io/pkg/bfast/man/bfastmonitor.html)
  (default 3). Lower it (1-2) when the series samples only part of the
  year (e.g. a growing-season-only cube from
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  `months`), where a high order overfits sparse seasonal coverage.

- level:

  Numeric. Significance level passed to
  [`bfast::bfastmonitor()`](https://rdrr.io/pkg/bfast/man/bfastmonitor.html)
  (default 0.01).

- min_obs:

  Integer. Minimum non-`NA` observations required to attempt a fit;
  pixels with fewer return `NA` (default 6).

- cores:

  Integer or `NULL`. Forked workers for the per-pixel reduction. When
  `NULL`, uses one fewer than the detected cores.

## Value

A two-band
[terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with layers `break_date` (decimal year or `NA`) and `break_mag` (signed
index change; negative = index drop).

## Details

`bfastmonitor` fits a season-trend model to a stable *history* period,
then watches the *monitoring* period (from `start` onward) for a
structural break. The returned `break_mag` is the median
monitoring-period residual: **negative means the index dropped** (e.g.
vegetation loss / channel scour), positive means it rose
(establishment). `break_date` is a decimal year (e.g. `2022.42`) or `NA`
where no break was detected.

Pixels are reduced in parallel with
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html)
(forked workers, so the per-pixel logic and its parameters are inherited
directly). Pixels with fewer than `min_obs` valid observations
short-circuit to `NA`.

## See also

[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
(builds the input stack),
[`dft_index_expr()`](https://newgraphenvironment.github.io/drift/reference/dft_index_expr.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# Requires network + gdalcubes + bfast
aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
cube <- dft_stac_cube(aoi, index = "kndvi", datetime = "2019-01-01/2023-12-31")
breaks <- dft_rast_break(cube, start = c(2022, 1))
terra::plot(breaks[["break_mag"]])  # negative (blue) = scour / veg loss
} # }
```

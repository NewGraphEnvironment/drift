# Pick, per feature, the capture nearest a date

From the captures table of
[`dft_wayback_captures()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_captures.md),
keeps for each feature and each target `date` the one capture whose
acquisition date is nearest to it. The result names the release and zoom
to pass to
[`dft_wayback_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_fetch.md).

## Usage

``` r
dft_wayback_pick(captures, date)
```

## Arguments

- captures:

  A captures table from
  [`dft_wayback_captures()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_captures.md).
  Any table with `feature`, `capture_date` and `res_m` works;
  `release_date`, `release_id` and `cover` are used as tiebreaks when
  present.

- date:

  A `Date` vector (or character coercible by
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html)) of target dates.
  Duplicates are dropped.

## Value

A tibble with one row per feature and target date, for every feature
that has a dated capture: `feature`, `date`, the chosen capture's other
columns, and `days_from_date` (signed: negative is a capture before the
date). A feature with no capture has no row; merge with your feature ids
to list it. Sorted by feature, then date.

## Details

Captures are ranked by, in order:

1.  days between `capture_date` and `date`, either side;

2.  finer `res_m`;

3.  the later `release_date`, then the larger `release_id` (compared as
    a number). The same capture is usually served by many releases, and
    any of them fetches it: a release that has not changed a tile
    redirects to the release that last did;

4.  the larger `cover`, then the earlier `capture_date`, then `source`,
    so the order is total even for a polygon that shows two captures
    equally near the date in one release.

Cover enters only as a tiebreak. For polygons, filter on `cover` before
the pick when the capture must image most of each feature.

A study design that bands by whole years (a capture in the endpoint year
before any capture a year off) expresses the band through the date: pass
mid-season, e.g. `as.Date("2017-07-01")`, and check `days_from_date` in
the result. The ranking itself does not band.

## See also

[`dft_wayback_captures()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_captures.md),
[`dft_wayback_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_fetch.md).

## Examples

``` r
cap <- tibble::tibble(
  feature = c(1L, 1L, 1L, 2L),
  release_id = c("100", "200", "300", "300"),
  release_date = as.Date(c("2017-11-16", "2020-04-29", "2024-03-07", "2024-03-07")),
  capture_date = as.Date(c("2013-08-01", "2017-06-11", "2023-08-25", "2016-09-30")),
  res_m = c(0.5, 0.5, 0.3, 0.5),
  source = "Maxar WV02", zoom = 18L, cover = 1
)
# the capture nearest mid-season in each endpoint year
dft_wayback_pick(cap, as.Date(c("2017-07-01", "2023-07-01")))
#> # A tibble: 4 × 10
#>   feature date       release_id release_date capture_date res_m source      zoom
#>     <int> <date>     <chr>      <date>       <date>       <dbl> <chr>      <int>
#> 1       1 2017-07-01 200        2020-04-29   2017-06-11     0.5 Maxar WV02    18
#> 2       1 2023-07-01 300        2024-03-07   2023-08-25     0.3 Maxar WV02    18
#> 3       2 2017-07-01 300        2024-03-07   2016-09-30     0.5 Maxar WV02    18
#> 4       2 2023-07-01 300        2024-03-07   2016-09-30     0.5 Maxar WV02    18
#> # ℹ 2 more variables: cover <dbl>, days_from_date <int>
```

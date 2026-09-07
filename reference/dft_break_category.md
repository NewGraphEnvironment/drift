# Temporal category of every row of a break-class summary

Compose
[`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md)'s
threshold-free measurements into the labelled split the package and its
consumers actually report: whether a transition is a switch that held, a
switch that turns on a single endpoint observation, or a sequence that
never settled — and, for the last of those, whether the endpoints differ
at all.

## Usage

``` r
dft_break_category(x, years = NULL, rule = "v1")
```

## Arguments

- x:

  Either the list returned by
  [`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md)
  (its `$summary` and `$years` are used) or a `$summary`-shaped data
  frame, in which case `years` is required. Columns `from_class`,
  `to_class`, `status` and `break_year` must be present.

- years:

  Integer vector of the observation years in the series. Ignored with a
  warning when `x` is a
  [`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md)
  result, which carries its own.

- rule:

  Character. The labelling rule to apply. Only `"v1"` exists; it is
  recorded in the returned `rule` column so old output identifies the
  rule that produced it.

## Value

`x`'s summary with three columns appended, its class and **row order**
preserved (`$summary` arrives sorted by `n_cells` descending):

- `category` — a factor with the five levels below, in that order

- `strength` —
  [`dft_break_strength()`](https://newgraphenvironment.github.io/drift/reference/dft_break_strength.md),
  `NA` off a clean switch

- `rule` — the rule that produced `category`

## Details

[`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md)
deliberately applies no threshold. Composing the label is a judgement,
so it lives here, in one place, under a version — see `rule`. The
numbers it rests on stay where they were measured.

`NA` propagates: a row whose pixels carry an `NA` in any interior year
cannot be scanned, arrives from
[`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md)
with `status` `NA`, and is labelled `NA` rather than refused. It is the
only `NA` this function produces, which is why an unlabelable class code
is an error instead. The bundled example series has no such row — mask a
year, or classify a series with a real `NA` in it, to see one.

A `status` value outside `stable` /
[`break`](https://rdrr.io/r/base/Control.html) / `flicker`, or a
[`break`](https://rdrr.io/r/base/Control.html) row carrying no
`break_year`, is an error rather than an `NA`: both mean the frame did
not come from
[`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md).

## The `"v1"` rule

|     |                   |                                         |
|-----|-------------------|-----------------------------------------|
| 0   | `stable`          | `status == "stable"`                    |
| 1   | `break_sustained` | a clean switch, `strength >= 2`         |
| 2   | `break_endpoint`  | a clean switch, `strength == 1`         |
| 3   | `unsettled`       | never settles, and the endpoints differ |
| 4   | `stable_flicker`  | never settles, and the endpoints agree  |

Levels 3 and 4 are the reason this function exists. A two-epoch
comparison reports level 3 as change and cannot see level 4 at all, so
they are used differently and must never be added together: on the
Bulkley floodplain that is 2,032.9 ha against 3,186.5 ha, and summing
them gives 7,811.5 ha of "changed" area where the published layer says
4,625.0 — a 69% overstatement.

`strength` is thresholded at 2 and the threshold is **not** an argument:
a free threshold would mean `rule = "v1"` no longer identifies the
labelling, which is the composition problem this function exists to end.
Use
[`dft_break_strength()`](https://newgraphenvironment.github.io/drift/reference/dft_break_strength.md)
directly for another cut.

`n_flips` is not part of this function's surface. It stays on `$breaks`,
where it is measured.

## See also

[`dft_rast_break_category()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_category.md)
for the same rule at pixel grain;
[`dft_break_strength()`](https://newgraphenvironment.github.io/drift/reference/dft_break_strength.md)
for the number it thresholds;
[`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md)
for the measurements.

## Examples

``` r
years <- 2017:2023
rasters <- lapply(years, function(yr) {
  terra::rast(system.file("extdata", paste0("example_", yr, ".tif"),
                          package = "drift"))
})
names(rasters) <- years
res <- dft_rast_break_class(dft_rast_classify(rasters, source = "io-lulc"))

cat_tbl <- dft_break_category(res)
head(cat_tbl[c("from_class", "to_class", "category", "strength", "rule")])
#> # A tibble: 6 × 5
#>   from_class to_class  category       strength rule 
#>   <chr>      <chr>     <fct>             <int> <chr>
#> 1 Trees      Trees     stable               NA v1   
#> 2 Rangeland  Rangeland stable               NA v1   
#> 3 Trees      Trees     stable_flicker       NA v1   
#> 4 Rangeland  Rangeland stable_flicker       NA v1   
#> 5 Water      Water     stable               NA v1   
#> 6 Trees      Rangeland unsettled            NA v1   

# the two populations a four-level vocabulary pools, kept apart
tapply(cat_tbl$area, cat_tbl$category, sum)
#>          stable break_sustained  break_endpoint       unsettled  stable_flicker 
#>           61.17           10.98           10.40           12.65           27.91 

# a summary read back from CSV needs the series stated
dft_break_category(as.data.frame(res$summary), years = years)$category[1:5]
#> [1] stable         stable         stable_flicker stable_flicker stable        
#> Levels: stable break_sustained break_endpoint unsettled stable_flicker
```

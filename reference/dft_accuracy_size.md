# Size and allocate a stratified accuracy sample

How many reference points a stratified sample needs to hit a target
standard error, and how to split them across strata – Olofsson et al.
(2014), Eq. 13 and section 5.1.

## Usage

``` r
dft_accuracy_size(
  weights,
  se_target,
  s_h = NULL,
  ua = NULL,
  allocation = c("proportional_min", "equal", "proportional"),
  n_min = 50
)
```

## Arguments

- weights:

  Numeric stratum weights (`N_h / N`), summing to 1, named by stratum –
  `$strata$weight` from
  [`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md),
  or from
  [`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md)'s
  `$stratum` table.

- se_target:

  The standard error to achieve for the estimate being planned for, as a
  proportion (0.01 is one percentage point). For an area, that is the
  class's share of total area.

- s_h:

  Per-stratum standard deviation of the indicator behind that estimate,
  in the order of `weights` (or matched by name when both are named).
  From a pilot, take `sd` from
  [`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md)`$stratum`
  for the target: `"agreement"` to plan for overall accuracy, or a
  reference class to plan for its area.

- ua:

  Alternatively, anticipated user's accuracy per stratum. Valid only
  when **the strata are the map classes**, where the SD of the agreement
  indicator in stratum `i` is `sqrt(ua_i * (1 - ua_i))` (Olofsson Eq.
  13). Give `s_h` or `ua`, not both.

- allocation:

  How to split `n` across strata:

  - `"equal"` – `n / H` each;

  - `"proportional"` – `n * weight`;

  - `"proportional_min"` (default) – at least `n_min` in every stratum,
    the remainder proportional to weight among the others. This is
    Olofsson's recommendation for change maps, where the change strata
    are rare and proportional allocation would give them a handful of
    points.

- n_min:

  Minimum points per stratum for `"proportional_min"`. Olofsson suggests
  50-100 per change stratum. Default 50.

## Value

A list: `n`, the total from Eq. 13 (rounded up); `allocation`, the
per-stratum sizes named by stratum, ready for
[`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md)'s
`n`; and the `s_h` used. Allocations are rounded, so they can sum to a
point or two either side of `n`.

## Details

Eq. 13 is `n = (sum(W_h * S_h) / SE)^2`. Its finite-population term is
dropped, which is safe when strata hold millions of cells and
conservative otherwise.

The allocation changes which estimates are precise, not whether they are
unbiased: any allocation with at least two points per stratum gives
unbiased estimates through
[`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md).
Check the anticipated standard errors of the estimates that matter – the
rare change classes' areas, typically – rather than overall accuracy
alone.

`s_h` of 0 (a pilot stratum where every point agreed) is legitimate and
makes that stratum contribute nothing to `n`; the minimum allocation
still samples it. A pilot that small understates the stratum's variance,
so treat a zero with suspicion.

## References

Olofsson, P., Foody, G.M., Herold, M., Stehman, S.V., Woodcock, C.E. and
Wulder, M.A. (2014). Good practices for estimating area and assessing
accuracy of land change. *Remote Sensing of Environment* 148, 42-57.
[doi:10.1016/j.rse.2014.02.015](https://doi.org/10.1016/j.rse.2014.02.015)

## See also

[`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md),
[`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md).

## Examples

``` r
# Olofsson et al. (2014) section 5.1.1: four strata that are the map
# classes, anticipated user's accuracies, and a target SE of 0.01 for
# overall accuracy -> n = 641
w <- c(deforestation = 0.020, forest_gain = 0.015,
       stable_forest = 0.320, stable_nonforest = 0.645)
dft_accuracy_size(w, se_target = 0.01, ua = c(0.70, 0.60, 0.90, 0.95),
                  allocation = "proportional")
#> $n
#> [1] 641
#> 
#> $allocation
#>    deforestation      forest_gain    stable_forest stable_nonforest 
#>               13               10              205              413 
#> 
#> $s_h
#>    deforestation      forest_gain    stable_forest stable_nonforest 
#>        0.4582576        0.4898979        0.3000000        0.2179449 
#> 

# From a pilot: size a full sample for the area of one class
map <- terra::rast(system.file("extdata", "example_2017.tif",
                               package = "drift"))
ref <- terra::rast(system.file("extdata", "example_2023.tif",
                               package = "drift"))
pilot <- dft_accuracy_sample(map, n = 20, seed = 1, map = map)
#> Taking all cells (a census) of 2 stratum/strata with no more cells than allocated: 4 (2), 9 (2).
pts <- sf::st_drop_geometry(pilot$points)
pts$ref_class <- terra::values(ref)[pts$cell, 1]   # stand-in reference
est <- dft_accuracy_estimate(pts, pilot$strata)
trees <- est$stratum[est$stratum$target == "2", ]  # IO LULC 2 = Trees
plan <- dft_accuracy_size(stats::setNames(trees$weight, trees$stratum),
                          se_target = 0.02, s_h = trees$sd, n_min = 20)
plan$allocation
#>  1  2  4  5  7  9 11 
#> 20 20 20 20 20 20 20 
```

# Accuracy and error-adjusted area from a stratified reference sample

Turn reference labels at stratified random sample points into the
numbers a change map should be reported with: an error matrix in
estimated proportions of area, overall / user's / producer's accuracy,
and **error-adjusted area per class with a confidence interval** –
following Olofsson et al. (2014) and Stehman (2014).

## Usage

``` r
dft_accuracy_estimate(labels, strata, level = 0.95)
```

## Arguments

- labels:

  A data frame meeting the
  [`dft_accuracy_labels()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_labels.md)
  contract: `point_id`, `stratum`, `map_class`, `ref_class`.

- strata:

  The `$strata` table from
  [`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md),
  or any data frame with `stratum`, `n_cells` (the stratum's size in
  cells, `n_cells_h`) and `area` (its mapped area in hectares).

- level:

  Confidence level for the intervals. Default `0.95`.

## Value

A list:

- `matrix` – tibble, long: `map_class`, `ref_class`, `proportion` (the
  estimated share of total area), one row per pair of classes, zeros
  included.

- `accuracy` – tibble: `measure` (`"overall"`, `"user"`, `"producer"`),
  `class` (`NA` for overall), `estimate`, `se`, `lower`, `upper`.

- `area` – tibble, one row per class: `proportion`, `proportion_se`,
  `area`, `area_se`, `lower`, `upper` (hectares).

- `stratum` – tibble, long, per stratum and `target`: `n`, `n_cells`,
  `weight`, `mean` and `sd` of an indicator within the stratum. `target`
  is `"agreement"` (map equals reference) or a reference class, written
  in full as a string (`"100000"`, never `"1e+05"`). `sd` is what
  [`dft_accuracy_size()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_size.md)
  takes to size a full sample from a pilot.

- `level`, `area_total` (ha).

## Details

Mapped area is a biased estimator whenever the map has errors, and for a
change map the bias is usually large: a single wrong label on either
date manufactures a transition. The error-adjusted area is the area the
*reference* labels imply, weighted back to the population by each
stratum's size.

## Estimators

The estimates come from
[`mapaccuracy::stehman2014()`](https://rdrr.io/pkg/mapaccuracy/man/stehman2014.html),
which implements Stehman (2014)'s estimators for stratified random
sampling. Those hold **whether or not the strata are the map classes** –
strata such as "change attributed to fire", "change unattributed" and
"stable" are fine. When the strata are the map classes they give
Olofsson et al. (2014)'s estimates, and the package test suite
reproduces that paper's worked example.

- The **finite population correction** `(1 - n_h / n_cells_h)` is always
  applied, so a stratum sampled in full (a census) contributes no
  variance. Olofsson et al. omit it; at pixel-scale `n_cells_h` the
  difference is below anything reported.

- Intervals are Wald intervals, `estimate +/- z * se` with
  `z = qnorm(1 - (1 - level) / 2)`, and are **not** truncated at 0 or 1:
  a lower bound below 0 says the class is too rare for the sample to
  bound away from zero, and truncating it would hide that.

- **A rare class hiding in a large stratum makes the interval too narrow
  at small samples.** If 1\\ the stratum gets 25 points, most samples
  see none of it, estimate that stratum's variance for *j* as 0, and
  report an interval that misses. On the bundled tiles (98 of 7,127
  "Trees" cells reference Water) Water's 95\\ at 75 and 89\\ hides in
  the large stable strata, so do not starve them.

- When the strata are not the map classes, the error matrix's row totals
  (the map-class shares) are **estimated** from the sample, not the
  known stratum weights. That surprises readers used to Olofsson's
  tables.

- Producer's accuracy is `NA` for a class no reference label falls in.

- Run time grows with roughly the 2.5th power of the number of classes:
  about 13 s for 1,000 points over 80 transition classes. Collapse
  classes you will not report before estimating.

## Targets that are unions of classes

"Tree loss" is every Trees -\> non-Trees transition; an "unattributed
residual" is loss outside any fire or harvest. Recode `map_class` and
`ref_class` to the target (say `"loss"` / `"other"`) and estimate again.
The standard error of a union is **not** the sum of its members'
standard errors, because the members' estimates are correlated.

## Training points

A row with `use == "training"` is refused. Points that trained a
classifier cannot also measure it – the estimate would be optimistic by
construction. Keep the accuracy sample separate from the start; a subset
of accuracy points chosen for training by judgement also stops being a
random sample of its stratum.

## References

Olofsson, P., Foody, G.M., Herold, M., Stehman, S.V., Woodcock, C.E. and
Wulder, M.A. (2014). Good practices for estimating area and assessing
accuracy of land change. *Remote Sensing of Environment* 148, 42-57.
[doi:10.1016/j.rse.2014.02.015](https://doi.org/10.1016/j.rse.2014.02.015)

Stehman, S.V. (2014). Estimating area and map accuracy for stratified
random sampling when the strata are different from the map classes.
*International Journal of Remote Sensing* 35(13), 4923-4939.
[doi:10.1080/01431161.2014.930207](https://doi.org/10.1080/01431161.2014.930207)

## See also

[`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md)
to draw the points,
[`dft_accuracy_labels()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_labels.md)
for the label contract,
[`dft_accuracy_size()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_size.md)
to size a sample from a pilot.

## Examples

``` r
# Olofsson et al. (2014), Table 8: 640 labelled points in four strata that
# are the map classes, over 10 million 30 m pixels
cls <- c("deforestation", "forest_gain", "stable_forest", "stable_nonforest")
counts <- matrix(c(66, 0, 5, 4,  0, 55, 8, 12,  1, 0, 153, 11,  2, 1, 9, 313),
                 nrow = 4, byrow = TRUE)
idx <- which(counts > 0, arr.ind = TRUE)
map <- rep(cls[idx[, 1]], counts[idx])
ref <- rep(cls[idx[, 2]], counts[idx])
labels <- data.frame(point_id = seq_along(map), stratum = map,
                     map_class = map, ref_class = ref)
pixels <- c(200000, 150000, 3200000, 6450000)
strata <- data.frame(stratum = cls, n_cells = pixels, area = pixels * 0.09)

res <- dft_accuracy_estimate(labels, strata)
res$area       # deforestation: 21,158 ha +/- 6,157 -- mapped was 18,000
#> # A tibble: 4 × 7
#>   class            proportion proportion_se    area area_se   lower   upper
#>   <chr>                 <dbl>         <dbl>   <dbl>   <dbl>   <dbl>   <dbl>
#> 1 deforestation        0.0235       0.00349  21158.   3142.  15000.  27315.
#> 2 forest_gain          0.0130       0.00213  11686.   1916.   7931.  15442.
#> 3 stable_forest        0.318        0.00879 285770.   7913. 270261. 301279.
#> 4 stable_nonforest     0.646        0.00923 581386.   8307. 565105. 597667.
res$accuracy
#> # A tibble: 9 × 6
#>   measure  class            estimate      se lower upper
#>   <chr>    <chr>               <dbl>   <dbl> <dbl> <dbl>
#> 1 overall  NA                  0.947 0.00943 0.928 0.965
#> 2 user     deforestation       0.88  0.0378  0.806 0.954
#> 3 user     forest_gain         0.733 0.0514  0.633 0.834
#> 4 user     stable_forest       0.927 0.0203  0.888 0.967
#> 5 user     stable_nonforest    0.963 0.0105  0.943 0.984
#> 6 producer deforestation       0.749 0.109   0.535 0.962
#> 7 producer forest_gain         0.847 0.130   0.593 1.10 
#> 8 producer stable_forest       0.935 0.0175  0.900 0.969
#> 9 producer stable_nonforest    0.962 0.00937 0.943 0.980
```

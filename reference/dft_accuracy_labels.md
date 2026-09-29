# Check a reference-label table against the accuracy-assessment contract

drift does not store reference labels; the caller does, in whatever
review tool they use. This is the contract such a table must meet before
[`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md)
will read it, so a review tool can be checked against it directly.

## Usage

``` r
dft_accuracy_labels(labels, strata = NULL)
```

## Arguments

- labels:

  A data frame with one row per labelled sample point.

- strata:

  Optional. The `$strata` table from
  [`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md),
  or any data frame with columns `stratum` and `n_cells`. When given,
  the labels are also checked for coverage of it.

## Value

`labels`, invisibly. Every fault is an error that names it.

## Columns

|              |          |                                           |
|--------------|----------|-------------------------------------------|
| `point_id`   | required | unique, non-missing sample point id       |
| `stratum`    | required | the stratum the point was drawn from      |
| `map_class`  | required | the map's class at the point              |
| `ref_class`  | required | the reference class the reviewer assigned |
| `confidence` | optional | reviewer confidence, carried and not read |
| `reviewer`   | optional | who labelled it, carried and not read     |
| `use`        | optional | `"accuracy"`, `"training"` or `NA`        |

`stratum` and `map_class` come from the design, not from the reviewer:
[`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md)
writes both (`map_class` through its `map` argument). Only `ref_class`,
and the optional columns, are the reviewer's.

## What is refused, and why

- **A missing or blank `ref_class`**
  ([`read.csv()`](https://rdrr.io/r/utils/read.table.html) reads an
  empty cell as `""`, not `NA`; both are refused). A point the reviewer
  could not label (cloud, no imagery) is nonresponse, and dropping it
  changes the stratum's sample size. That is a design decision, so the
  caller makes it explicitly – remove the rows and say so – rather than
  having it happen silently here.

- **A duplicated `point_id`**, which would count one point twice.

- **A stratum absent from `strata`**, a stratum with no cells that
  nevertheless has labels, or a stratum with cells but no labels: either
  way the labels do not cover the population the weights describe, and
  no estimator can repair that.

- **A `use` value other than `"accuracy"`, `"training"` or `NA`.**

Filtering by `confidence` before estimating is possible and is also a
design change: the kept points are no longer a random sample of their
stratum when low confidence is not random (it rarely is – edges, mixed
cells). Report it if you do it.

## Change maps

For accuracy of a transition map, `map_class` is the transition id and
`ref_class` is composed from the reviewer's two endpoint labels with the
same scheme
[`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
uses: `ref_from * 1000 + ref_to`. The contract needs no endpoint
columns; carry them alongside if useful.

## See also

[`dft_accuracy_estimate()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_estimate.md),
which calls this;
[`dft_accuracy_sample()`](https://newgraphenvironment.github.io/drift/reference/dft_accuracy_sample.md),
which writes `point_id`, `stratum` and `map_class`.

## Examples

``` r
labels <- data.frame(
  point_id  = c("1_00001", "1_00002", "2_00001", "2_00002"),
  stratum   = c(1, 1, 2, 2),
  map_class = c(1, 1, 2, 2),
  ref_class = c(1, 2, 2, 2)
)
dft_accuracy_labels(labels)

# a point nobody could label is refused, not dropped
labels$ref_class[2] <- NA
try(dft_accuracy_labels(labels))
#> Error : `ref_class` has 1 missing or blank value(s). A point that could not be labelled is nonresponse; remove it deliberately (it changes the stratum's sample size) rather than passing NA.
```

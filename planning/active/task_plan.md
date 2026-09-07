# Task: dft_rast_break_class(): expose the temporal split as a function, keep the confidence number, stop pooling two flicker populations (#72)

`dft_rast_break_class()` deliberately thresholds nothing: it reports `n_flips`, `break_year`,
`n_before`, `n_after` and lets the caller compose. That design stays. The cost is that the
composition now lives in **four** places, none of them in the package:

| where | grain | shape |
|---|---|---|
| `cat_fun()` — `data-raw/break_class_groups.R:100`, `data-raw/benchmark_break_class_bulk.R:102` | pixel | `$breaks` matrix -> 0..3 |
| `temporal_category()` — `data-raw/break_class_groups.R:274` | summary row | `status` + `break_year` -> label |
| `fig_fun()` — `data-raw/break_class_groups.R:478` | pixel | splits flicker by `changed` -> 0..4 |
| `is_sustained()` — `data-raw/disturbance_compare.R:110` | bare year | `pmin(i, n-i) >= 2` |

Two consequences:

1. **A four-level vocabulary that lets a reader pool two populations.** `cat_fun`'s category 3 is
   every `n_flips >= 2`, changed or not. On BULK that is 2,032.9 ha of changed-but-unsettled and
   3,186.5 ha that flickers while both endpoints agree. Nothing shipped actually pools them —
   `summary_change.csv` splits on `changed` — but the name invites it, and summing gives 7,811.5 ha
   where the published layer says 4,625.0, a **69% overstatement**.
2. **The confidence number is computed and discarded.** `pmin(n_before, n_after)` runs 1-3 on a
   seven-year series and survives only as its `>= 2` threshold, so "held five years" and "held one"
   collapse to the same label.

## Decisions taken at the plan gate

- **Three exports, split by grain**, not one function with a `grain =` switch. The paths share a
  predicate, not an implementation: one is pure R over a data frame, the other a streamed
  `terra::app()` over a 169M-cell grid with its own memory and datatype hazards. Splitting also
  leaves room for the patch grain (#67), which is a third return shape.
- **Names reuse the existing `dft_rast_` signal.** All six raster-returning exports carry it;
  `dft_transition_vectors()` reads as not-a-raster by its absence.
- **Vocabulary retires `flicker`.** Five levels, ids `0:4` in the order the article's colour table
  already keys on (`break_class_groups.R:602`).
- **`rule = "v1"` is a column, not an attribute** — every consumer here writes CSV, which drops
  attributes; the repo's own convention is *"`class_set` is a column, not a footnote"*.
- **`dft_rast_break_class()` gains `$years` and nothing else.** `$summary` and `$status` untouched.

## The API

```r
dft_break_strength(break_year, years)                     # integer    — a measurement, never versioned
dft_break_category(x, years = NULL, rule = "v1")          # tibble     — a label, versioned
dft_rast_break_category(x, rule = "v1", filename = NULL)  # SpatRaster — a label, versioned
```

One unexported `break_category_code()` holds the map; both label functions call it. That is the
single definition — two exports do not make two rules.

| id | level | condition |
|---|---|---|
| 0 | `stable` | `n_flips == 0` |
| 1 | `break_sustained` | `n_flips == 1 & strength >= 2` |
| 2 | `break_endpoint` | `n_flips == 1 & strength == 1` |
| 3 | `unsettled` | `n_flips >= 2 & from != to` |
| 4 | `stable_flicker` | `n_flips >= 2 & from == to` |

`NA` in -> `NA` out throughout.

## Phase 1: measurement and row-grain label (pure R, no terra)

- [x] `R/dft_break_strength.R` — `idx <- match(break_year, years) - 1L`, return `pmin(idx, n - idx)`.
      `years` sorted/unique/`length >= 2`; `NA_integer_` for `NA`; error on a `break_year` not in
      `years[-1]`. Document the unit as **observations, not years**, and `max_strength = floor(n/2)`.
- [x] `R/dft_break_category.R` — takes the result list or a bare `$summary` frame plus `years`.
      Adds `category` (factor, id order), `strength` (integer), `rule` (character). Preserves input
      row order. Named errors for missing `from_class`/`to_class` and for a list with no `$years`.
- [x] `$years` (sorted) on `dft_rast_break_class()`; update `expect_named()` at
      `test-dft_rast_break_class.R:18` and `:90`.
- [x] Tests: strength round-trip against `pmin(n_before, n_after)` over every fixture; named
      fixtures assert the vocabulary; `flicker` -> `stable_flicker` and `flicker_diff` -> `unsettled`
      (the pooling bug, one pixel each); `na_year` -> `NA` not an error; gapped and `n == 2` series.

## Phase 2: raster-grain label

- [x] `R/dft_rast_break_category.R` — one `app()` pass over `c(x$breaks, codes)` emitting
      `(category, strength)`. Strip the factor with `deepcopy()` + `set.cats(NULL)`.
- [x] terra discipline: pad when `ncol == 2L` (measured: a 2-column return on a 2-column raster is
      read as transposed and silently scrambled); matrix-only refusal; `filename =` on every write;
      `steps = ceiling(ncell / 2.5e6)`; `INT1U`; the parent's `files`/`on.exit` cleanup verbatim;
      factor ids pinned at `0:4` in article order; a `filename =` argument.
- [x] Tests: widths 1/2/3 against an arithmetic reference; `NA` round-trips from the written file as
      `NA` not 255; factor id/label table pinned; level set equals `class_value` in
      `inst/cartography/drift_temporal.csv`.
- [x] Pixel <-> summary parity on the bundled series (`test-dft_rast_break_class.R:369-396` pins
      3,403 / 1,265 / 2,791 / 1,098 / 776 + 264).
- [x] Pin the pooling case from `inst/extdata/temporal-composition/summary_groups.csv`: BULK
      `changed_ha == 4625.0`, `stable_flicker_ha == 3186.5`, pooled `== 7811.5`. Assert **no single
      level** carries the pooled figure.

## Phase 3: vocabulary and the row-grain callers (one coordinated commit)

- [ ] `inst/cartography/drift_temporal.csv`: `flicker` -> `unsettled`, carrying every column
      `gq_reg_custom()` reads.
- [ ] `break_class_groups.R` summarize stage: delete `temporal_category()`, call
      `dft_break_category()`.
- [ ] Equivalence gate from committed `summary_pixels.csv` (243/274/228/230 rows): new category
      equals old except `flicker`, which maps to `unsettled` where `changed` and `stable_flicker`
      otherwise, with **cell counts identical**. Not `git diff --exit-code` — the vocabulary changes.
- [ ] Regenerate `inst/extdata/temporal-composition/*.csv` and
      `data-raw/logs/break_class_groups/summary_groups.{csv,md}`; update the article's `keys`,
      `keys3` and `stopifnot` class set.
- [ ] Docs: `inst/extdata/temporal-composition/README.md:23-43` and `CLAUDE.md:118-120` must name
      the export. Reconcile "Confidence" / "sustained" / `strength`.

## Phase 4: disturbance_compare.R

- [ ] `is_sustained(by)` -> `dft_break_strength(by, years) >= 2`; re-run its summarize stage from
      committed logs and require the outputs unchanged.

## Phase 5: BULK scale test, and the pixel-grain callers

- [ ] Fetch `bulk_co_ff04` 2017-2023; run `dft_rast_break_category()` with an RSS sampler
      (start the long command alone on its own line, or `$!` is the subshell). Record wall-clock
      and peak RSS for the PR body.
- [ ] Migrate `cat_fun`/`fig_fun` in the `article-bulk` stage under its existing cell-for-cell
      self-check; regenerate `bulk_grid_1km.csv` and `bulk_window.rds` with `varnames()` pinned.
- [ ] Leave `data-raw/benchmark_break_class_bulk.R` alone; pointer comment only.

## Phase 6: release

- [ ] `devtools::document()`, `pkgdown::check_pkgdown()`, `lintr::lint_package()` against the `HEAD`
      baseline, full `devtools::test()`.
- [ ] `NEWS.md` + `DESCRIPTION` 0.15.0 -> **0.16.0**, as the final commit.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] Restore-the-bug proof: put the 4-level vocabulary back, confirm the parity and
      absent-pooled-number tests go red, via `NOT_CRAN=true testthat::test_file()`
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Acceptance (from the issue)

- [ ] One definition of the split in the package; the three re-derivations call it.
- [ ] `pmin(n_before, n_after)` reachable without recomputing it from `$breaks`.
- [ ] Existing `$summary` readers unaffected.
- [ ] Pooled and unpooled totals both reproducible, difference asserted — 4,625.0 vs 7,811.5 ha.

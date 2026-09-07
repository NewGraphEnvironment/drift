# Review round 3 — drift#72

Reviewed against `main...HEAD` plus the working tree. The tree moved three times
during the review (`cafbff6`, then `686158a`, then an uncommitted extraction of
`read_change()` into `data-raw/read_change.R`); everything below is stated against
the tree as of the last read. `devtools::test()` on it: **FAIL 0 | WARN 0 | SKIP 13
| PASS 1003**. `devtools::document()` produces no diff. `pkgdown::check_pkgdown()`
is silent.

## The mechanism the three rounds share

Rounds 1 and 2 and this one have each found a defect inside the previous round's
fix, and every one of them is the same shape:

> **A base-R coercion turns an absent or wrongly-shaped value into a legitimate,
> in-range value, and the guard beside it tests the value rather than its
> provenance — so the guard passes and the wrong number is published.**

The instances, in order:

| round | coercion | absent/ill-shaped in | plausible value out |
|---|---|---|---|
| 1 | argument recycling | length-2 `changed` vs 4 rows | `3 4 3 4`, silently |
| 1 | `as.integer(2020.7)` | a fractional `break_year` | `2020` |
| 1 | `pmin()` with no guard | a non-break row | a `strength` where the contract says none |
| 2 | `NA` class name → `NA` `changed` | a code absent from the class table | `NA` category, read as "could not be scanned" |
| 2 | a factor written to file | no RAT sidecar | integer codes read back as plain integers |
| **3** | **`as.integer(as.character(NaN))`** | **`crosstab(useNA=TRUE)`'s empty group** | **`0` — and `0` is a real level (`stable`) and a real strength** |

`as.integer(NaN)` is `NA`; `as.integer("NaN")` is **`0`, with no warning**
(measured, R 4.5). That is the round-3 instance and it had reached a committed
artifact: `data-raw/logs/benchmark_break_category/summary_strength.csv` published
`strength = 0` for 3,327,822 `stable`, 203,293 `unsettled`, 318,653
`stable_flicker` and 165,139,380 unscanned cells, against a documented contract of
`NA` off a clean switch. Two of the guards immediately below it —
`!anyNA(sus$strength)` and `!anyNA(end$strength)`, commented "a clean switch always
has one" — were made **unable to fire** by the same line, because after the
round-trip no strength can be `NA`.

**This was fixed and the artifact regenerated during the review** (`686158a`;
`summary_strength.csv` now reads `NA`, `rss_summary.csv` moved 8.88 → 8.82 GiB and
NEWS was updated to match). Reported here because the loop asked for the mechanism
and because two call sites of it survive — finding 1.

## Findings

- **[fragile] `data-raw/break_class_groups.R:500-501`** — the two remaining
  `as.integer(as.character(...))` coercions of `terra::crosstab()` output:
  ```r
  pc <- terra::crosstab(c(pid, category), long = TRUE, useNA = FALSE)
  pc$patch_id <- as.integer(as.character(pc$patch_id))
  pc$category <- as.integer(as.character(pc$category))
  ```
  Commit `686158a` fixed the identical idiom at three sites in this same file and
  in the benchmark, each with a comment naming the hazard explicitly. These two
  were not touched. They are safe **today only because `useNA = FALSE`** — a
  property of one argument, not of the code: flip it (or reach this with an
  unscannable pixel inside a change patch, which `na_year` in
  `tests/testthat/helper-break_class.R` proves is a reachable series shape) and
  every empty group becomes `patch_id 0` / `category 0`, and category 0 is
  `stable`, which is precisely the value the `for (k in c(0L, 4L))` guard 12 lines
  below exists to refuse. A fix that lands in some call sites and not others is
  the "one enforcement surface reads as complete" row in `code-check.md`. Use
  `as.integer(pc$patch_id)` / `as.integer(pc$category)` directly, as the other
  three now do.

- **[bug] `R/dft_break_category.R:56` (and `man/dft_break_category.Rd:46`)** — the
  `@details` claim is false:
  > "`NA` propagates: a pixel with an `NA` in any interior year cannot be scanned,
  > arrives with `status` `NA`, and is labelled `NA` rather than refused — **the
  > series in this package's own examples contains one.**"

  Measured on the series the `@examples` block actually runs (bundled
  `example_2017..2023.tif`, `dft_rast_classify(source = "io-lulc")`):
  ```
  rows with NA status in $summary: 0
  rows with NA category:           0
  tapply(ct$area, ct$category, sum)
    stable break_sustained break_endpoint unsettled stable_flicker
     61.17           10.98          10.40     12.65          27.91
  ```
  Every `NA`-evidence pixel in that series also has an `NA` transition, so no
  `NA`-status row reaches `$summary` and the example's `tapply` shows no `NA`
  group. The fixture that does contain the case is `na_year` in
  `tests/testthat/helper-break_class.R`, not the examples. This is exported
  documentation stating a fact about a runnable example that the example
  contradicts, on the one branch a reader would use it to reason about. Either
  point at the test fixture or drop the clause.

- **[fragile] `data-raw/read_change.R` is untracked** — `git ls-files
  --error-unmatch` reports it unknown to git, `git check-ignore` returns 1 (not
  ignored). `data-raw/break_class_groups.R:95` and
  `data-raw/benchmark_break_category_bulk.R:35` both `source()` it
  unconditionally, so if it does not get `git add`ed both scripts die on line 1 of
  their run for anyone but the author. Same class as `code-check.md`'s "a link to
  a repo-hosted artifact must be *tracked*, not merely present"; flagged because
  the extraction is uncommitted at the time of writing.

## (a) Literals in the changed files: contract or third-party fact

| literal | where | verdict |
|---|---|---|
| `c("stable","break_sustained","break_endpoint","unsettled","stable_flicker")` | `break_category_levels()` | **contract** — correctly the single hardcoded definition |
| `"v1"` | `break_rule_check()`, `rule` column, `drift_break_rule` tag | **contract** — correctly hardcoded |
| threshold `2` on `strength` | `break_category_code()` | **contract**, deliberately not an argument — documented |
| `n_flips` map `stable=0, break=1, flicker=2` | `dft_break_category.R:125` | **contract** — the aggregate spelling of `pmin(n_flips, 2)`, matches `dft_rast_break_class.R:254` |
| `from * 1000 + to` split (`%/%`, `%%`) | `break_category_scan()`, both `data-raw` `changed` closures | **contract**, but stated in four places; already pinned by the reconciliation |
| `2.5e6` chunk bound, `INT1U`, `COMPRESS=LZW` | `dft_rast_break_category.R:131-139` | **third-party fact**, measured on terra 1.9.34, recorded in NEWS |
| `pad <- ncol(stack) == 2L` | `dft_rast_break_category.R:120` | **third-party fact** — terra's `min(ncol, 13)` test chunk; measured, and the width 1/2/3 sweep pins it |
| `cat_labels` (four-level) | `data-raw/read_change.R` | **contract** — deliberately frozen to read the committed evidence |
| `chg_cats <- c("break_endpoint","break_sustained","unsettled")` | `break_class_groups.R:339` | duplicated subset of the levels; harmless (a mismatch fails loud in the set compare beneath it) |
| `yr_endpoint <- c(years[2], years[length(years)])` | `break_class_groups.R` | **derived**, and asserted against `dft_break_category()` rather than trusted — this is the right shape |
| `62.5 / 26.5 / 16.3 s`, `8.82 GiB`, `90,935`, `168,269`, `169,248,352` | NEWS 0.16.0 | **third-party facts**, all re-derived: they match `timings.csv`, `rss_summary.csv`, `summary_strength.csv` (53763+37172 = 90935) and `summary_category.csv`; `14651*11552 = 169,248,352` ✓ |
| `2,032.9 / 3,186.5 / 7,811.5 ha / 69%` | NEWS, roxygen, README, notes | re-derived from `bulk/summary_change.csv`: 909.35+1682.69+2032.93 = 4,624.97; +3,186.53 = 7,811.50; 7811.50/4624.97 = 1.689 ✓ |
| `539 rows` | NEWS | `wc -l summary_class_temporal.csv` = 540 incl. header ✓ |

Nothing in the set is "neither".

## (b) Guards added or changed — can each fire?

| guard | fires? |
|---|---|
| `break_category_code()` length check | yes — a length-2 `changed` against 4 rows errors (round 1's defect) |
| `break_rule_check()` | yes — `rule = "v2"`, pinned by test |
| unrecognised `status` | yes — pinned |
| `no_year` (break row, no `break_year`) | yes — pinned |
| `stray` (break_year off a non-break row) | yes — pinned; this is what makes "`strength` is NA off a clean switch" a contract |
| `unnamed` (NA class name) | yes — round 2's fix, pinned by the new `partial$from_class[...] <- NA` test |
| `!identical(names(breaks), need)` / `compareGeom` | yes — pinned |
| `overwrite` must be TRUE/FALSE, and `filename` clobber refusal | yes — pinned at `pad = FALSE`; I verified both **also** hold at `pad = TRUE` (ncol 2): `overwrite = FALSE` refuses with `[crop] file exists` and mtime does not move, `overwrite = TRUE` succeeds. The `isTRUE(overwrite) && identical(out_file, filename)` on both writes is correct. The test does not cover the pad branch; not a defect, but it is the branch a future edit will forget. |
| benchmark `!anyNA(sus$strength)` / `!anyNA(end$strength)` | **now** yes, after `686158a`; was vacuous before it |
| benchmark positive control (`bad$n_cells[1] + 1L`) | technically yes, but it is close to a test of `identical()` itself — it can only fail if `ct$n_cells[1]` is `NA`. The load-bearing controls are the `setequal` and the cell-for-cell compare above it. |
| `for (k in c(0L, 4L))` stable/stable_flicker inside a change patch | yes — `reshape()` creates `n_cells.0` / `n_cells.4` only when those categories occur, so the guard's `cn %in% names(wide)` is TRUE exactly when the defect is present |
| `stopifnot(identical(n0, nrow(patches)))` | yes |
| `is_sustained()` reachability comment in `disturbance_compare.R` | verified: `discriminates()` returns early on `NA` and `reach <- intersect(c(Y, Y+1L), break_years)` is non-empty and always within `years[-1]`, and it is the only caller. So `dft_break_strength()`'s refusals really are unreachable, and the `NA >= 2 → NA` behaviour change (the old closure returned `FALSE`) cannot be reached either. |

## (c) Where the five-level vocabulary is written down

| place | derived or duplicated |
|---|---|
| `break_category_levels()` | **source of truth** |
| `dft_break_category()` `@section` table, `@return` | duplicated (prose — unavoidable) |
| `dft_rast_break_category()` `@return`, `@param filename` | duplicated (prose) |
| `inst/cartography/drift_temporal.csv` `class_value` | duplicated — **but pinned**: `tests/testthat/test-dft_break_category.R:24` reads the shipped CSV via `system.file()` and asserts against `break_category_levels()`. Good. |
| `vignettes/articles/temporal-composition.Rmd:38, 121, 176` | duplicated literals, pinned only against the CSV by `stopifnot(identical(names(pal), c(...)))` — not against the package (`break_category_levels()` is `@noRd`). The CSV↔package link above closes the chain transitively. |
| `data-raw/break_class_groups.R` | derived via `break_category_levels()` at every label site; one duplicated subset (`chg_cats`) |
| `data-raw/benchmark_break_category_bulk.R` | now derived via the extracted `read_change()`; the inline four→five map it carried is gone |
| `data-raw/read_change.R` `cat_labels` | deliberately the retired four-level set |
| shipped CSVs (`summary_class_temporal.csv`, `summary_treeloss_temporal.csv`, `summary_groups.csv` header `pct_unsettled`, `bulk_grid_1km.csv`) | all checked: no `flicker` category value survives; `unsettled` / `stable_flicker` throughout |
| `inst/notes/temporal-qa-groups.md`, `inst/extdata/temporal-composition/README.md`, `CLAUDE.md`, `NEWS.md` | prose, all updated consistently |
| `inst/extdata/temporal-composition/bulk_window.csv` column `n_cells_flicker` | the one hold-out spelling. It is a *column name* in a provenance file nothing keys on by that string (`break_class_groups.R:710` writes it, the article reads `win$patch_*` and `art$reach`), so it is cosmetic — noted, not filed. |

Remaining `flicker` occurrences elsewhere are `status`-level vocabulary
(`dft_rast_break_class()`'s `stable`/`break`/`flicker`), which is unchanged and
correct.

## Other things checked, clean

- `data-raw/logs/benchmark_break_category/*.csv` reconcile with each other and
  with `data-raw/logs/break_class_groups/bulk/summary_change.csv`:
  `summary_category.csv` reproduces all five committed rows once the four-level
  `flicker` is split by `changed`; `summary_strength.csv` sums to the same
  90,935 / 168,269; category + NA totals = 4,108,972 + 165,139,380 =
  169,248,352 = `ncell` ✓.
- The RSS sampler watches `Sys.getpid()` via processx, so `$!`-on-a-subshell
  (#62) cannot arise; `withr::defer(envir = globalenv())` is correct (a top-level
  `on.exit()` never fires); the `< 0.5 GiB` magnitude assertion is a real
  wrong-process check.
- `pct_flicker → pct_unsettled` is a correct rename, not a relabel: the old
  `pct_*` were already shares *of changed area*, so the four-level `flicker`
  restricted to `changed == 1` is exactly `unsettled`
  (2032.93 / 4624.97 = 43.96% = the committed 44.0) ✓.
- `overstatement_factor` is `changed_ha / sustained_ha` (4625/909.35 = 5.09), not
  the pre-#62 `100 / pct_sustained` (5.076) — the corrected form.
- `fig_cat <- category` is equivalent to the retired two-pass `cat_fun()` +
  `fig_fun()` composition, including its `NA` set (`ch` NA ⊆ `ca` NA).
- `dft_break_strength()` survives an all-`NA` `break_year` column read from CSV as
  `logical` (the `read.csv` typing trap): the `!is.numeric && !all(is.na)` guard
  lets it through and `as.integer(NA)` is `NA_integer_`.
- `strip_copy()` leaves `x$raster` unmutated (pinned); no `.aux.xml` sidecar is
  written; the intermediate cleanup leaves exactly one survivor, and the
  `length(files)` guard against `paste0(character(0), ".aux.xml")` is present.
- `terra::app()` shape/dispatch handling: the `pad` condition is at `ncol == 2`
  (not the parent's 5), the closure refuses a bare vector, `steps` bounds the
  chunk. All three pinned by tests.

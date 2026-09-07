# Review round 2 — drift#72 (`dft_break_category()` / `dft_break_strength()` / `dft_rast_break_category()`)

Reviewed at `f5cb289` (the two commits `d04e68b` + `f5cb289` against `3d54378`), plus the
uncommitted working-tree change to `data-raw/break_class_groups.R` that landed mid-review.

## What was verified rather than read

- **All four test files green**: `test-dft_break_strength.R` 25 pass, `test-dft_break_category.R`
  58 pass, `test-dft_rast_break_category.R` 46 pass, `test-dft_rast_break_class.R` 0 fail / 0 error
  (`NOT_CRAN=true`, `test_file()` per file so nothing is skipped as CRAN).
- **Item G — the regenerated artifacts reproduce exactly.** `git archive HEAD` into a scratch tree,
  `Rscript data-raw/break_class_groups.R summarize` there, then `cmp` against the committed copies:
  `summary_groups.csv`, `summary_groups.md`, `summary_bulk_reconcile.csv`,
  `inst/extdata/temporal-composition/{summary_groups,summary_class_temporal,summary_treeloss_temporal}.csv`
  — **byte-identical, all six.** The migration is behaviour-preserving.
- **Item G, independently**: a key-mapped set comparison of `summary_class_temporal.csv` against
  `git show HEAD~2:` (old `flicker` → `unsettled`/`stable_flicker` by `changed`) gives 539 rows both
  sides, **0 keys added, 0 removed, 0 value differences**. The only real change is row order, which
  is `stats::aggregate()` sorting `"stable" < "stable_flicker"` where it used to sort
  `"flicker" < "stable"` — cosmetic, and evidence the script was genuinely re-run.
- **Item D — `read_change()` is correct and total on every committed file.** All five
  `summary_change.csv` files carry exactly `{stable, break_sustained, break_endpoint, flicker}` and
  `changed` reads back from `read.csv` as **integer** 0/1, so `as.integer(chg$changed[fl]) == 1L` is
  well-defined (no `TRUE`/`FALSE` string hazard). The map is a bijection and the collision guard is
  reachable but never fires. `article-bulk`'s `ref` was left on raw `read.csv` in the committed
  version, so the deferred stage was self-consistent as committed.
- **Item C — the `ncol == 2` pad condition is right, and the test that guards it is not vacuous.**
  Restored the bug in the scratch tree (`pad <- FALSE`) and re-ran: the "widths 1, 2 and 3" test
  goes **2 failed / 7 passed**, every other test still green. `app()`'s `ntest` is
  `min(ncol, 13)`, the closure returns 2 columns, so transposition can only fire at `ncol == 2`;
  widths 1 and 3 take the `nrow == ntest` branch correctly.
- **Item C — `filename` on the padded path.** Not covered by the suite (`res_cases` is 12 columns
  wide, so it only exercises the unpadded branch). Probed directly at w = 2 and w = 3 with
  `filename` supplied: file written, `sources(out)` is the caller's path, correct dims (1x2 / 1x3),
  correct values, **0 leftover `dft_break_category_*` files in `tempdir()`**, no stray `.aux.xml`.
  The cleanup cannot delete the file the returned raster points at on any of the four
  pad x filename combinations.
- **Item A — `break_category_code()` is total on reachable input.** Enumerated: `n_flips == 0` → 0
  regardless of `strength`/`changed`; `n_flips == 1` → 1/2 (and `n_flips == 1` implies non-NA
  `n_before`/`n_after` by construction in `break_class_scan()`); `n_flips >= 2` → 3/4 (and
  `changed` NA implies an endpoint NA, which implies `n_flips` NA, so the fall-through is
  unreachable at pixel grain); `n_flips` NA → NA. `many & changed` with `changed` NA is `FALSE`,
  not NA, so no silent slot. The new length guard closes the recycling hole.
- **Item B — the new guards close it.** Factor and character `break_year` now error by name,
  fractional and non-finite values error, all-NA logical (the `read.csv` shape) still passes. The
  only remaining silent-wrong-answer route is a `years` **superset**, which is documented explicitly
  in `@details` and is unreachable from the result path (`$years` is used).
- **`data-raw/disturbance_compare.R`'s `is_sustained()` migration is safe.** The new form returns
  `NA` for `NA` input and *errors* outside `years[-1]` where the old form returned `FALSE`, but its
  only caller (`discriminates()`) returns early on `NA` and intersects with `break_years` before
  calling, so no reachable input changes behaviour. The committed
  `data-raw/logs/disturbance_compare/` numbers are unaffected.
- **Item E — the rename is complete** in the committed tree. Every surviving `flicker` in `R/`,
  `tests/`, `inst/`, `man/`, `vignettes/` is either the unchanged `status` vocabulary
  (`stable`/`break`/`flicker`, which did not move), prose, or a fixture name. The article's
  `keys3`/`lab`/`pal` all key on `unsettled`, and `summary_treeloss_temporal.csv` supplies it.

## Findings

- **[bug]** `data-raw/break_class_groups.R` — **uncommitted working-tree change only** (`git status`
  shows ` M` on this file; not in either reviewed commit). The in-flight migration of the
  **per-group** stage (line ~851, `write.csv(ct, .../summary_change.csv)`) now labels rows with
  `break_category_levels()`, so a fresh group run writes a **five-level** `summary_change.csv`.
  `read_change()` (line 110) still validates against the four-level `cat_labels` (line 102) and
  refuses anything else. Confirmed by feeding a five-level frame through the current `read_change()`:

  ```
  Error: ... carries a category_label outside the four-level vocabulary: stable_flicker, unsettled
  ```

  So after re-running any group with the working-tree code, both `summarize` (three call sites) and
  `article-bulk` (`ref <- read_change(...)`) abort. Producer and reader are out of step. It needs a
  pass-through arm: accept `break_category_levels()` unchanged, and map only when the file is in the
  old vocabulary. Nothing committed is affected — the committed files are all four-level, which is
  why the scratch `summarize` run above still reproduced byte-for-byte.

- **[fragile]** `R/dft_rast_break_category.R:63` and its roxygen (line 8) — **`$years` is required
  and never used.** `grep -n "years" R/dft_rast_break_category.R` shows the only occurrences are the
  presence check, its error message, and the `@examples`. Strength at pixel grain is
  `pmin(n_before, n_after)` read straight off `$breaks`; `break_year` (`v[, 1L]`) is not read either.
  Two consequences:
  - the `@param x` line — "`$years` the series the endpoint threshold is relative to" — is a claim
    the code does not make true, and it is the sentence a reader would use to reason about the
    threshold;
  - a pre-0.16.0 result carrying `$raster` and `$breaks` is refused for no functional reason, and
    unlike `dft_break_category()` (whose message hands the caller an escape hatch — "pass `years`
    and the summary directly") this one offers none.

  Either drop `years` from the required set, or state that it is a provenance check that the result
  came from a current `dft_rast_break_class()`.

- **[fragile]** `R/dft_break_category.R:152` — `changed = s$from_class != s$to_class` is `NA`
  whenever a class code is absent from the class table, because `dft_rast_break_class()` fills
  `from_class`/`to_class` through `code_lookup[...]`, which returns `NA` for an unknown code.
  A `flicker` row then gets `category = NA` with a perfectly good non-`NA` `status`. Reproduced on
  the synthetic 4-class table with a code 9 pixel:

  ```
    from_class to_class  status category strength
  1      Trees    Trees  stable   stable       NA
  2       <NA>    Trees flicker     <NA>       NA      <- status is fine, category is NA
  3       <NA>     <NA> flicker     <NA>       NA
  ```

  `@details` states that `NA` category means "a pixel with an `NA` in any interior year cannot be
  scanned", so the two causes are indistinguishable downstream and this one fails toward a silent
  `NA` rather than the named error the neighbouring malformed-input cases get. Not reachable with
  the shipped `io-lulc` / `esa-worldcover` tables (they cover every code); reachable with a
  caller-supplied partial `class_table`. `dft_rast_break_category()` is unaffected — there `changed`
  comes from the transition code, which is `NA` only when `n_flips` already is.

- **[fragile]** `R/dft_rast_break_category.R:123`/`:134` — when `filename` is supplied, `set.cats()`
  runs **after** `terra::app()`/`terra::crop()` have written the file, so the RAT is only on the
  returned object. Measured: `terra::rast(f)` on the written file returns a non-factor two-layer
  raster (no `.aux.xml` written either). `@return` documents `category` as "a factor with ids 0:4",
  which holds for the object and not for the artifact the caller asked to be written — and the whole
  point of passing `filename` is that the grid is too big to keep, so the reopened copy is what gets
  used.

## Not findings (checked and cleared)

- `on.exit(if (length(files)) unlink(...))` — the `paste0(character(0), ".aux.xml")` hazard is
  guarded, and the guard is exercised (no `.aux.xml` appeared in the working directory under any
  probe).
- `strip_copy(trans)` does not mutate the caller (`coltab<-` deep-copies first); pinned by the
  existing test and re-confirmed.
- All-NA input: `dft_rast_break_class()` returns a 0-row summary and `dft_rast_break_category()`
  returns an all-NA raster with the full level set attached — no error, no `terra::freq()` trap.
- Zero-row summary through `dft_break_category()`: `rep(rule, nrow(s))` avoids the
  "`x$col <- value` errors on a 0-row frame" trap.
- `break_category_scan()` refuses a bare vector, so `app()` takes the vectorised path; pinned.
- `wopt = list(datatype = "INT1U")` round-trips `NA` as `NA` rather than 255; pinned.
- No `_pkgdown.yml` reference index exists, so the three new exports cannot fail
  `pkgdown::check_pkgdown()`.
- `NEWS.md` / `DESCRIPTION` are still at 0.15.0 while the error messages name "drift < 0.16.0" —
  that is the release step (`/gh-pr-merge`), not a defect in this diff.

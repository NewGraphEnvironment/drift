# Code review — round 1 (code) — drift#72 Phase 1 diff

Branch `72-break-category-expose-temporal-split`, staged tree exported with
`git checkout-index` and checked in isolation, so every measurement below is of
what this commit ships, not of the working tree (which also carries the
untracked `R/dft_rast_break_category.R` and an unstaged
`inst/cartography/drift_temporal.csv`).

**What was verified green** — `testthat::test_file()` on both new files
(25 + 51 PASS) and on the modified `test-dft_rast_break_class.R` (173 PASS);
both new topics' `@examples` executed clean; `pkgdown::check_pkgdown()` on the
staged tree reports no problems (the repo has no explicit `reference:` index, so
the two new exports are picked up automatically). The other three `R CMD check`
WARNINGs on the staged tarball (non-ASCII in `R/dft_stac_fetch.R`, two vignette
ones from `--no-build-vignettes`) are pre-existing and not from this diff.

## Findings

### 1. **[bug]** `R/dft_break_category.R:62` → `man/dft_break_category.Rd:96` — dangling Rd cross-reference; `R CMD check` goes to WARNING on this commit

`@seealso [dft_rast_break_category()] for the same rule at pixel grain;`
generates `\link[=dft_rast_break_category]{...}`. That topic does not exist in
this commit — `R/dft_rast_break_category.R` is **untracked** (`git status
--untracked-files=all` → `?? R/dft_rast_break_category.R`), and the accepted
tradeoffs put it two commits out.

Measured on the staged tarball (`drift_0.15.0.tar.gz`, R 4.5.2):

```
* checking Rd cross-references ... WARNING
Missing link(s) in Rd file 'dft_break_category.Rd':
  ‘dft_rast_break_category’
```

Confirmed against a minimal control package that the classification is a
WARNING, not a NOTE.

Why it matters rather than being cosmetic: `r-packages.md` makes
`devtools::check()` the release gate, and this commit takes it to WARNING for a
reason unrelated to anything it changed — which is exactly the noise that gets
scrolled past. There is **no R-CMD-check workflow in this repo** (only
`pkgdown.yaml` and `update-citation-cff.yaml`), so nothing in CI will catch or
un-catch it; it will simply sit in the built help and on the pkgdown reference
page as a dead link for as long as the intermediate commit is the tip.

The sibling mention at line 176 is inside a `@noRd` block and generates no Rd,
so it is safe to leave.

Fix: drop the clause until the raster function lands, or stage
`R/dft_rast_break_category.R` (+ its test and Rd) with this commit.

---

### 2. **[fragile]** `R/dft_break_category.R:183-194` `break_category_code()` — no length check; a divisor-length `changed` or `strength` recycles **silently** into a plausible wrong label

The function is `@noRd` and shared by design with the raster-grain caller, so
the length contract is the whole interface. Measured:

```r
break_category_code(c(2L,2L,2L,2L), rep(NA_integer_,4), c(TRUE,FALSE))
#> 3 4 3 4          <- no warning, no error
break_category_code(c(1L,1L,1L), 2L, c(TRUE,TRUE,TRUE))
#> 1 1 1            <- scalar strength recycled, no warning
```

A *non-multiple* length does warn (`longer object length is not a multiple…`),
so the only silent cases are exactly the two shapes a caller is most likely to
get wrong: a scalar, and a vector whose length divides the row count (a
per-year vector on a `length(years)`-row frame, say). The output is a
well-formed category vector, so nothing downstream can tell.

Both current callers pass matched lengths; this is about the second one landing
later. Three lines close it:

```r
stopifnot(length(strength) == length(n_flips), length(changed) == length(n_flips))
```

---

### 3. **[fragile]** `R/dft_break_strength.R:80-87` (via `R/dft_break_category.R:133`) — a `years` that is a superset of the real series passes every guard and silently changes every strength

The refusal is membership of each break year in `years[-1]`. That catches a
*different* series and a shifted one; it cannot catch a **longer** one, and a
longer one is what the stated consumer path invites. Measured, true series
`2017:2023`:

```r
dft_break_strength(2023L, 2017:2023)   #> 1   (a genuine endpoint break)
dft_break_strength(2023L, 2017:2030)   #> 6   (silently "sustained")
```

So a `$summary` written to CSV and re-read with the series typed by hand —
which is the documented reason `dft_break_category()` accepts a bare data frame
at all — republishes `break_endpoint` rows as `break_sustained` with nothing
said. `summary_pixels.csv` does not carry the series, so the number has to come
from a human.

Not a defect in the code so much as an undetectable input: worth saying so in
`@param years` ("the one input this function cannot validate — pass
`dft_rast_break_class()$years`, never a hand-typed range"), and worth
considering emitting `years` alongside any summary CSV the package's own
scripts write, so the migrated `data-raw/break_class_groups.R` reads it rather
than restating it.

---

### 4. **[fragile]** `tests/testthat/test-dft_break_category.R:145` — `expect_false(any(n == changed + 2791L))` cannot detect the pooling it names, and has a 77-cell false-alarm margin

Two separate problems with one line.

- **It cannot fire on the defect.** The pooling bug is a *reader* summing
  `unsettled` and `stable_flicker`; nothing in the code can produce a level
  carrying that sum. The four `expect_equal`s immediately above already pin
  every non-`stable` level exactly, so this assertion adds no discrimination —
  a proxy standing in for a property the neighbouring assertions already hold.

- **It can fire on correct data.** Measured on the bundled series:

  ```
           stable break_sustained  break_endpoint       unsettled  stable_flicker
             6117            1098            1040            1265            2791
  changed = 3403, forbidden value = 6194
  ```

  `stable` is 6117 against a forbidden 6194 — a margin of **77 cells, 0.02% of
  the 360,000-cell grid** — and `stable` is the one level no assertion pins, so
  it can move while the four pinned counts hold. The failure message would then
  point at a pooling bug that does not exist.

Also worth knowing before this test is copied: `tapply()` returns `NA` for an
empty factor level, `any(<vector with NA and no TRUE>)` is `NA`, and
`expect_false(NA)` **errors** rather than failing. Not reachable today (all
five levels are populated), reachable the moment a fixture leaves one empty —
and `as.vector(n[c(...)])` on line 136 has the same exposure.

---

### 5. **[fragile]** `R/dft_break_category.R:145` vs the `@return` claim at line 27 — `strength` is computed for every row, so "NA off a clean switch" is documented but not enforced

`strength <- dft_break_strength(s$break_year, years)` runs over all rows and is
assigned unconditionally. `dft_rast_break_class()` never emits a `break_year`
on a non-`break` row, so the package's own output is fine — but the function
explicitly accepts a foreign/hand-edited data frame, and on that path a
`flicker` row carrying a `break_year` publishes a non-`NA` `strength` beside a
`stable_flicker` category, contradicting its own documentation in a CSV.

One line makes the column match the claim:

```r
strength[!is.na(n_flips) & n_flips != 1L] <- NA_integer_
```

---

### 6. **[fragile]** `R/dft_break_strength.R:75` — `as.integer()` truncates rather than refusing, on a function whose stated contract is "refuse rather than return a wrong number"

Measured:

```r
dft_break_strength(2020.7, years)   #> 3     (truncated to 2020, accepted)
dft_break_strength("abc",  years)   #> NA    (R's coercion warning only)
```

The first is the truncation shape `code-check.md` catalogues (rtj#265): a
value that is not a calendar year at all is silently rounded into a valid one,
where every *other* malformed input to this function is a named error. The
second turns unparseable input into "this pixel had no break", which is the
direction that reads as success.

Neither is reachable from the package's own outputs — `terra::values()` and
`read.csv()` both give whole numbers — so this is low. If it is worth closing,
the shape check is one line before the coercion:

```r
if (is.numeric(break_year) && any(break_year != trunc(break_year), na.rm = TRUE))
  stop("`break_year` must be whole years.", call. = FALSE)
```

---

## Checked and clean

Things the brief asked to check hard that came back correct, with the probe
results, so a later round does not re-run them:

- **`break_category_code()` NA propagation.** `NA` in any of `n_flips`,
  `strength`, `changed` yields `NA` on the affected element and nothing else;
  `n_flips == 0` with `changed = NA` correctly still yields `0` (a stable pixel
  has equal endpoints by construction). `n_flips = 1` with `strength = NA`
  yields `NA` — and `dft_break_category()` catches that case earlier as a named
  error, so it cannot reach the output.
- **`dft_break_strength()` guards.** A factor `break_year` errors (level codes
  are not in `years[-1]`); `TRUE` errors; `NaN`/`Inf`/`NA` return `NA`; a
  character `"2020"` parses correctly; `integer(0)` returns `integer(0)`;
  `years` of length 2 works and `< 2` errors; unsorted, duplicated and
  `NA`-carrying `years` all error. Return type is integer on every path.
- **The `status` lookup at line 125.** Factor `status` works (via
  `as.character`); `""` errors with `unrecognised status value: `; `NA` status
  propagates to an `NA` category; an all-`NA` (logical) `status` column from a
  CSV round trip gives 10 `NA` categories and no error; a 0-row frame gives
  `named integer(0)` and no error.
- **The round-trip test in `test-dft_break_strength.R:11-15` is not vacuous.**
  `sum(!is.na(measured))` is 6 on the fixture (the six `switch_*` cases), so
  `expect_gt(..., 0L)` is doing real work, and the two sides are genuinely
  independent derivations (the `n_before`/`n_after` layers vs `match()` on
  `break_year`).
- **`is.list()` dispatch ordering.** `is.data.frame()` is tested first, so a
  tibble and a `grouped_df` both take the data-frame branch and come back with
  their class intact (measured: `grouped_df tbl_df tbl data.frame`, 10 rows).
  A `SpatRaster` is neither and hits the named error.
- **`$` vs `[[`.** The list reads use `[[` throughout; the data-frame reads use
  `$` but only for names the `setdiff(need, names(s))` guard has already proven
  present exactly, so partial matching cannot bite.
- **The `$years` addition.** Present and correct on both return paths,
  including the 0-row early return (verified with an all-`NA` series:
  `names()` is `raster breaks summary years`, `$years` is `2017…2023`,
  `nrow($summary)` is 0, and `dft_break_category()` on that result returns a
  0-row frame with all five levels, an integer `strength` and a character
  `rule`). It is the sorted vector — the unsorted-names test at
  `test-dft_rast_break_class.R:210` pins that.
- **Class-name collision.** `changed` is compared on class *names* at summary
  grain and on *codes* at raster grain; both shipped class tables
  (`io_lulc_v02.csv`, `esa_worldcover.csv`) have unique `class_name`s, so the
  two grains agree. Only a user-supplied `class_table` with duplicate names
  could split them.
- **No other consumer assumes a three-element result** — `grep` across `R/`,
  `vignettes/`, `data-raw/` and `tests/` finds only the one `expect_named()`,
  which the diff updates.

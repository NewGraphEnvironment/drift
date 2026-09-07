# Plan-agent design review — round 1 (#72)

Agent type `Plan` (read-only, no Write tool), so the findings arrived as reply text and are
transcribed here. Reviewed the proposed API against `R/dft_rast_break_class.R`,
`data-raw/break_class_groups.R`, `data-raw/disturbance_compare.R`,
`inst/cartography/drift_temporal.csv`, `vignettes/articles/temporal-composition.Rmd`,
`inst/extdata/temporal-composition/README.md` and the test files.

## Verdict

The split is right in spirit but wrong in its seams: `strength` belongs in `$summary`, the pixel
path belongs in its own `dft_rast_*` function, the level named `unsettled` collides with shipped
artefacts that say `flicker`, and the `rule` attribute is the one carrier that cannot survive the
repo's own provenance channel (CSV).

## 1. Measurement vs versioned label — right axis, one seam misplaced

`pmin(n_before, n_after)` is already a measured output of the scan
(`R/dft_rast_break_class.R:324-326`), and `$summary` already carries `break_year`, from which it is
exactly recoverable. The cheapest fix for "carry the number, not the threshold" is one line in
`dft_rast_break_class()`: add a `strength` column to `summary_tbl` (`:275-283`), consistent with
the documented no-threshold contract at `:58`.

Cost of `dft_break_strength()` as designed: it creates a second derivation of a number the scan
already computes. It is only *not* redundant for a caller holding a bare `break_year` with no
`$breaks` — which is real (`disturbance_compare.R:110-113` computes strength for published fire
years, not for scan output). Keep it, scope it in the docs as the inverse, and pin the round trip
in a test.

Note the roxygen calls this quantity **Confidence** (`R/dft_rast_break_class.R:36`) and the README
calls the threshold **sustained** (`inst/extdata/temporal-composition/README.md:26-27`). Three
words for one number if `strength` ships without reconciling them.

**Disposition:** two of three adopted. The `strength` column on `$summary` was **not** taken — the
acceptance criterion is met by the export, and the issue says to leave `$summary` alone. The
wording reconciliation and the round-trip test are in Phase 1 and Phase 3.

## 2. `grain` as an argument — no, split it

1. **Naming convention.** Every raster-returning export is `dft_rast_*`
   (`dft_rast_break`, `dft_rast_classify`, `dft_rast_consensus`, `dft_rast_summarize`,
   `dft_rast_transition`, `dft_rast_trend`); `dft_transition_vectors()` returns `sf` and drops the
   prefix. `dft_break_category(grain = "pixel")` returning a SpatRaster breaks a convention the
   package holds without exception.
2. **The input contract changes with the argument.** The summary path accepts a list or a data
   frame; the pixel path accepts only the list and needs `$raster` too. An argument that changes
   both the accepted input type and the returned type is two functions sharing a name.
3. **Nothing is shared but the map.** Summary is pure data-frame code; pixel is `app()` + pad/crop
   + datatype + cats + tempfile cleanup.

**Disposition:** adopted in full, including the unexported `break_category_code()` as the single
vocabulary.

## 3. Non-consecutive years — the identity holds, the meaning does not

Verified for `n = 2..8` and for `c(2017, 2020, 2023)`: `pmin(idx, n - idx)` with
`idx = match(break_year, years) - 1` reproduces `pmin(n_before, n_after)` exactly, and
`strength < 2` is exactly `break_year %in% c(years[2], years[n])` at every series length. So
`dft_break_strength()` and `temporal_category()`'s endpoint test are provably the same rule.

What breaks:

- **The unit is observations, not years.** On `2017, 2020, 2023` a break at 2020 gets
  `strength = 1`, though three calendar years flank it each side. `dft_rast_break_class()` accepts
  a gapped series today (`:138` checks only the four-digit shape, `:142` uniqueness).
- **Degenerate series.** `strength >= 2` requires `n >= 4`; on 2- or 3-year series
  `break_sustained` is structurally unreachable, and `n == 2` is supported
  (`test-dft_rast_break_class.R:249-257`).
- **`match()` failure modes.** `break_year == years[1]` gives `idx = 0` and `pmin(0, n) = 0` — the
  existing guard catches it (`disturbance_compare.R:112`, `i >= 1L`). A `break_year` not in `years`
  gives `NA` silently. `NA` break_year (every stable/flicker row) must return `NA_integer_`.
- **`$years` must be the sorted vector** (`R/dft_rast_break_class.R:145-147`) or every downstream
  `match()` is wrong for a caller who passed years out of order —
  `test-dft_rast_break_class.R:203` proves that is supported input.

**Disposition:** adopted in full.

## 4. terra hazards — the existing pad guard does not cover the new function

Measured on terra 1.9.34 in this repo:

```
ncol= 2  out nlyr= 2  layer a ok= FALSE
ncol= 3  out nlyr= 2  layer a ok= TRUE
```

A `fun` returning 2 columns on a raster exactly 2 cells wide is read as transposed and silently
scrambled. `dft_rast_break_class()` pads only at `ncol == 5L` (`:206`). The tests at
`test-dft_rast_break_class.R:300-321` sweep widths 4/5/6 — none reach it. Sweep 1/2/3.

Also mandatory:

- **Dispatch.** `if (!is.matrix(v)) stop("matrix chunks only")`, or `app()` runs the closure once
  per cell — 57x slower, values identical, invisible to a suite. Pin the closure directly as
  `test-dft_rast_break_class.R:259-279` does.
- **One pass, not three.** Today the pixel category costs `app(breaks)` + `app(codes)` for
  `changed` + `crosstab` (`break_class_groups.R:445-456`). Stack `c(res$breaks, codes)` and emit
  `(category, strength)` in a single `app()`.
- **Strip the factor before `app()`** with `deepcopy()` + `set.cats(NULL)` — one copy;
  `levels<- NULL` (as `break_class_groups.R:448` does) copies again.
- **`filename =` + `steps`.** Never omit `filename`. Set `steps` explicitly as the parent does,
  `ceiling(ncell / 2.5e6)` (`:226`); the chunk here is 5 input layers.
- **Cleanup.** Copy the parent's `files`/`on.exit` discipline verbatim (`:157-168`), including the
  `if (length(files))` guard — `paste0(character(0), ".aux.xml")` is `".aux.xml"` in `getwd()`, and
  there is a test for it (`test-dft_rast_break_class.R:350-367`).
- **Datatype `INT1U`** (0-4 and 1-3, both with `NA`). Test that `NA` round-trips from the written
  file as `NA`, not 255.
- **Factor ids 0:4** in the order `stable, break_sustained, break_endpoint, <unsettled>,
  stable_flicker` — `bulk_window.rds` and `temporal-composition.Rmd:121-123` key the colour table
  on those integers. Pin the id/label table in a test.
- **Add a `filename =` argument.** A 169M-cell 2-layer output landing in `tempdir()` is a footgun
  the parent gets away with only because callers immediately `crosstab` it.

**Disposition:** adopted in full. The 2-column trap was independently reproduced before adoption.

## 5. `rule = "v1"` — keep the concept, change the carrier

Worth it: the vocabulary has already changed once (4 levels in `cat_fun`
`break_class_groups.R:111`, 5 in `fig_fun` `:477-485`), so "which rule produced this label" is a
real question about real files.

An attribute is the wrong carrier and this repo has already decided so twice: `write.csv()` drops
it and every consumer here is a CSV; and the repo's own convention is *"`class_set` is a column,
not a footnote"* (`inst/extdata/temporal-composition/README.md:32`), with `rule` already a literal
column in a committed artefact (`break_class_groups.R:670-673`).

So: a **column** at summary grain, `terra::metags()` plus the level labels at pixel grain (mind the
`NULL`-empty-case trap). Drop `match.arg()` on a one-element vector — a typo check dressed as an
API; use an explicit `if (!identical(rule, "v1")) stop(...)`.

Do **not** additionally expose `min_strength = 2` as a knob: if the threshold is a free parameter,
`rule = "v1"` no longer identifies the labelling and the composition problem is re-created inside
the function. A caller wanting another threshold uses `strength` directly.

**Disposition:** adopted in full.

## 6. Ordering

The decisive constraint is the **vocabulary**, not committed-vs-gitignored.
`inst/cartography/drift_temporal.csv:5` uses `class_value = flicker` (label "Unsettled"); the
article asserts that exact set (`temporal-composition.Rmd:38-39`) and keys off it at `:121,142`;
the shipped CSVs carry `category = "flicker"` for both populations, disambiguated by `changed`;
`summary_groups.csv` has a `pct_flicker` column. Renaming touches the registry CSV, the article,
three shipped CSVs, `README.md:37-43` and `CLAUDE.md:118-120` — all at once, or the article's
`stopifnot` fails at build.

Recommended sequence: `$years` first (the two exact `expect_named()` at
`test-dft_rast_break_class.R:18` and `:90` will go red — expected, update in the same commit, and
an old result without `$years` must produce a named error rather than `match(x, NULL)`); then the
pure-R exports; then the **equivalence gate from committed CSVs**, pointing the summary path at
the four `summary_pixels.csv` (243/274/228/230 rows) and requiring it to reproduce
`summary_change.csv` and `summary_class_temporal.csv`; then the pixel export; and **leave
`cat_fun`/`fig_fun` alone until the BULK COGs are in hand** — `break_class_groups.R:96-99` states
the copy is deliberate and `article-bulk` refuses to proceed unless it reproduces
`summary_change.csv` cell for cell (`:456-470`), which needs the gitignored rasters. Migrating
before that check can run trades a verified evidence record for an unverified one.
`disturbance_compare.R:110-113` last, since `discriminates()` is quoted in prose at `:98-102` and
written into `summary_groups.csv`.

**Disposition:** adopted, with one correction. The reviewer's `git diff --exit-code` acceptance
does not hold once the vocabulary changes; the gate is instead cell counts identical after mapping
`flicker` -> `unsettled` / `stable_flicker` on `changed`.

## 7. Tests

The 4625/7811.5 case is reproducible from a shipped file:
`inst/extdata/temporal-composition/summary_class_temporal.csv`, `group == "bulk"` —
`sum(area_ha[changed]) = 4624.97`, `sum(area_ha[!changed & category == "flicker"]) = 3186.53`,
pooled `7811.50`, ratio `0.6890`. That file has no `status`/`break_year`, so it can only be an
expectation, never an input; the reviewer suggested shipping
`data-raw/logs/break_class_groups/bulk/summary_pixels.csv` (243 rows, ~12 KB) into
`inst/extdata/temporal-composition/` to make the test end-to-end.

Assert also:

- **Round-trip identity:** on `res_cases$breaks`, `dft_break_strength(break_year, years) ==
  pmin(n_before, n_after)` for every fixture row (`helper-break_class.R:24-40`) — the guard against
  the two derivations drifting.
- `switch_2018` / `switch_2023` -> `break_endpoint`, `switch_2020` -> `break_sustained`
  (`helper-break_class.R:28-33`).
- `flicker` -> `stable_flicker`, `flicker_diff` -> unsettled (`:34-35`). These two rows **are** the
  pooling bug, one pixel each.
- `na_year` -> `NA` category, not an error. `temporal_category()` `stop()`s on an `NA` status
  (`break_class_groups.R:275-277`) and the package's own documented example series contains one, so
  a straight port would abort on `dft_rast_break_class()`'s `@examples`.
- **Pixel == summary** on the bundled seven-year series (`test:369-396`), which already pins 3,403
  changed, 1,265 changed-flicker, 2,791 stable-flicker, 1,098 sustained, 776 + 264 endpoint.
- **Level set == registry** `class_value`, ids `0:4` in article order — the only thing stopping the
  vocabulary and the colours drifting apart.
- Widths 1/2/3 against an arithmetic reference; `n == 2` series.
- The regression guard is that the **pooled number is absent**: no single level carries 7811.50.

**Disposition:** adopted, except shipping a second copy of `summary_pixels.csv`. The bundled
seven-year series carries both populations at 1/100 scale, so the summary <-> pixel parity test is
already end-to-end on package data, and `summary_groups.csv` (which ships) carries the BULK
figures. A copied CSV would be one fact derived twice.

## 8. What the design or the issue gets wrong

- **"Four call sites, inconsistently" is wrong on the numbers.** They are four expressions of one
  rule and they are provably equal — the `summarize` stage reconciles aggregate to pixel grain on
  integer cell counts in all four groups with a positive and a structural control
  (`break_class_groups.R:337-376`), and `article-bulk` re-derives the pixel path and refuses to run
  unless it matches cell for cell (`:456-470`). The real cost is duplication plus a bespoke
  hand-written equality check. **The PR must not claim to fix wrong numbers.**
- **The pooling hazard is in the vocabulary, not in `cat_fun`.** `cat_fun`'s category 3 is honest
  (`n_flips >= 2`), and no shipped number pools it: `summary_change.csv` splits by `changed`
  (3186.53 vs 2032.93) and the article's `pct_flicker = 44` is already `2032.93 / 4624.97`. The
  hazard is that a four-level vocabulary lets a downstream reader drop the `changed` column and sum.
  Calling it "an error in `cat_fun`" sends the implementation to the wrong file.
- **`n_flips` has no home in the new API.** `break_class_groups.R:820-822` zonal-means it per patch
  and `summary_groups.csv` publishes `n_flips_sliver` / `n_flips_wider`. Say explicitly that
  `n_flips` stays on `$breaks` and is not part of the category's public surface.
- **Row order.** `$summary` is sorted by `n_cells` descending (`R/dft_rast_break_class.R:284`).
  Document that `dft_break_category()` preserves input row order.
- **Docs that go stale in the same PR:** `inst/extdata/temporal-composition/README.md:23-43`
  ("composed here, not by the package", "Five categories, not four") becomes false the moment the
  export exists, and `CLAUDE.md:118-120` names `cat_fun` as the thing to read before quoting a
  share.
- **Missing from the design entirely:** `filename =` on the pixel function; the `NA`-status
  contract; the `n < 4` degenerate case; the `$years`-absent (old RDS) error path; and whether
  `$breaks` gains a `strength` layer — **it should not**, since `pmin(n_before, n_after)` is one
  expression and a fifth layer costs a full-grid write on a 169M-cell run.

**Disposition:** all adopted into the plan and this findings record.

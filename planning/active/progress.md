# Progress — expose the temporal split as a function (#72)

## Session 2026-09-07

- CI scan clean on entry (last five runs green; pkgdown deployed 15:47Z).
- Plan-mode exploration: found **four** re-derivations, not the three the issue names —
  `cat_fun()` (twice), `temporal_category()`, `fig_fun()` and `is_sustained()`.
- Plan agent review returned 8 sections; transcribed to `review-round1.md` with a disposition
  line on each. Two findings not adopted, both with a stated reason.
- Independently reproduced the terra `app()` 2-column transpose trap before adopting the pad
  condition — the highest-risk item, and the existing sweep (widths 4/5/6) cannot reach it.
- User settled four API forks at the gate: split by grain, `dft_rast_` naming, `unsettled`
  vocabulary, `rule` as a column, `$years` only on `dft_rast_break_class()`.
- Created branch `72-break-category-expose-temporal-split` off main (verified 0 behind origin).
- Scaffolded PWF baseline with the approved phases.
- Next: Phase 1 — `dft_break_strength()`, `dft_break_category()`, `$years`.

### Phases 1-4 landed

- Phase 1-2 in `d04e68b`: three exports, `$years`, 998 tests passing (was ~900).
  Both guards proven by restoring the defect they exist for — the `ncol == 2` pad
  (2 failures without it) and the flicker pooling (9 failures across 4 tests).
- Reordered 3 before 2 in execution so every commit is green: the registry
  assertion in `test-dft_break_category.R` needs the `unsettled` rename, which is
  Phase 3's, so the cartography CSV landed with the exports.
- Phase 3 equivalence gate: `dft_break_category()`'s rollup reproduces the committed
  `summary_change.csv` **cell for cell in all four groups**, with the stage's positive
  and structural controls still firing. `summary_class_temporal.csv` — 539 rows in,
  539 out, key sets identical under the 4->5 level map, **zero rows whose `n_cells` or
  `area_ha` moved**. The committed per-group `summary_change.csv` files are not
  rewritten; `read_change()` maps them on read, and the map is a bijection with
  `(changed, four-level)`.
- Phase 4: `is_sustained()` -> `dft_break_strength() >= 2`, proven equivalent on every
  input `discriminates()` can reach, for series lengths 2-9. Its summarize stage
  re-run: outputs byte-identical.
- Code review round 1 (`review-code-round1.md`) found 6; 5 fixed, 1 self-resolved
  (a missing Rd link to a file that was untracked when the reviewer read the tree).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `expect_false(NA)` errors rather than fails, and `tapply()` returns `NA` for an empty factor level | Assert the property (endpoint equality) rather than an arithmetic identity over `tapply()` output |
| `inst/notes/temporal-qa-groups.md does not contain summary_groups.md verbatim` | Expected — the note embeds the generated tables byte for byte, so a renamed column means the note is rebuilt from the new `summary_groups.md`, not hand-edited |
| Two review agents given the same findings path; the first ran ~35 min and wrote after the second was spawned | One file per round is not enough when a round is re-spawned — rescued as `review-code-round1.md` before the collision |

### Phase 5-6 landed

**BULK scale test** (`data-raw/benchmark_break_category_bulk.R`, evidence in
`data-raw/logs/benchmark_break_category/`). 14651 x 11552 = 169,248,352 cells at 10 m,
97.7% NA outside the floodplain threads:

| stage | seconds |
|---|---|
| download (7 COGs, checksum-verified) | 5.4 |
| `dft_rast_break_class()` | 60.0 |
| `dft_rast_break_category()` | **26.6** |
| reconciliation crosstab | 16.4 |

Peak RSS **8.88 GiB** over 52 samples, sampler watching the R process's own pid.
`dft_rast_break_category()` reproduces the committed four-level `summary_change.csv`
cell for cell once mapped to five levels, with a positive control on the comparator;
90,935 sustained cells carry `strength >= 2` against 168,269 endpoint-only at exactly 1,
matching the committed counts.

**`article-bulk`** re-run through the export: reproduces `summary_change.csv` cell for
cell, same 21,701 patches, same selected patch 18141 at the same 0.299 min share, and the
1 km grid conserves 41,089.7 / 4,625.0 / 3,186.5 ha. `bulk_grid_1km.csv` regenerates
byte-identical; `bulk_window.rds` differs only in `meta` (run date and drift version) with
every raster's values, extent and varnames identical.

Two things the run caught that no fixture could:

- `on.exit()` at a script's top level never fires, so the first run's peak RSS was
  swallowed when a `stopifnot` aborted. `withr::defer(envir = globalenv())` fixed it, and
  it prints `Ran 1/1 deferred expressions` as the confirmation.
- `df[cond, ]` where `cond` holds an `NA` returns an all-`NA` ROW rather than dropping it,
  so `all(c(2, 3, NA) >= 2)` was `NA` and `stopifnot` failed on correct data. `%in%`
  instead of `==`, plus an explicit `!anyNA()`.

**Review round 2** found 4; 1 was already fixed mid-flight (`read_change()` refusing the
five-level vocabulary), 3 fixed and pinned: `$years` required but never read by the pixel
path (a pre-0.16.0 result is now accepted), an NA class name giving a silent NA category,
and the written file carrying no RAT while `@return` promised a factor (documented, since
matching the parent's no-sidecar posture is deliberate).

Lints in the changed R files: 0, against a baseline of 2 at `main`.

### The NaN coercion trap, found by reading the committed evidence

`summary_strength.csv` published `strength 0` for `stable`, `unsettled` and
`stable_flicker` — three categories that have no strength at all. Measured on R 4.5.2:

```
as.character(NaN)              "NaN"
as.integer("NaN")              0      <- no warning
as.numeric("NaN")              NaN
as.integer(NaN)                NA
as.integer(as.numeric("NaN"))  NA
```

`terra::crosstab(useNA = TRUE)` returns **numeric** columns with `NaN` for the group that
has no value, so the common idiom `as.integer(as.character(x))` turns "no value" into a
legitimate-looking zero, silently. Four sites were mine; two more are pre-existing under
`useNA = FALSE` and cannot reach it, so they are left alone.

The dangerous one was not the published CSV but `break_class_groups.R`'s article-bulk
self-check: `break_category_levels()[as.integer(as.character(ct$category)) + 1L]` maps a
`NaN` category to index 1, which is **`stable`**. A pixel that could not be scanned would
have been compared as a stable one. BULK carries no such pixel, so the check passed —
this is a latent defect a fixture would not have reached either, since it needs an
interior NA year *and* a known transition.

Found by reading a committed number and asking what it meant, not by review or by a test.

### `filename` with no way to overwrite

terra refuses to write over an existing file and its error names `overwrite=TRUE` as the
remedy — which the function did not accept, so the message pointed at something the caller
could not do. Added `overwrite = FALSE`, wired through both the padded and unpadded write
paths, and pinned.

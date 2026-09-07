# Review round 1 — article tables block in `data-raw/break_class_groups.R` (#66, phase 2)

Reviewer: code-review subagent. Date: 2026-09-06.
Scope: staged diff (`p2.diff`), the full script, the four committed
`summary_pixels.csv` / `summary_change.csv` inputs, and the three CSVs the block wrote.

Everything below was measured against the real data, not reasoned from the code.

## Findings

- **[fragile]** `data-raw/break_class_groups.R:334-342` (diff 102-110) — `agrees()` walks the
  **rollup's** rows, not the expected set. `idx <- match(<roll keys>, <chg keys>)` then
  `identical(as.integer(roll$n_cells), as.integer(chg$n_cells[idx]))` compares exactly
  `nrow(roll)` values. A row present in `summary_change.csv` but **absent** from `roll` is
  invisible: `anyNA(idx)` only fires the other way (a rollup category missing from `chg`), and
  the conservation check three lines up compares `per_class` against `summary_pixels.csv` —
  the *same* file the rollup came from — so it cannot see a discrepancy against
  `summary_change.csv` either. This is the CLAUDE.md pattern "the same iteration must walk the
  expected set rather than the subject's, or a missing member is invisible".

  Reachable in principle: the producer keeps `useNA = TRUE` in `terra::crosstab()` and only
  drops `is.na(ct$changed)`, so an NA-`category` row (`cat_labels[NA + 1L]` → `NA_character_`)
  would land in `summary_change.csv` with real cells and never be compared.

  Measured: all four groups have `nrow(roll) == nrow(chg) == 5`, `agrees()` TRUE, positive
  control FALSE, and `sum(pc$n_cells) == sum(chg$n_cells)` exactly (4,108,972 / 4,183,814 /
  1,600,176 / 6,937,760). **Nothing is wrong today** — this is a hole in the guard, not a
  defect in the output. One line closes it, inside `agrees()`:

  ```r
  if (length(idx) != nrow(chg)) stop("summary_change.csv carries rows the rollup does not")
  ```

- **[bug]** `inst/extdata/temporal-composition/README.md` — the stated range is wrong at the
  precision it is stated to, and the true value falls **outside** it. The README says excluding
  `Trees -> Water` "moves the sustained share by **-1.2 to +6.0 points**". Computed from the
  committed `summary_treeloss_temporal.csv`:

  | group | incl. Water | excl. Water | delta |
  |---|---|---|---|
  | bulk | 20.277804 | 20.875973 | +0.5982 |
  | necr | 32.060883 | 32.963190 | +0.9023 |
  | lnth | 15.920115 | 14.666487 | **-1.2536** |
  | kotl | 35.436074 | 41.435789 | +5.9997 |

  `round(-1.25362741, 1)` is **-1.3**, not -1.2, and -1.2536 is not inside `[-1.2, +6.0]`.
  This is a shipped `inst/` artifact (installed with the package and quoted by the article),
  so it is the release-note-number class: derive it from the artifact. Write `-1.3 to +6.0`,
  or `-1.25 to +6.00`.

- **[fragile]** `inst/extdata/temporal-composition/README.md` — documents an `article-bulk`
  stage and three files (`bulk_grid_1km.csv`, `bulk_window.csv`, `bulk_window.rds`) that do not
  exist, in present tense, in a file that ships inside the package. The script's argument
  validator (`break_class_groups.R:54`) accepts only `bulk|necr|lnth|kotl|summarize`, so the
  README's own instruction — "Regenerate with `Rscript data-raw/break_class_groups.R summarize`
  and then `... article-bulk`" — aborts with the usage `stop()`. `grep -n "article-bulk" ` on
  the script returns nothing. This is phase 3 of `task_plan.md`, so it resolves if phase 3
  lands in the same PR; it is only a problem if this commit is what ships. Worth a checkbox on
  phase 3 rather than a change now.

## Checked and clean (measured, not assumed)

The items the request asked to be checked hard, with what the measurement was:

1. **`aggregate(by = <data.frame>)` dropping NA groups.** Confirmed R behaviour — a 3-row frame
   with one NA in a `by` column aggregates to 2 rows, silently. **Not reachable here:**
   `from_class`/`to_class` have 0 NAs in all four `summary_pixels.csv` (243/229/227/273 rows),
   so `changed` (`from != to`) has none either, `group` is a literal, and `category` is
   guaranteed non-NA by `temporal_category()`'s own `stop()`. The conservation check
   (`sum(pc$n_cells)` vs a fresh re-read of the file) is a genuine tripwire for this and it
   passes with delta 0 in every group. `read.csv`'s `na.strings` cannot manufacture one either
   — the class vocabulary is `Bare Ground / Built Area / Clouds / Crops / Flooded Vegetation /
   Rangeland / Snow/Ice / Trees / Water`, none of which is `NA`.

2. **`ave(a$n_cells, pair, FUN = sum)` with `pair <- paste(from, to, sep = "\r")`.** `\r` is
   safe: no class name contains it, and the partition it induces is identical to the
   `(from, to)` partition. `ave()`'s failure mode with an NA group is real and silent (the NA
   rows keep their original value, so `pct_of_pair` would come out as a bogus `100`), but is
   unreachable — `aggregate()` upstream would already have dropped an NA-keyed row.
   `pct_of_pair` denominators are correct: `changed` is constant within a pair (from==to ⇒ all
   FALSE, from!=to ⇒ all TRUE), so the pair group is complete, and the `lapply` scopes it per
   group. No zero denominators (the row is in its own denominator).

3. **`agrees()` row alignment and the positive control.** Alignment is by `match()`, so row
   order is irrelevant — the `order()` on `a` cannot desynchronise it. Keys are unique in both
   objects. The positive control does fire: measured FALSE in all four groups. On a
   hypothetical 0-row `roll`, `bad$n_cells[1] <- bad$n_cells[1] + 1L` **errors** (`replacement
   has 1 row, data has 0`) rather than passing silently, and `aggregate()` would have errored
   first (`no rows to aggregate`) — so the empty case is loud, not green. The residual gap is
   finding 1 above.

4. **`temporal_category()`.** `anyNA(status)` is the first statement, before any
   `out[status == ...]` indexing, so the NA-subscript error is unreachable. The
   `%in%` NA hazard (`NA %in% c(2018, 2023)` is FALSE → would silently classify as sustained)
   is closed by the explicit `if (any(is.na(break_year[brk]))) stop(...)` immediately above it.
   Measured: 0 NA `break_year` on break rows, 0 non-break rows carrying a `break_year`, break
   years span 2018-2023 in every group. The final `anyNA(out)` catches an unknown status value.

5. **`yr_endpoint <- c(years[2], years[length(years)])`.** Correct, and more general than its
   comment claims. The identity is **positional** — `break_year` is the first year of the new
   class, so the 2nd element of the series leaves `n_before = 1` and the last leaves
   `n_after = 1`, both failing `pmin(...) >= 2` — so it holds for a non-consecutive series too.
   Independently verified end-to-end: the `%in% yr_endpoint` composition reproduces
   `summary_change.csv` (which is computed the *other* way, from `cat_fun()` on
   `pmin(n_before, n_after)` via `terra::crosstab`) cell-for-cell in all four groups. That is a
   real cross-check, not circular — two different computations off the same `res` object.

6. **`stopifnot(nrow(treeloss) == 2L * length(groups) * length(chg_cats))`.** Tight, and it
   cannot pass while a category is silently missing. `from_class == "Trees" & to_class != "Trees"`
   forces `changed == TRUE`, which excludes `stable` (status `stable` ⇔ `n_flips == 0` ⇔
   from==to), so the per-`(group, class_set)` maximum is 3 categories. 24 rows over 8 combos
   therefore forces exactly 3 each — a group short one category cannot be compensated by
   another group having four. Measured 24. It *would* fire on a group that legitimately had
   zero tree loss in one category, but that is a real anomaly worth aborting on.

7. **`dir.create(art_dir, recursive = TRUE, showWarnings = FALSE)`.** No silent path: the
   suppressed warning is followed by `write.csv()`, which errors on an unwritable path. All
   five guards run before the first write, so a failing run leaves no CSV behind.

8. **Git churn / determinism.** Re-ran the whole block against the committed inputs and wrote
   to a temp directory: `cmp` reports the regenerated `summary_class_temporal.csv`
   **byte-identical** to the committed one. `pct_of_pair` at `write.csv`'s 15 significant
   digits comes from deterministic IEEE arithmetic on integer inputs, so it is reproducible;
   nothing reads these files back, so 15-vs-17-digit round-trip fidelity is not in play.
   `git status` confirms the three pre-existing `summarize` outputs (`summary_groups.csv/.md`,
   `summary_bulk_reconcile.csv`) are unmodified — only the logs README changed.

9. **`order()` locale collation.** `order()` on character does use locale collation (`method =
   "auto"` picks `shell`, not `radix`, for character). Measured under both `C` and
   `en_US.UTF-8`: the nine class names and the four category labels sort **identically** in
   both, including `Snow/Ice` (the only name with punctuation). So the committed byte order is
   locale-invariant for the current vocabulary. Latent only if a class name is ever added
   whose ordering depends on punctuation or case placement.

Other things checked with nothing to report: `$` partial matching (`chg$category` vs the longer
sibling `category_label` — exact match wins, and every lookup has an exact column);
`per_class$area` renamed to `area_ha` matches the file's units (cells × 0.01 ha, verified);
`as.integer()` on cell counts is nowhere near `.Machine$integer.max` (max 6.94M);
`out[...]` column subset names all exist in the `out` frame; `pct_of_pair` (cell share) and
`pct_of_set` (area share) are numerically equivalent because cell size is constant within a
group, so the two column names do not carry different populations;
`pkgload::load_all(".")` is unconditional at the top of the script, per the `data-raw`
convention.

/Users/airvine/Projects/repo/drift/planning/active/review-round1.md

# Review round 3 — `data-raw/disturbance_compare.R`, `data-raw/disturbance_compare-run.sh`

Reviewed the files on disk (788 / 41 lines) plus the diff at
`cc_diff3.txt`. Round 2's five fixes all verified present and doing what they
claim. Four of the five hold. **The class is NOT closed** — the mechanism recurs one
axis over inside R2-2 and R2-5, and there is one new crash path.

Everything below was measured, not reasoned. Measurements are in
"Probes run" at the bottom.

---

## Findings

### R3-1 — **[bug]** `disturbance_compare.R:241,247,270,300,306` — a 0-row per-group CSV aborts `summarize` with an opaque error

`event_rows()` (line 177) and `offset_rows()` (line 709) each carry an explicit
empty-input guard that returns a **0-row** data frame. `write.csv()` on that writes a
header-only file. `read.csv()` reads it back as a 0-row frame — and then the summarize
stage does

```r
e <- rd(g, "summary_events.csv"); e$group <- g; e         # line 241
o <- rd(g, "summary_break_offset.csv"); o$group <- g; o   # line 270
x <- rd(g, "summary_flicker_strata.csv"); x$group <- g; x # line 300
```

Measured on R 4.5:

```
d <- data.frame(source=character(0)); d$group <- "g"
#> Error in `$<-.data.frame`: replacement has 1 row, data has 0
```

Also confirmed through the full write → read round trip (header-only file, `nrow 0`,
same error).

The producer is guarded and the consumer is not, so the emptiness branch that exists to
keep a 12-minute run alive is exactly the branch that kills the assembly step. It is
reachable whenever a group has **no** fire-tagged *and* no harvest-tagged published
patches (`summary_events.csv`), or no tagged patch in either source with a modal break
year (`summary_break_offset.csv`). The author wrote both guards, so both cases are
considered reachable; `summary_flicker_strata.csv` is always 12 rows and is safe today
only by accident of `4 strata x 3 pops`.

Fix: `if (nrow(e)) e$group <- g else e <- cbind(e, group = character(0))`, or build the
column with `data.frame(e, group = rep(g, nrow(e)))`, which is 0-row-safe.

---

### R3-2 — **[bug, latent]** `disturbance_compare.R:679-681, 753-754, 756-758` — `area_ha_eval` DOES create a third population, and the guard's own comment asserts it cannot

Direct answer to Q1a: **yes.**

```r
pub_area <- stats::aggregate(area_ha ~ patch_id, sf::st_drop_geometry(published), sum)
```

`aggregate.formula` defaults to `na.action = na.omit`, which deletes the model-frame row
**before** `FUN` runs. Measured:

```
p <- data.frame(patch_id=c(1,2,3), area_ha=c(1,NA,3))
aggregate(area_ha ~ patch_id, p, sum)
#>   patch_id area_ha
#> 1        1       1
#> 2        3       3          <- patch 2 is GONE, not NA
```

So a published row with `NA area_ha` (or `NA patch_id`) yields **no** `pub_area` row, and
after the `all.x` merge that patch has `tag_evaluated == TRUE` and
`is.na(area_ha_eval) == TRUE`. That is a third state, and three things then go wrong at
once, all silently:

- Phase 3's `k` (line 753) filters `!is.na(ev_patch$area_ha_eval)`, so the patch is
  dropped from **every** population and from `n_patches` — a filter that is *not* the same
  predicate as `tag_evaluated` and is nowhere counted.
- `n_trimmed` (line 682) excludes it too (`!is.na(area_ha_eval)`), so it is not
  `patches_trimmed_by_clip` either.
- The comment at lines 756-758 states *"Every population is gated on `tag_evaluated`, so it
  is non-NA throughout"* — an invariant asserted in prose and enforced nowhere.

This is the same `aggregate` trap the file already guards **twenty lines earlier**:
`flags` at line 655 passes `na.action = stats::na.pass` with a six-line comment
explaining exactly this. Two aggregates over the same `published` frame, one guarded and
one not.

Note `na.action = na.pass` is *not* the fix here — `sum(c(1, NA))` is `NA`, so the third
state persists under a different cause. The fix is to make it loud:

```r
stopifnot(!any(ev_patch$tag_evaluated & is.na(ev_patch$area_ha_eval)))
```

or add `tag_evaluated_without_eval_area` as a `join_audit.csv` row, which is the pattern
R2-6 used for the equivalent `in_fire == 1 & is.na(fire_year)` case.

Latent, not live: the four published layers currently carry non-NA `area_ha`. So is
R2-5's own `flags` guard, which was added anyway.

---

### R3-3 — **[bug]** `disturbance_compare.R:638-639, 715-719, 753-762` — R2-5 corrected the **weight** but not the **measurand**; `flicker_frac` and `break_frac` are still measured over the *unclipped* footprint

`pid_r` (line 555) is rasterized from `pat_sv`, the **sieved UNCLIPPED** patches. Every
cell count that feeds `n_valid / n_flicker / n_break` therefore covers the whole
unclipped patch, including the part outside the sub-basin. `flicker_frac` and
`break_frac` are ratios over that footprint.

R2-5's fix changed the Phase 3 *weight* from `area_ha` to `area_ha_eval` on the stated
grounds that "weighting by the full unclipped `area_ha` would give such a patch more
weight than the geometry the tag actually saw". Correct — and the identical argument
applies to the quantity being weighted. For a trimmed patch,
`weighted.mean(flicker_frac, area_ha_eval)` multiplies the clipped area by a flicker
fraction computed over the unclipped area. The result is neither the clipped statistic
nor the unclipped one.

The reach is the same population R2-5 was written for (`n_trimmed`,
`patches_trimmed_by_clip`), so the magnitude is whatever that count turns out to be — and
`n_trimmed` was added by R2-5 precisely because nobody knew it.

Two honest resolutions:
- rasterize `pat_cl` for the cell statistics as well (rejected by the header's fact 1 —
  it would drop sub-cell fragments and manufacture Phase 3's hypothesis), or
- keep the unclipped measurand and say so in the column name / note, and report
  `patches_trimmed_by_clip` beside the Phase 3 table so a reader can bound the effect.

Whichever, the current state is a hybrid nothing in the CSV names.

---

### R3-4 — **[bug]** `disturbance_compare.R:721-725 vs 758-761` — `break_frac_area_wtd` is published in two CSVs with two different weights, and one comment cross-quotes the other

`summary_break_offset.csv` (line 719):

```r
break_frac_sum = q$break_frac * q$area_ha      # UNCLIPPED weight
a$break_frac_area_wtd <- round(a$break_frac_sum / a$area_ha, 3)
```

`summary_flicker_strata.csv` (line 761):

```r
break_frac_area_wtd = round(weighted.mean(ev_patch$break_frac[k],
                                          ev_patch$area_ha_eval[k]), 3)   # CLIPPED weight
```

Same column name, same nominal quantity, two different weights. R2-5 moved Phase 3 to
`area_ha_eval` and left Phase 2 on `area_ha`.

The tell that this is already being read as one number: the Phase 2 header comment at
line 703 says *"the area-weighted `break_frac` for the tagged populations is 0.72-0.93,
**reported by Phase 3**"* — Phase 2's documentation quotes Phase 3's value to describe
Phase 2's own population. Both tables land in the same note.

Either weight Phase 2 by `area_ha_eval` too (it is on `ev_patch`, so it is a one-token
change) or rename one of the two columns.

---

### R3-5 — **[bug]** `disturbance_compare.R:287-302` — `pct_lag01_of_tagged` mixes populations: `n_tagged` counts **published rows**, `n_lag01` counts **`pat_sv` patches**

Direct answer to Q2: **no, they are not the same population**, though they coincide when
the reconciliation is exact.

- `n_tagged = sum(e$n_patches[...])` where `e` is `summary_events.csv`, produced by
  `event_rows(published, ...)` — one count per **row of the published layer**, per year.
- `n_with_break` / `n_lag01` come from `summary_break_offset.csv`, produced by
  `offset_rows()` over `ev_patch` — one count per **`pat_sv` patch** (sieved, unclipped),
  after the `patch_id` merge has collapsed fragments.

They differ on two axes the script itself measures and then does not consult:

1. **Splitting.** A patch straddling a sub-basin boundary is two published rows and one
   `pat_sv` patch, so it adds 2 to the denominator and at most 1 to the numerator. The
   file collapses fragments defensively for the tags (lines 647-660, "a straddling patch
   would repeat it") and does **not** collapse them in `event_rows`. `rows_split_by_clip`
   is 0 today and is written to `group_meta.csv`, which the `agree` block never reads.
2. **Reproduction failure.** `published_patch_ids_unmatched` (line 592) counts published
   rows with no `pat_sv` patch. Those are in the denominator and cannot reach the
   numerator. `reconciled` lives in `group_meta.csv`; `agree` does not read it, so
   `pct_lag01_of_tagged` is published at face value whether or not the reproduction closed.

The bias is one-directional (`n_with_break <= n_tagged` always, so the rate is never
>100% and never looks wrong). Fix: read `rows_split_by_clip` and
`published_patch_ids_unmatched` in the `agree` block and either refuse or publish them
beside the rate; or derive `n_tagged` from `summary_patch_join.csv`
(`tag_evaluated & flag == 1 & !is.na(year)`), which is the numerator's own population.

---

### R3-6 — **[bug]** `disturbance_compare.R:303-332` — R2-2's stale-artifact fix landed on the per-group stage only; `summarize` writes six files at `log_root` with no clear and no completion marker

R2-2 added `file.remove(Sys.glob(file.path(out_dir, "*.csv")))` (line 355) and moved the
gate to `group_meta.csv`. Confirmed correct, and confirmed it **cannot** reach the
summarize outputs — those live one directory up (`data-raw/logs/disturbance_compare/`,
verified on disk: `summary_*_groups.csv`, `summary_groups.csv/.md`), and the glob is
non-recursive. Q1c: no bad interaction.

But the summarize stage now has the exact defect R2-2 removed from the per-group stage.
It writes `summary_reconcile_groups.csv`, `summary_events_groups.csv`,
`summary_agreement_groups.csv`, `summary_flicker_groups.csv`, `summary_groups.md` and
`summary_groups.csv` with:

- no clearing beforehand, and
- no marker file whose presence means "all six came from one run".

An error during construction — R3-1's 0-row crash is the concrete one, and it fires at
line 241 or 270, *before* any write — leaves all six files from a **previous** summarize
on disk while the per-group CSVs beneath them have just been regenerated. Nothing
downstream can tell. `message("SUMMARIZE DONE")` is in-band only; nothing consumes it
(the shell wrapper never runs `summarize`).

Fix: mirror the per-group pattern — remove the six paths at the top of the block, and
write `summary_groups.csv` last so its presence is the marker.

---

### R3-7 — **[minor]** `disturbance_compare.R:355` — `file.remove()`'s return value is discarded on a guard whose whole purpose is preventing mixed-run artifacts

```r
invisible(file.remove(Sys.glob(file.path(out_dir, "*.csv"))))
```

`file.remove()` returns a logical vector and **warns** rather than erroring on a failure
(permissions, a file open elsewhere). A failed removal leaves the stale CSV in place, the
run overwrites some of its siblings, and the `group_meta.csv` invariant — "meta present
=> every CSV beside it came from the same run" — is silently false. The warning is one
line in a `run.log` the wrapper only greps for `error|halted`.

```r
rm_ok <- file.remove(Sys.glob(file.path(out_dir, "*.csv")))
if (length(rm_ok) && !all(rm_ok)) stop("could not clear stale CSVs in ", out_dir)
```

---

### R3-8 — **[minor]** `disturbance_compare.R:775-782` — R2-3 guarded the read side of the NULL-drop trap and left the write side open

R2-3 correctly replaced `read.csv(...)$n_fire_events_disc` with `gm[["..."]]` plus a
`stopifnot`, on the grounds that *"`$` on a data.frame returns NULL for a missing column
and `data.frame()` silently DROPS a NULL argument"*.

The `meta` construction is the same `data.frame()` and takes three values straight off a
parsed JSON document:

```r
published_drift_version = props[["nge:drift_version"]],
running_drift_version   = ...,
published_gross_loss_ha = props[["gross_loss_ha"]],
```

`props[["missing"]]` is `NULL`, and `data.frame()` drops it. A catalogue rename of
`nge:drift_version` or `gross_loss_ha` therefore ships a `group_meta.csv` **quietly
missing that column**, with no error, and the run reports `ALL STAGES DONE`. The two
columns `summarize` reads are now protected; the ones it does not read are the evidence
record.

One line above the `data.frame()` closes it:

```r
stopifnot(all(c("nge:drift_version", "gross_loss_ha") %in% names(props)))
```

---

### R3-9 — **[minor]** `disturbance_compare.R:591-592` — `published_patch_ids_matched` / `_unmatched` count **rows**, not patch ids

```r
sum(published$patch_id %in% pat_sv$patch_id)
sum(!published$patch_id %in% pat_sv$patch_id)
```

These sum over `nrow(published)`, so a straddling patch contributes twice under a metric
name that says "patch_ids". Identical to `rows_split_by_clip` in cause and zero today,
but this is the row R3-5 would want to consult, and it is labelled as a count of ids.
`length(unique(...))` on both, or rename to `published_rows_*`.

---

### R3-10 — **[minor]** `disturbance_compare.R:741, 756` — the `ge_0.5_ha` stratum thresholds on the **unclipped** area while the row reports the **clipped** area

```r
ge_0.5_ha = ev_patch$area_ha >= 0.5      # unclipped
area_ha   = round(sum(ev_patch$area_ha_eval[k]), 1)   # clipped
```

A patch of 0.6 ha unclipped, trimmed to 0.3 ha, is in the `>= 0.5 ha` stratum and
contributes 0.3 ha to the stratum's reported area. Small, one-directional, and the same
axis as R3-3 — listed for the enumeration rather than as an independent defect.

---

## Direct answers to the questions asked

| question | answer |
|---|---|
| Does `area_ha_eval` create a third population (NA patches)? | **Yes** — R3-2. `tag_evaluated & is.na(area_ha_eval)` is reachable via `aggregate`'s `na.omit`, is silently excluded from all three Phase 3 populations, is not counted anywhere, and is asserted impossible in a comment. |
| Is `weighted.mean` safe when `area_ha_eval` sums fragments? | **The summation is correct** — `sum` over a patch's published fragments is exactly the evaluated area, and it is the right weight. Three checks: (a) `break_frac` is `NA` on exactly the same condition as `flicker_frac` (`n_valid > 0`, lines 638-639), so the `!is.na(flicker_frac)` gate makes both non-NA and the default `na.rm = FALSE` is safe; (b) `k` contains no `NA` (every input is `%in%`, `>=` on a non-NA column, or `!is.na`); (c) all-zero weights give `NaN` not an error (measured), unreachable since a polygon's area is > 0. **The unsafe part is not the mean, it is the measurand** — R3-3. |
| Does `file.remove(Sys.glob(...))` touch the summarize CSVs? | **No.** Verified on disk: summarize writes to `data-raw/logs/disturbance_compare/`, the glob is `data-raw/logs/disturbance_compare/<group>/*.csv`, and `Sys.glob` is not recursive. The related defect is the *absence* of the same protection at `log_root` — R3-6. |
| Any path where `group_meta.csv` is written but an earlier CSV was not? | **No.** The write order is events(426) → reconcile(520) → class_compare(541) → patch_join(686) → join_audit(698) → break_offset(729) → flicker_strata(765) → **meta(783)** → timings(786). No branch skips a write, and `write.csv` errors rather than returning a status. `timings.csv` is the only file after meta, and `summarize` does not read it (the shell wrapper does, gated on `ALL STAGES DONE`, which is after it). The gate holds — but see R3-7: it holds only if the clear at line 355 succeeded, which is unchecked. |
| Any path where `n_trimmed` is undefined at the deferred `audit` write? | **No.** Lines 581 → 682 → 693 → 698 are straight-line with no branch, and `sum()` over an empty logical is `0L`. R2-6's deferred write is sound. |
| Is the class closed? | **No.** R3-3, R3-4, R3-5 and R3-10 are the same mechanism one axis over, inside R2-5's and R2-2's own fixes. |

---

## Enumeration: every derived column, its population and its precision

Requested as the terminating evidence. **P** = population, **prec** = precision. Rows
marked ⚠ are where the label and the population disagree.

### `summary_events.csv` — `event_rows(published, ...)`

| column | population | precision |
|---|---|---|
| `year` | published rows, flag==1, non-NA year | exact |
| `n_patches` | **published ROWS** (clipped; a split patch counts per fragment) ⚠ name says patches | exact int |
| `area_ha` | sum of published `area_ha` = **clipped, geometry-recomputed** | round 1 dp |
| `n_events` | distinct `fire_number` **within one year**; NA for harvest | exact |
| `discriminating` | `discriminates(year)` | — |

### `group_meta.csv`

| column | population | precision |
|---|---|---|
| `reconciled` | `pat_cl` (clipped) vs `published`, **RAW** values | raw — authoritative, read back by summarize (R2-4) |
| `n_fire_events_disc` | distinct `fire_number` over published rows, discriminating years | exact |
| `patches_dropped_by_clip` | `pat_sv` ids absent from `pat_cl` | exact |
| `rows_split_by_clip` | `nrow(pat_cl) - n_distinct(pat_cl$patch_id)` | exact |
| `join_zero_cell_patches` | `pat_sv` ids with no rasterized cell | exact |
| `published_gross_loss_ha` | item property, **not recomputed** ⚠ silently droppable (R3-8) | as published |
| `discriminating_full/partial` | derived from `years` | — |

### `summary_reconcile.csv`

| column | population | precision |
|---|---|---|
| `n_patches`, `area_ha` | four populations, one per `step` — labelled, correct | round 1 dp |
| `d_ha` | `diff()` of the **already-rounded** column | round 1 dp of rounded — labelled; summarize's `sieve_ha`/`clip_ha` recompute the same way, so they agree |

### `summary_class_compare.csv`

| column | population | precision |
|---|---|---|
| `n_repro`, `ha_repro` | `pat_cl` — clipped, area from post-intersection `st_area` | raw |
| `n_pub`, `ha_pub` | published rows | raw |
| `d_n`, `d_ha` | difference | `d_ha` round 2 dp |

### `join_audit.csv`

| column | population | precision |
|---|---|---|
| `patches_in`, `patches_with_cells`, `patches_zero_cells`, `cells_total` | `pat_sv` — **unclipped** | exact |
| `area_from_cells_ha`, `area_from_geometry_ha` | `pat_sv` — unclipped | round 2 dp |
| `max_abs_patch_ha_delta` | `pat_sv` ∩ cells | `signif 3` |
| `published_patch_ids_matched/unmatched` | **published ROWS** ⚠ (R3-9) | exact |
| `patches_not_tag_evaluated` | `pat_sv` ids absent from published | exact |
| `patches_trimmed_by_clip` | `pat_sv`, `tag_evaluated`, **non-NA `area_ha_eval`** ⚠ (R3-2) | exact |
| `fire_flag_without_year`, `harvest_flag_without_year` | published ROWS | exact |

### `summary_patch_join.csv` (`ev_patch`) — population is `pat_sv`, sieved **unclipped**

| column | population | precision |
|---|---|---|
| `area_ha` | **unclipped** patch, `st_area` pre-intersection | raw |
| `area_ha_eval` | **clipped**, summed over published fragments; NA when `!tag_evaluated` **or** when `published$area_ha` is NA ⚠ (R3-2) | raw |
| `n_valid`, `n_na`, `n_flicker`, `n_break` | cells of the **unclipped** footprint | exact |
| `flicker_frac`, `break_frac` | fraction over the **unclipped** footprint ⚠ (R3-3) | raw |
| `break_year_modal` | modal break year among **break cells of the unclipped patch**; no minimum break fraction (documented at line 623) | exact |
| `in_fire`, `in_harvest` | `any()` collapsed over published fragments, NA→0 after `tag_evaluated` | 0/1 |
| `fire_year`, `fire_number`, `harvest_start_year_calendar` | **largest published fragment's** value | as published |
| `tag_evaluated` | `patch_id %in% published$patch_id` | logical |

### `summary_break_offset.csv`

| column | population | precision |
|---|---|---|
| `n_patches` | `pat_sv` patches: `tag_evaluated & flag==1 & !is.na(year) & !is.na(break_year_modal)` | exact |
| `area_ha` | sum of **UNCLIPPED** `area_ha` ⚠ same name, different population from every other `area_ha` | round 1 dp |
| `break_frac_area_wtd` | weighted by **UNCLIPPED** area ⚠ (R3-4) | round 3 dp |
| `offset` | `break_year_modal - disturbance_year`, raw integers (crosstab returns numeric, not factor — measured) | exact |

### `summary_flicker_strata.csv`

| column | population | precision |
|---|---|---|
| `n_patches` | `pat_sv`, `tag_evaluated`, non-NA `flicker_frac` **and** non-NA `area_ha_eval` ⚠ second gate is not `tag_evaluated` (R3-2) | exact |
| `area_ha` | sum of **CLIPPED** `area_ha_eval` ⚠ third meaning of this column name | round 1 dp |
| `flicker_frac_area_wtd`, `break_frac_area_wtd` | measurand **unclipped**, weight **clipped** ⚠ (R3-3, R3-4) | round 3 dp |
| stratum `ge_0.5_ha` | threshold on **unclipped** area ⚠ (R3-10) | — |

### summarize outputs

| column | population | precision |
|---|---|---|
| `recon$*_ha`, `sieve_ha`, `clip_ha` | read back from the 1-dp CSV, differenced there | 1 dp of 1 dp — deliberate (R2-4) |
| `reproduced` | **raw**, read back from `group_meta.csv` | raw — R2-4 fix confirmed |
| `n_classes_differ`, `max_abs_d_ha` | `summary_class_compare.csv`, all classes | 2 dp |
| `ev$fire_patches_*`, `harv_patches_*` | published ROWS, discriminating years | exact |
| `ev$fire_ha_disc`, `harv_ha_disc` | **clipped published** area | 1 dp |
| `ev$fire_events_disc` | distinct fires, from meta (R2-3 fix confirmed) | exact |
| `agree$n_tagged` | **published ROWS** ⚠ (R3-5) | exact |
| `agree$n_with_break`, `n_lag01` | **`pat_sv` patches** ⚠ different population from `n_tagged` | exact |
| `agree$pct_lag01_of_break` | ratio within one population — **sound** | 1 dp |
| `agree$pct_lag01_of_tagged` | **cross-population ratio** ⚠ (R3-5) | 1 dp |

Summary of the enumeration: **`area_ha` carries three distinct populations across four
CSVs** (published-clipped-row, unclipped-patch, clipped-eval), **`break_frac_area_wtd`
carries two different weights under one name**, **`n_patches` counts published rows in two
files and `pat_sv` patches in two others**, and **`flicker_frac` / `break_frac` are
measured on one footprint and weighted by another**. That is the round-2 mechanism, intact,
one axis over.

---

## Round 2's fixes — verdict

| fix | verdict |
|---|---|
| R2-1 `pct_lag01` denominators | **partial** — `pct_lag01_of_break` is sound; `pct_lag01_of_tagged` crosses populations (R3-5) |
| R2-2 clear + gate on `group_meta.csv` | **correct for the per-group stage**, both halves verified; the summarize stage still has the original defect (R3-6), and the clear's return is unchecked (R3-7) |
| R2-3 `gm[["..."]]` + `stopifnot` | **correct on the read side**; the write side is still open (R3-8) |
| R2-4 read `reconciled` back | **correct** — one fact, derived once, raw precision, read back |
| R2-5 `area_ha_eval` weighting | **half** — the weight is fixed, the measurand is not (R3-3), Phase 2 was not brought along (R3-4), and it introduced a third NA population (R3-2) |
| R2-6 `join_audit.csv` deferred write + flag-without-year rows | **correct** — straight-line, `n_trimmed` always defined, no partial-file path |

---

## Checked and clean (recorded so the next round need not redo them)

- **`terra::crosstab(..., long = TRUE, useNA = TRUE)` returns numeric columns, not
  factors.** Measured on this terra. So `as.integer(q$break_year_modal)` at line 714 is
  the year, not a factor level index — the classic silent-catastrophe here does not fire.
- `res$breaks` is documented as an **integer** SpatRaster (`dft_rast_break_class.R:31`),
  not factor, corroborating the above.
- `agg_cells()` correctly guards `aggregate`'s "no rows to aggregate" error, and returns a
  frame whose `all.x` merge then fills to `0L` — no zero-length or NaN path.
- `pat_cl$area_ha` overwrite (line 474) is required and correct: `dft_transition_vectors()`
  assigns `area_ha` at line 155 **before** `st_intersection` at line 171, so drift's own
  column is genuinely pre-clip. Verified in the package source.
- No `area_ha.x` / `.y` collision in the `ev_patch` merges: `firstrow` and `flags` select
  4 and 3 columns respectively, neither carrying `area_ha`, and `pub_area` is renamed
  before merging.
- `tag_evaluated` is computed **before** the `in_fire`/`in_harvest` NA fill (672 vs 685).
  Ordering correct.
- Every merge into `ev_patch` reorders rows by `patch_id`, and every subsequent derivation
  is elementwise on `ev_patch`'s own columns — no "derive before you re-order" hazard.
- `k` in Phase 3 contains no `NA` (every term is `%in%`, `>=` on a non-NA column, or
  `!is.na`), so `sum(k)` and the subsetting are sound.
- `strata`/`pops` cover the additive-flag case correctly; the residual is a conjunction of
  zeros, not a subtraction of totals.
- `sf` handling: `st_drop_geometry()` before every column selection and `aggregate`; no
  hardcoded geometry-column name anywhere.
- **Shell wrapper is sound on both traps it names.** `Rscript … &` is on its own line with
  every `mkdir`/`: >` before it, so `$!` is the R process (not the wrapper shell);
  the OK/FAIL branch gates on the in-band `ALL STAGES DONE` marker, not on `rc`; `run.log`
  and `rss.txt` are truncated per run so a stale marker cannot be matched; the empty-`rss.txt`
  default (`peak="n/a"`) is present; `timings.csv` is written before the marker so the OK
  line's `grep` cannot miss it; `fails` accumulates per item rather than reporting the last
  item's status.

---

## Probes run

```r
# 1. crosstab column types (terra, 10x10 fixture)
sapply(crosstab(c(pid, by), long=TRUE, useNA=TRUE), class)
#>       pid        by         n
#> "numeric" "numeric" "numeric"       -> no factor trap at line 714

# 2. 0-row $<-
d <- data.frame(source=character(0)); d$group <- "g"
#> Error in `$<-.data.frame`: replacement has 1 row, data has 0

# 3. full write.csv -> read.csv round trip on a 0-row frame
#> file is header-only; read.csv gives nrow 0, ncol 2; $<- errors identically

# 4. aggregate na.omit drops the row rather than returning NA
aggregate(area_ha ~ patch_id, data.frame(patch_id=1:3, area_ha=c(1,NA,3)), sum)
#> 2 rows: patch 2 absent entirely

# 5. weighted.mean with all-zero weights
weighted.mean(c(1,2), c(0,0))   #> NaN  (no error; unreachable here)
```

Directory layout confirmed on disk: `data-raw/logs/disturbance_compare/{bulk,kotl,lnth,necr}/`
beside `summary_*_groups.csv`, `summary_groups.{csv,md}`, `README.md` — so the per-group
glob and the summarize writes are in different directories, as R2-2 assumed.

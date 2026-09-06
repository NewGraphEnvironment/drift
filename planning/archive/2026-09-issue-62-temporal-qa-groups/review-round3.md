# Code-check round 3 — mechanism behind rounds 1-2, full prose-vs-CSV walk, `round()` walk (#62)

Reviewed the staged diff (55 files) against code-check.md / -shell / -r / -spatial, re-verified
the round-1 and round-2 fixes, rebuilt every cell of `summary_groups.csv` from the per-group CSVs
with a fresh script (unrounded, then rounded as the summarize stage does), recomputed the two
columns whose per-group inputs are rounded from their unrounded sources on disk (the gpkg areas,
`summary_patches.csv`), recomputed the reconcile delta row from unrounded shares, and walked every
numeric range, ratio and table-derived claim in the six prose files against its CSV cell.

## The mechanism

Round 2's findings were one shape, not four: **a claim written from a reading of the emitted table
rather than emitted by the script, and a derived cell computed downstream of a display rounding.**
"Endpoint second in every group" and "49-60% of wall" were table-reading claims; `overstatement_factor
= 100 / pct_sustained` and "0.5 to 1" were derived from rounded intermediates. The guard that exists
(`summary_groups.md` verbatim in the note) covers the *tables*, so every surviving instance sits in
what the guard structurally cannot reach: sentences *about* the tables, formulas documented in
planning files, and `round()` calls in the summarize stage outside the `rows` block round 2 walked.
Three of the four findings below are that shape once more; the fourth is the same defect in the one
`round()` site nobody walked.

## Findings

- **[bug — prose contradicts CSV]** `inst/notes/temporal-qa-groups.md:65-67` — "necr and kotl were
  cut from a gdalcubes cube upstream and bulk and lnth were not (floodplains#83); the values read
  identically and **the necr/kotl rows do not separate from the others on any column**." False.
  Ranking each numeric column of `summary_groups.csv`, the necr/kotl pair sits at one end on
  thirteen columns; leaving aside the five that are floodplain size (`valid_ha`, `ff02/04/06_km2`),
  the temporal ones all point the same way — the cube-cut groups flicker *less*:

  | column | necr / kotl | bulk / lnth | |
  |---|---|---|---|
  | `pct_sustained` | 31.0 / 24.7 | 19.7 / 20.6 | highest two |
  | `pct_flicker` | 39.6 / 42.3 | 44.0 / 48.5 | lowest two |
  | `overstatement_factor` | 3.23 / 4.06 | 5.09 / 4.86 | lowest two |
  | `stable_flicker_over_changed` | 0.66 / 0.63 | 0.69 / 0.97 | lowest two |
  | `n_flips_sliver` | 2.20 / 2.03 | 2.28 / 2.23 | lowest two |
  | `n_flips_wider` | 1.83 / 1.92 | 1.94 / 2.10 | lowest two |
  | `break_frac_all` | 0.604 / 0.577 | 0.560 / 0.515 | highest two |
  | `break_frac_other` | 0.621 / 0.583 | 0.575 / 0.515 | highest two |
  | `cloud_cells_2017` | 0 / 0 | 280 / 62 | zero vs non-zero |

  With n = 4 any one column splits 2-vs-2 by chance one time in three, and these columns are
  correlated (they are all "less flicker"), so this is one signal, not nine — but the sentence as
  written is a table-reading claim that the table refutes, and it is exactly the A2 confound the plan
  review said "the note must name" if it appeared (`findings.md:22`). The `cloud_cells_2017` row is
  the sharpest: the two groups with zero 2017 clouds are the two that came through the cube. Reword
  to state the direction and its size, and say it cannot be separated from producer path at n = 4 —
  do not assert non-separation.

- **[fragile — derived from rounded intermediates]** `data-raw/break_class_groups.R:228` —
  `delta <- round(recon[2, -1] - recon[1, -1], 2)` subtracts the two *rounded* `rec()` rows
  (`valid_ha`, `changed_ha`, `stable_flicker_ha` at 1 dp; shares at 1 dp) and then displays the
  result at 2 dp — a precision the inputs do not have. Measured against unrounded `shares()`:

  | column | committed delta | unrounded delta |
  |---|---|---|
  | `valid_ha` | 0.7 | 0.71 |
  | `changed_ha` | 4.6 | 4.62 |
  | `stable_flicker_ha` | **-0.1** | **-0.03** |
  | `pct_sustained` | 0.0 | -0.033 |
  | `pct_endpoint` | 0.0 | +0.029 |
  | `pct_flicker` | 0.0 | +0.004 |

  The `stable_flicker_ha` delta is overstated 3x (3186.6 − 3186.5 on rounded cells vs 3186.56 −
  3186.53), and the three share deltas read `0.00` for differences that are ±0.03. Nothing in prose
  quotes the wrong values — the note says "71 more valid cells, 4.6 ha more changed area, and the
  three shares identical to one decimal", all of which hold — but this is the identical defect round 2
  fixed in `overstatement_factor`, in the one `round()` site outside the `rows` block. Compute the
  delta from `shares(new)` minus `shares(old)` (both unrounded) and round once.

- **[fragile — derived from rounded intermediates, no effect at current values]**
  `data-raw/break_class_groups.R:169` and `:177-178` — `ff06_over_ff02` divides `area_km2` cells
  that `shape_row()` (line 113) already rounded to 2 dp, and `pct_area_artifact` divides `area_ha`
  cells that `grp()` (line 372) already rounded to 1 dp. Recomputed from the unrounded gpkg areas
  (same `st_make_valid` → `st_transform` → `st_union` path) and from `summary_patches.csv`: all
  eight committed cells are unchanged (raw ratios 1.202655 / 1.219515 / 1.264138 / 1.081248; raw
  shares 17.7666 / 13.0718 / 24.5251 / 17.8441 — none within 5e-4 of a rounding boundary). So the
  cells are right, by margin rather than by construction. Same fix shape as round 2: carry an
  unrounded area column in `summary_shape.csv` / `summary_patch_groups.csv` (or compute the ratio in
  the per-group stage from `a`) so the summarize stage never divides a display value.

- **[low — planning doc describes a formula the code no longer uses]** `planning/active/findings.md:20`
  (G4) — "derived figures (`overstatement_factor = 100 / pct_sustained`, …) are columns, not prose
  arithmetic". Round 2 changed the derivation to `changed_ha / sustained_ha` from unrounded areas
  (`break_class_groups.R:156`); the findings entry still documents the rounded-input formula that
  produced 5.08 / 4.85 / 4.05. Same class as round 2's "unlinked on exit" — a description of the code
  that stayed put when the code moved. Append the correction (findings is append-only) rather than
  leaving a formula a reader would reproduce to the wrong last digit.

## Walk: every numeric range / ratio / table-derived claim in prose vs its CSV cell

49 items enumerated across six files; 2 mismatches (the necr/kotl claim and the G4 formula, above).
Everything else matches the cell it must come from.

**`inst/notes/temporal-qa-groups.md`** (27): Q1 sustained 19.7 / 31.0 / 20.6 / 24.7 ✓; flicker
39.6-48.5 and largest in every group ✓ (44.0 > 36.4, 39.6 > 31.0, 48.5 > 31.0, 42.3 > 33.1);
endpoint 29.4-36.4 second in three, necr 31.0 edges 29.4 ✓; factor 3.2 to 5.1 (3.23-5.09) ✓; no
group above a third (max 31.0) ✓; stable-flicker 3.2-9.9% (3.22-9.85) ✓; 0.63 to 0.97 ✓. Q2 2018 >
2023 in all four ✓; ratio 1.09 (kotl) to 1.25 (necr) ✓; 16.3-20.0 / 13.1-16.4 ✓; bulk 280 cells =
2.8 ha of 925.7 ✓ (`summary_class_freq.csv` 2017 Clouds 280); lnth 62 ✓; necr/kotl 0 in 2017 ✓. Q3
1.081 (kotl) to 1.264 (lnth) ✓; 166.5-423.2 m ✓; 2.5x (2.54) ✓; 9 points (8.9) ✓; kotl in the
middle (rank 2 of 4) ✓; necr 186.7 / lnth 196.4 lowest / highest flicker ✓; sliver 2.03-2.28 vs
wider 1.83-2.10 and sliver > wider in each group ✓. Q4 eight `break_frac` cells ✓; three lower,
lnth indistinguishable ✓; 13.1-24.5% ✓. Reconciliation 14651 x 11552 / 16000 x 12000, +71 cells,
+4.6 ha, shares identical to one decimal ✓ (`summary_bulk_reconcile.csv`; grid dims from
`group_meta.csv` and findings). Run 13.7-16.3 GiB, 56M-204M cells ✓. "necr/kotl rows do not
separate on any column" ✗ (above). Q5 restatements 39.6-48.5 / 3.2-5.1x ✓.

**`data-raw/logs/break_class_groups/README.md`** (7): 2026-09-05, terra 1.9.34, drift 0.14.0 ✓
(`group_meta.csv`); bulk 312 s / 15.4, kotl 323 / 16.3, lnth 100 / 13.7, necr 138 / 14.2 ✓
(`timings.csv` wall 312.3 / 322.6 / 99.9 / 137.9; `rss.txt` max 16,124,224 / 17,067,376 /
14,341,984 / 14,872,368 KiB = 15.38 / 16.28 / 13.68 / 14.18 GiB); 14-16 GiB, 56M-204M ✓; 44-58% of
wall (48.9 / 43.8 / 46.9 / 57.9) ✓; 1.7-2.2x overlap ✓ against findings B1 (1.69 / 1.86 / 2.19 —
no committed CSV; a plan-review measurement); 8.5-20 GB ✓ (CLAUDE.md, the #9 run).

**`NEWS.md`** (2): 19.7-31.0%, 39.6-48.5% ✓. **`CLAUDE.md`** (2): 20-31%, 40-49% ✓ (rounded).

**`planning/active/task_plan.md`** (5): header 4,620 ha / 19.7 / 36.4 / 44.0 / 3,187 ha ✓ against
`benchmark_break_class/summary_change.csv` (4620.35; 19.69 / 36.35 / 43.95; 3186.56); Phase 2 wall
and peak per group ✓; +71 / +4.6 / identical to one decimal ✓; Phase 4 39.6-48.5 and 3.2-5.1x ✓.
"867 pass, 0 fail, 13 skip" not re-run here (no `R/` change in the diff).

**`planning/active/findings.md`** (6): grid dims for four groups ✓ (`group_meta.csv`); G2 clouds
280 / 62 / kotl 2019:4 + 2021:1 / necr none ✓; G4 formula ✗ (above); A4 204.5M / 6.94M / 4.11M /
~1.7x (1.69) ✓ — "7-9 min, 10-14 GB" is labelled a prediction (actual 5.4 min, 16.3 GiB); O2
4,108,972 vs 4,108,901, 71 cells ✓; issue-context 4,620 / 19.7 / 36.4 / 44.0 / 922 / 757 / 3,187 /
0.50 vs 0.58 ✓ against `benchmark_break_class/` (`summary_pixels.csv` break area 2018 = 922.67,
2023 = 757.00; `summary_patch_groups.csv` 0.496 vs 0.575).

## Walk: every `round()` in the summarize stage

| line | expression | inputs | verdict |
|---|---|---|---|
| 129 | `pct()` shares | unrounded `area_ha` | ✓ |
| 152-153 | `valid_ha`, `changed_ha`, `pct_changed_of_valid` | unrounded | ✓ |
| 156 | `overstatement_factor` | unrounded `changed_ha / sustained_ha` (round-2 fix) | ✓ verified: 5.09 / 3.23 / 4.86 / 4.06 |
| 157-158 | `stable_flicker_ha`, `pct_stable_flicker_of_valid` | unrounded | ✓ |
| 160 | `stable_flicker_over_changed` | unrounded | ✓ |
| 161-163 | `break_20xx_ha`, `pct_break_20xx`, `ratio_2018_2023` | unrounded `byyr$area_ha` / unrounded `changed_ha` | ✓ |
| 169 | `ff06_over_ff02` | **`area_km2` rounded to 2 dp at line 113** | finding 3 |
| 177 | `pct_area_artifact` | **`area_ha` rounded to 1 dp at line 372** | finding 3 |
| 185 | `peak_rss_gib` | raw KiB | ✓ |
| 222-225 | `rec()` | unrounded, rounded once for display | ✓ |
| 228 | `delta` | **the rounded `rec()` rows** | finding 2 |

Pass-through columns (`break_frac_*`, `n_flips_*`, `ff04_width_m`, `ff0x_km2`, `ff04_perimeter_km`)
are copied, not derived; `width_m` at line 115 is from unrounded `a` and `p`. Rebuilding the 16
derived-from-`summary_change`/`summary_break_year`/`rss.txt` columns from scratch reproduced every
committed cell for all four groups.

## Round-1 and round-2 fixes, verified

- `rss.txt` peaks (above) match the Run table; each file's first sample is 32 KiB (pre-`exec`
  child), harmless to `max()`; `run_wallclock.txt` 23:41:43 → 23:56:28 UTC contiguous, all `exit 0`.
- `verify_checksum()` unlinks `path` and `item_json` together (line 81); `fetch_once()` then
  refetches both on the next run, so the remedy converges.
- Note prose: "second in three groups, necr 31.0 edges 29.4" ✓; README "44-58%" ✓;
  `overstatement_factor` from unrounded areas ✓; `stable_flicker_over_changed` is a column and the
  note quotes its range ✓; the note-verbatim guard (line 234-242) now runs after the reconcile write
  (line 231) ✓; task_plan reads "removed with the session tempdir" ✓.
- `summary_groups.md` minus its comment line is contained byte-for-byte in the note (re-checked
  with Python `in`, independent of the script's `grepl`).

## Checked and clean

- `.gitignore`: `check-ignore -v` puts `item.json` and `summary_patches.csv` under the new lines,
  `rss.txt` untouched; `git ls-files 'data-raw/logs/**/*.json'` is empty, so the new `**/*.json`
  rule hides nothing tracked.
- Launcher: `Rscript … &` alone, `$!` is R; per-item `OK`/`FAIL` with `fails` as exit; `timings.csv`
  read only on the marker branch; `set -u` with no arrays; `sort -n` on `ps -o rss=` output.
- Script: `[[` on the parsed item JSON; `curl_fetch_disk` to tmp + rename on 200; `st_length(st_boundary())`
  not `st_perimeter()`; `cat_fun` refuses a bare vector; `levels(codes) <- NULL` on a `deepcopy`;
  `compareGeom` across the seven; `!inMemory` premise; consecutive-years and equal-valid-cells asserts;
  `pick()` returns `NA_real_` on a missing label rather than a zero-length value in `data.frame()`.
- The two remaining accepted tradeoffs (`cat_fun` duplication, downloaded COGs, tempfile intermediates)
  are as stated in the README.

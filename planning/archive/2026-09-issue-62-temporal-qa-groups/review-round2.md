# Code-check round 2 — evidence CSVs, note, README, NEWS, CLAUDE.md, launcher, script (#62)

Reviewed the staged diff against code-check.md / -shell / -r / -spatial, the round-1 fixes,
every committed CSV / rss.txt / run_wallclock.txt under `data-raw/logs/break_class_groups/`,
the summarize stage of `data-raw/break_class_groups.R`, and every numeric claim in the prose
files against the CSV cells they cite.

## Findings

- **[bug — prose contradicts CSV]** `inst/notes/temporal-qa-groups.md:22-23` — "Flicker is the
  largest category in every group (39.6-48.5%), and an endpoint-only break the second
  (29.4-36.4%)". False for necr: `summary_groups.csv` has necr `pct_sustained` 31.0 >
  `pct_endpoint` 29.4, so in necr the endpoint-only break is **third**, not second. True for
  bulk (36.4 > 19.7), lnth (31.0 > 20.6) and kotl (33.1 > 24.7). The 29.4-36.4 range is
  right; the ordinal claim is not. Reword: "the second in three groups; in necr the sustained
  switch (31.0%) edges it (29.4%)".

- **[bug — prose contradicts CSV]** `data-raw/logs/break_class_groups/README.md:29` — "The
  transition-artifact stage is the wall-clock floor (49-60% of each run)". From the committed
  `timings.csv` (`transition_artifact / wall`): bulk 152.8/312.3 = **48.9%**, kotl 141.2/322.6
  = **43.8%**, lnth 46.9/99.9 = **46.9%**, necr 79.8/137.9 = **57.9%**. Two of four groups sit
  outside the stated range and the top is never reached; the range is 44-58%. "Largest stage
  in every run" is true; the percentages are hand-typed and wrong.

- **[fragile — double rounding]** `data-raw/break_class_groups.R:150` — `overstatement_factor =
  round(100 / sh$pct_sustained, 2)` divides by the share already rounded to one decimal by
  `pct()` (line 132). Recomputed from the unrounded share the cell differs in the last digit
  for three of four groups: bulk 5.09 (committed 5.08), lnth 4.86 (4.85), kotl 4.06 (4.05);
  necr 3.23 either way. The note's "3.2 to 5.1" is unaffected, and `findings.md` documents it as
  `100 / pct_sustained`, so this is a precision defect rather than a mismatch — but a column
  named as a ratio should be computed from the unrounded quantity (`100 * changed_ha /
  sustained_ha`), not from a display value.

- **[low — loose hand-typed bound]** `inst/notes/temporal-qa-groups.md:27` — stable-endpoint
  flicker is "0.5 to 1 times the changed area itself". `stable_flicker_ha / changed_ha` from
  `summary_groups.csv` is 0.69 (bulk), 0.66 (necr), 0.97 (lnth), 0.63 (kotl). The lower bound
  is 0.63, not 0.5. Not a cell mismatch, but a number typed rather than derived; "0.6 to 1"
  or "two-thirds to the whole of" matches.

- **[low — fragile ordering]** `data-raw/break_class_groups.R:201-208` — the note-verbatim
  `stop()` fires after `summary_groups.csv` / `.md` are written (lines 165, 200) and before
  `summary_bulk_reconcile.csv` is rewritten (line 226). A summarize run that trips the guard
  leaves a fresh `summary_groups.*` beside a stale reconcile CSV, and a commit taken at that
  point ships evidence from two different runs. Move the check after the reconcile write
  (or before any write). Loud, not silent — the guard itself is correct.

- **[low — plan claim contradicted by code]** `planning/active/task_plan.md` Phase 1, checked
  item "every intermediate raster via `filename = tempfile()` and unlinked on exit" — the script
  has no `unlink()`/`on.exit()` for the six `tempfile()` rasters (an accepted tradeoff: R
  removes the session tempdir). The checkbox asserts a behaviour the code does not have; strike
  "and unlinked on exit" or say "left to R's tempdir cleanup".

## Checked and clean

- **Round-1 fixes.** (a) All four `rss.txt` files now sample R: peaks 16,124,224 (bulk),
  17,067,376 (kotl), 14,341,984 (lnth), 14,872,368 (necr) KiB → 15.4 / 16.3 / 13.7 / 14.2 GiB,
  matching the Run table; first sample of each is 32 KiB (the forked child before `exec`),
  harmless to a max. Sample counts (148 / 153 / 48 / 66 at 2 s) and `run_wallclock.txt`
  (`start <g>` / `end <g> (exit 0)`, 23:41:43 → 23:56:28 UTC, contiguous) agree with `wall`
  in `timings.csv` to within R startup (312.3 vs 316 s etc.). (b) `verify_checksum()` now
  deletes `item.json` with the mismatched asset; a re-run refetches the JSON, so the remedy
  converges (one asset per run in the worst case of a full republish, but it terminates).
- **Every other number in the note, NEWS, CLAUDE.md, README, task_plan, findings** matches its
  CSV cell: Q1 shares, 3.2-5.1x, 3.2-9.9%, "no group above a third"; Q2 ratios 1.09-1.25,
  16.3-20.0 / 13.1-16.4, 280 / 62 / 0 / 0 clouds in 2017 (kotl's 5 = 2019:4 + 2021:1 per
  `summary_class_freq.csv`), 2.8 ha of 925.7; Q3 1.081-1.264, 166.5-423.2 m (2.54x), 9-point
  flicker spread, necr/lnth width and rank claims, sliver > wider `n_flips` in all four; Q4
  all eight `break_frac` cells, 13.1-24.5%; reconciliation +71 cells / +4.6 ha / shares
  identical to one decimal; README run order, wall and peak per group, 1.7-2.2x overlap;
  CLAUDE.md 20-31% / 40-49% (rounded); NEWS 19.7-31.0 / 39.6-48.5; findings A4 6.94M valid,
  O2 4,108,972 vs 4,108,901.
- **Summarize columns compute what their names claim**: `valid_ha` = all rows of
  `summary_change.csv` (sums to `valid_cells`: 4,108,972 / 6,937,760 / 1,600,176 / 4,183,814);
  `pct_*` over `changed == 1` rows; `pct_break_20xx` over `changed_ha` (not the break area —
  matches the note's "share of the changed area"); `stable_flicker_ha` from `changed == 0 &
  flicker`; `cloud_cells_*` from `class_name == "Clouds"` (code 10 in
  `inst/lulc_classes/io_lulc_v02.csv`); `ff06_over_ff02`, `pct_area_artifact` (over `all`,
  which equals the changed area), `peak_rss_gib = max(KiB) / 1024^2`; `width_m` recomputes
  (2 × 386.42e6 / 4642.6e3 = 166.5).
- **Internal identities hold in every group**: `summary_break_year.csv` n_cells sums to
  categories 1+2 of `summary_change.csv`, and 2018+2023 to category 2 exactly (A1);
  `summary_pixels.csv` sums to the valid count with no `NA`-status rows; valid cells equal
  across all seven years; `res$breaks` layer order (`break_year, n_before, n_after, n_flips`)
  matches `cat_fun`'s column indices; `flag_sliver/boundary/reciprocal` exist in
  `dft_transition_artifact()` output.
- `cat_fun` is byte-identical to the BULK script's (diffed). The #9 `summary_change.csv` has
  the same six columns the reconcile reads. `summary_groups.md` is contained verbatim in the
  note (re-ran the `grepl`: TRUE). Staged note == disk note; the Q5 bullet's "3.2-5.1x" is a
  CSV-backed figure.
- Launcher: `Rscript … &` alone; `ps -o rss=` output's leading blanks are fine for `sort -n`
  and `scan()`; `grep 'wall'` matches only the `"wall"` row; per-item FAIL count is the exit.
- `.gitignore`: `check-ignore` puts `item.json`, the COGs and `run.log` under the new/existing
  patterns and leaves `rss.txt` and the summary CSVs tracked; no tracked `.json` under
  `data-raw/logs`.
- `digest`, `knitr` in DESCRIPTION; `st_length(st_boundary())` avoids lwgeom; `[[` used on
  the parsed item JSON.

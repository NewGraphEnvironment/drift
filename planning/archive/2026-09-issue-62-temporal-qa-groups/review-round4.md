# Code-check round 4 — round-3 fixes verified; the mechanism re-walked past the repo boundary (#62)

Reviewed the staged diff against code-check.md / -shell / -r / -spatial. Re-ran the `summarize`
stage in a scratch rsync of the repo (no `.git`, no rasters) and byte-compared its three outputs
against the staged files; recomputed the reconcile row by hand from the two `summary_change.csv`
inputs; re-walked every numeric claim in the note, README, NEWS, CLAUDE.md and the three planning
files against `summary_groups.csv`; then followed the note's own claim that the Q5 issues were
"filed with these numbers in their bodies" to the two issue bodies.

## Round-3 fixes, verified

- **necr/kotl bullet** (`inst/notes/temporal-qa-groups.md:65-72`): `pct_flicker` 39.6 / 42.3
  against 44.0 / 48.5 ✓, `pct_sustained` 31.0 / 24.7 against 19.7 / 20.6 ✓, "the two with no 2017
  clouds" ✓ (`cloud_cells_2017` 0 / 0 vs 280 / 62; kotl's 5 clouds are 2019 + 2021). "The two that
  flicker least" ✓ — necr and kotl are ranks 1-2 on `pct_flicker`. The confound is named, not
  asserted away; floodplains#83 confirms the pairing (necr and kotl carry the 30 gdalcubes/NetCDF
  tags, bulk and lnth do not).
- **`rec()` / delta** (`data-raw/break_class_groups.R:222-234`): `rec()` returns unrounded shares
  from unrounded `area_ha`; each of the three rows is rounded once at 2 dp. Hand recomputation from
  the two inputs: valid_cells 4108901 / 4108972 / +71; changed_ha 4620.35 / 4624.97 / +4.62;
  pct_sustained 19.694 → 19.69, 19.662 → 19.66, delta −0.033 → −0.03; pct_endpoint 36.354 → 36.35,
  36.383 → 36.38, delta +0.029 → 0.03; pct_flicker 43.952 → 43.95, 43.956 → 43.96, delta +0.004 → 0;
  stable_flicker_ha 3186.56 / 3186.53 / −0.03. Every cell of the committed
  `summary_bulk_reconcile.csv` matches.
- **Reconciliation sentences**: note `:58-61` "71 more valid cells, 4.62 ha more changed area, and
  the three shares within 0.03 of a point" ✓; `task_plan.md:28` "+71 valid cells, +4.62 ha changed,
  three shares within 0.03 of a point" ✓; `findings.md:25` (O2) 4,108,972 vs 4,108,901 ✓.
- **Scratch re-run of `summarize`**: `summary_groups.csv`, `summary_groups.md` and
  `summary_bulk_reconcile.csv` came back byte-identical (`cmp`) to the staged files, and the
  note-verbatim guard printed `note tables match summary_groups.md`. So the staged CSVs are what the
  staged script emits from the staged per-group inputs.
- **`ff06_over_ff02` / `pct_area_artifact`** accepted-as-recorded: README and findings.md both carry
  the record ✓. Hand check of the four ratios from the rounded inputs reproduces the committed cells.
- **findings.md G4 formula** now reads `changed_ha / sustained_ha` (`:20`) ✓.

## Findings

- **[bug — a downstream record claims to be the CSV and disagrees with it]**
  `NewGraphEnvironment/stac_floodplains_bc#67` body, table headed "The numbers (drift
  `data-raw/logs/break_class_groups/summary_groups.csv`)" — `overstatement_factor` reads
  **5.08 / 3.23 / 4.85 / 4.05**. The staged `summary_groups.csv` has **5.09 / 3.23 / 4.86 / 4.06**.
  The three wrong cells are exactly `100 / pct_sustained` from the rounded share (100/19.7 = 5.076,
  100/20.6 = 4.854, 100/24.7 = 4.049) — the formula round 2 removed from the script at
  `break_class_groups.R:156`. The issue was filed at 2026-09-06T00:00Z, before rounds 2-3, and the
  fix never reached it. This matters because the diff asserts the propagation happened: the note
  says the Q5 decisions "are filed as their own issues with these numbers in their bodies"
  (`inst/notes/temporal-qa-groups.md:75`) and `task_plan.md:38` ticks "Filed with the numbers". The
  issue's prose range "3.2-5.1x" still holds; the table it rests on does not. Same mechanism round 3
  named (a derived cell downstream of a display rounding), one artifact further out than the walk
  reached — `code-check.md`, "Written data outlives the fix": grep for the *number*, not the file.
  Remedy: `gh issue edit 67 --repo NewGraphEnvironment/stac_floodplains_bc --body-file …` with the
  three cells corrected (issue bodies get edited, not appended). Secondary, same issue family:
  `drift#64` body says the stable-flicker area is "0.5 to 1 times the changed area itself" — the
  hand-typed range round 2 replaced with `stable_flicker_over_changed` (0.63-0.97). Not false
  (0.63-0.97 sits inside 0.5-1), but it is the pre-fix wording under a heading that names the CSV;
  worth correcting in the same pass.

- **[low — planning record overstates a data claim]** `planning/active/findings.md:74` — the round-3
  row says the cube-cut groups "flicker least on **every** temporal column". On `pct_endpoint` kotl
  (33.1) is above lnth (31.0), and on `pct_stable_flicker_of_valid` necr (9.15) is above bulk (7.76),
  so the necr/kotl pair is not at one end of either. Round 3's own review listed the eight columns
  where it holds and did not include these two; the compressed summary in findings.md dropped the
  qualifier. The shipped note (`:65-72`) makes only the three claims that are true. Fix the word
  "every" in findings.md, which becomes the archive record.

- **[low — evidence README's edit inventory is incomplete]**
  `data-raw/logs/break_class_groups/README.md:29-33` — "The only edit to the script after the batch
  was the checksum-mismatch message …, the rounding of the reconciliation delta row, and … deriving
  `overstatement_factor` … and adding `stable_flicker_over_changed`". Round 2 also moved the
  note-verbatim guard to run after the reconcile write (round-3 review, "Round-1 and round-2 fixes,
  verified"), and round 3 restructured `rec()` rather than only re-rounding a delta. Neither changes
  a number, and the sentence's load-bearing claim — "no per-group number moved" — is confirmed by
  the scratch re-run. But "the only edit" is an enumeration, and `run.log` is gitignored, so this
  sentence is the only record of what changed post-batch; say "summarize-stage edits only" or list
  them completely.

## Re-walk of prose touched or added since round 3

Every range, ratio and table-reading claim in the six repo files checked against `summary_groups.csv`
and the per-group CSVs; all hold. Sample of the ones re-derived rather than re-read: Q2
break_2018 + break_2023 = pct_endpoint area in every group (925.73 + 756.96 = 1682.69 bulk; 942.32 +
756.64 = 1698.96 necr; 272.63 + 232.06 = 504.69 lnth; 610.62 + 559.37 = 1169.99 kotl) — the Q2
derivation identity holds on the data, not only in the code comment. README run order bulk → kotl →
lnth → necr matches `run_wallclock.txt` (23:41:43 / 23:46:59 / 23:52:25 / 23:54:07 Z, all `exit 0`,
contiguous). Transition-artifact share of wall 48.9 / 57.9 / 46.9 / 43.8 % → "44-58%" ✓. Peak RSS
16,124,224 / 14,872,368 / 14,341,984 / 17,067,376 KiB → 15.4 / 14.2 / 13.7 / 16.3 GiB ✓. `.gitignore`
new rules: `run.log`, `item.json`, `summary_patches.csv`, `.tif`, `.gpkg` all `check-ignore` as
ignored; zero tracked `.json` under `data-raw/logs`, so the `**/*.json` rule hides nothing. Launcher
unchanged since round 3 (`Rscript … &` alone, per-item OK/FAIL, `fails` as exit). `#67`'s cost
paragraph (21-72 s scan, 100-323 s wall, 14-16 GiB) matches `timings.csv` / `rss.txt`; `#64`'s table
matches the CSV cell for cell.

## Verdict

One real defect, outside the diff but inside a claim the diff makes: the `stac_floodplains_bc#67`
body carries three pre-round-2 `overstatement_factor` cells under a heading naming
`summary_groups.csv`. Everything staged in the repo is internally consistent and reproduces from the
script.

# Task: Temporal QA across watershed groups from the published annual series: does the BULK split generalise? (#62)

`dft_rast_break_class()` (#9, v0.14.0) was measured on one watershed group. On BULK, of the
4,620 ha the 2017 -> 2023 comparison reports as change, 19.7% is a switch sustained two years each
side, 36.4% is a clean switch with 2017 or 2023 the odd year out, and 44.0% flickers; 3,187 ha
flickers while reading stable on the endpoints. Now that floodplains#79 / stac_floodplains_bc#59
have published every IO LULC year for **four** groups (`bulk_co_ff04`, `necr_ch_ff04`,
`lnth_ch_ff04`, `kotl_bt_ff04`; PINE was dropped upstream — floodplains#76), run the temporal leg
across all four from the published assets and answer the questions one group cannot.

Analysis only. Nothing in `R/` changes unless the run finds a defect.

## Phase 1: Script — `data-raw/break_class_groups.R`
- [x] Stages: `Rscript data-raw/break_class_groups.R <group>` (one group per process) and `Rscript data-raw/break_class_groups.R summarize`; refuse an unknown group; header documents usage and the RSS sampler (`ps -o rss= -p $PID >> rss_<group>.txt` every 2 s)
- [x] Per group, download the seven COGs and `floodplain.gpkg` to `data-raw/logs/break_class_groups/<group>/` with the BULK gpkg pattern (`curl_fetch_disk` to tmp, rename on HTTP 200 only, skip if present); assert seven files, one grid, one CRS
- [x] `dft_rast_classify(source = "io-lulc")` -> `dft_rast_break_class()`; write `summary_pixels.csv` (Q2 comes from its `break` rows by `break_year`: `n_before == 1` is exactly `break_year == 2018`, `n_after == 1` exactly `break_year == 2023`)
- [x] Category crosstab identical to BULK (0 stable / 1 sustained >= 2 each side / 2 endpoint-only / 3 flicker, crossed with endpoint-changed) -> `summary_change.csv` (Q1). `cat_fun` is copied from the BULK script with a comment saying why it is duplicated
- [x] `dft_transition_vectors(changes_only = TRUE)` -> `dft_transition_artifact()` -> per-patch zonal (`break_frac`, `break_year_mean`, `n_flips_mean`) -> the same six patch-group rows -> `summary_patch_groups.csv` (Q4); `summary_patches.csv` written but gitignored (add `data-raw/logs/break_class_groups/*/summary_patches.csv`)
- [x] Q3 leg (redesigned after the plan review): `summary_shape.csv` per group — ff02/ff04/ff06 areas, perimeter, polygon count and `2A/P` width from the published gpkg; the `_by_blue_line_key` segment design was rejected (polygons overlap 1.7-2.2x, kotl has no layer). Within-group width evidence comes from the sliver / wider rows of `summary_patch_groups.csv`
- [x] Verify every download against the asset's `file:checksum`; `summary_class_freq.csv` per year (clouds); assert consecutive years and equal valid-cell counts
- [x] `data-raw/break_class_groups-run.sh` — launcher that samples the Rscript PID's RSS (a first sampler caught the wrapper shell: `&` binds the whole `&&` list)
- [x] `timings.csv` per group; `ALL STAGES DONE` marker; every intermediate raster via `filename = tempfile()` (removed with the session tempdir)
- [x] `summarize` stage: read the four groups' CSVs -> `summary_groups.csv` and a kable `summary_groups.md` the note includes verbatim, plus `summary_bulk_reconcile.csv`; one row per group: changed ha; sustained / endpoint / flicker % (Q1); 2018-break and 2023-break ha and % of changed (Q2); floodplain `2A/P`, `ff06_over_ff02`, `ff04_width_m`, sliver vs wider `n_flips` (Q3); `break_frac` for artifact-signature vs other patches (Q4)

## Phase 2: Run on the four groups, commit the evidence
- [x] necr shakedown, then `break_class_groups-run.sh bulk kotl lnth necr` (reviewer's order: bulk first for the reconciliation, kotl second as the memory ceiling); each gated on `ALL STAGES DONE`
- [x] Peak RSS (GiB) and wall per group: bulk 312 s / 15.4, kotl 323 s / 16.3, lnth 100 s / 13.7, necr 138 s / 14.2 — in `summary_groups.csv` (`Run` table) and the README
- [x] BULK reconciliation (`summary_bulk_reconcile.csv`): +71 valid cells, +4.62 ha changed, three shares within 0.03 of a point
- [x] `data-raw/logs/break_class_groups/README.md`
- [x] Commit the per-group CSVs, `summary_groups.csv` / `.md`, `summary_bulk_reconcile.csv`, `rss.txt`, README

## Phase 3: Note and bookkeeping
- [x] `inst/notes/temporal-qa-groups.md` — Q1-Q4 answered; tables are `summary_groups.md` included verbatim and the summarize stage refuses to finish if the note's copy differs
- [x] `CLAUDE.md` Reference docs line; `NEWS.md` `(development version)` entry
- [x] Edit issue #62 body: four groups not five, PINE excluded with the floodplains#76 link, Q3 metric named (done before the run, per the review)

## Phase 4: Q5 decisions, archive, PR
- [x] Filed with the numbers: (a) drift#64 corrected annual series (flicker 39.6-48.5% of changed area in every group — worth building); (b) stac_floodplains_bc#67 `break_n_flips` / `break_year` assets (overstatement 3.2-5.1x everywhere)
- [x] Fold in the Plan-agent review findings (landed before the first run; see findings.md)
- [ ] `/planning-archive` with Measurement + Evidence sections; `/gh-pr-push` with `Relates to NewGraphEnvironment/sred-2025-2026#16`

## Validation

- [x] Tests pass (867 pass, 0 fail, 13 skip; no `R/` change)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

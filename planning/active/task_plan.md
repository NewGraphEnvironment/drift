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
- [ ] Stages: `Rscript data-raw/break_class_groups.R <group>` (one group per process) and `Rscript data-raw/break_class_groups.R summarize`; refuse an unknown group; header documents usage and the RSS sampler (`ps -o rss= -p $PID >> rss_<group>.txt` every 2 s)
- [ ] Per group, download the seven COGs and `floodplain.gpkg` to `data-raw/logs/break_class_groups/<group>/` with the BULK gpkg pattern (`curl_fetch_disk` to tmp, rename on HTTP 200 only, skip if present); assert seven files, one grid, one CRS
- [ ] `dft_rast_classify(source = "io-lulc")` -> `dft_rast_break_class()`; write `summary_pixels.csv` (Q2 comes from its `break` rows by `break_year`: `n_before == 1` is exactly `break_year == 2018`, `n_after == 1` exactly `break_year == 2023`)
- [ ] Category crosstab identical to BULK (0 stable / 1 sustained >= 2 each side / 2 endpoint-only / 3 flicker, crossed with endpoint-changed) -> `summary_change.csv` (Q1). `cat_fun` is copied from the BULK script with a comment saying why it is duplicated
- [ ] `dft_transition_vectors(changes_only = TRUE)` -> `dft_transition_artifact()` -> per-patch zonal (`break_frac`, `break_year_mean`, `n_flips_mean`) -> the same six patch-group rows -> `summary_patch_groups.csv` (Q4); `summary_patches.csv` written but gitignored (add `data-raw/logs/break_class_groups/*/summary_patches.csv`)
- [ ] Q3 leg: `st_transform` the `<sp>_ff04_by_blue_line_key` layer to the raster CRS, `terra::rasterize(field = "blue_line_key", filename = ...)`, crosstab against the category raster -> per-segment `area_ha`, share flicker / sustained / endpoint of its changed area, stable-endpoint flicker share, effective width `2 * area / perimeter` (m) -> `summary_segments.csv`; whole-floodplain `2A/P` as one row of group metadata
- [ ] `timings.csv` per group; `ALL STAGES DONE` marker; every intermediate raster via `filename = tempfile()` and unlinked on exit
- [ ] `summarize` stage: read the four groups' CSVs -> `summary_groups.csv`, one row per group: changed ha; sustained / endpoint / flicker % (Q1); 2018-break and 2023-break ha and % of changed (Q2); floodplain `2A/P`, Spearman rho of segment flicker share vs segment width, flicker share by width tercile (Q3); `break_frac` for artifact-signature vs other patches (Q4)

## Phase 2: Run on the four groups, commit the evidence
- [ ] Run necr first (smallest) as the shakedown, then lnth, bulk, kotl; each with the RSS sampler; gate each on `ALL STAGES DONE` in its log, not the wrapper exit
- [ ] Record peak RSS (GiB, one unit) and wall time per group in `timings.csv` / README
- [ ] Reconcile the BULK re-measurement against `data-raw/logs/benchmark_break_class/summary_change.csv` (published 14651 x 11552 grid vs fetched 16000 x 12000): the three shares should agree within a couple of points; a larger gap is a finding, not noise
- [ ] `data-raw/logs/break_class_groups/README.md` — what produced it, when, on what, which files are committed vs gitignored
- [ ] Commit the per-group CSVs, `summary_groups.csv`, `rss_*.txt`, README

## Phase 3: Note and bookkeeping
- [ ] `inst/notes/temporal-qa-groups.md` — Q1-Q4 each answered with a per-group table; every number names the CSV and column it comes from; the BULK-vs-#9 reconciliation line; what the numbers do and do not support
- [ ] `CLAUDE.md` Reference docs: add the note; `NEWS.md` entry under the development heading
- [ ] Edit issue #62 body: four groups not five, PINE excluded with the floodplains#76 link, Q3 metric named

## Phase 4: Q5 decisions, archive, PR
- [ ] File or close-as-not-worth-it, with the numbers in the body: (a) drift issue for the per-pixel mode-filter corrected series; (b) stac_floodplains_bc issue for carrying temporal evidence beside `transition_2017_2023`
- [ ] Fold in the Plan-agent review findings (spawned during planning; arrives asynchronously)
- [ ] `/planning-archive` with Measurement + Evidence sections; `/gh-pr-push` with `Relates to NewGraphEnvironment/sred-2025-2026#16`

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

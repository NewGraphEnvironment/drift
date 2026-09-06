# Findings — Temporal QA across watershed groups from the published annual series (#62)

## Plan-mode exploration (2026-09-05)

- Four items carry seven `classified_*` assets: bulk_co_ff04 (EPSG:32609, 14651 x 11552), necr_ch_ff04 (32610, 6288 x 8945), lnth_ch_ff04 (32610, 11212 x 5398), kotl_bt_ff04 (32611, 13437 x 15219). PINE was dropped upstream (floodplains#79 / stac_floodplains_bc#59; tracked in floodplains#76). The issue's "five" is four.
- STAC API `https://images.a11s.one/collections/stac-floodplains-bc/items?limit=10` paginates by `next` links; `page=` is ignored (same 10 items every time).
- Published COGs: ~0.5-1.3 MB, Byte, DEFLATE, nodata 255, palette + RAT (TIFF tag 42112), 512 blocks, overviews, NGE_* provenance tags. `terra::rast()` reads them as non-factor integer (cats NULL; unique = 1,2,4,5,7,8,9,11); `dft_rast_classify(source = "io-lulc")` works unchanged (probed necr 2018).
- `floodplain.gpkg` layers: `<sp>_ff02`, `<sp>_ff04` (1 feature), `<sp>_ff04_by_blue_line_key` (427/244/179 features for bulk/necr/lnth; fields valley, blue_line_key, wsg, species, scenario, gnis_name; EPSG:3005), `<sp>_ff06`, `layer_styles`.
- `R/dft_rast_break_class.R` spills only in-memory inputs to disk; file-backed inputs stack without copying. Reading local COG copies removes the 8.5-20 GB input floor the BULK run carried.
- Published BULK grid (14651 x 11552) differs from the #9 run's fetched grid (16000 x 12000), so BULK is re-measured here and reconciled against `data-raw/logs/benchmark_break_class/summary_change.csv`.
- Machine m1, 64 GB, 1.1 TB free.

## Plan-agent review (2026-09-05, spawned during planning; landed after approval)

One blocker, five gaps, four ordering points; all folded into `data-raw/break_class_groups.R` before the first run.

- **B1 — the per-stream `_by_blue_line_key` layer is unusable for Q3.** Its polygons overlap: sum of segment areas / union = 1.69 (necr, re-measured here), 1.86 (bulk), 2.19 (lnth) — tributary floodplains nest inside the mainstem's, so `rasterize()` last-wins would assign about half the area by feature order. `valley` is the constant 1. `kotl_bt_ff04` has no such layer at all (`bt_ff02`, `bt_ff04`, `bt_ff06`, `layer_styles`). Replaced by two shape proxies derived from the published polygons — ff06 / ff02 area ratio (how much the floodplain widens with flood factor) and ff04 effective width `2A/P` with perimeter and polygon count beside it — plus the #44 sliver-vs-wider patch rows already in `summary_patch_groups.csv`. With n = 4 there is no test; the note shows the rows.
- **G2 — clouds.** Code 10 is present in bulk 2017 (280 cells), lnth 2017 (62), kotl 2019 (4) and 2021 (1), per the reviewer's histograms; nowhere in necr. A cloudy year counts as a flip, so the script writes `summary_class_freq.csv` per year and the summary carries `cloud_cells_2017` beside the 2018-break area. Not masked: masking would make a year `NA` and blank all four evidence layers for those cells.
- **G3 — checksums.** Every asset carries `file:checksum` (sha256 multihash, `1220` prefix); the script verifies each download against it and deletes a mismatch.
- **G4 / AC2 — script-emitted tables.** The summarize stage writes `summary_groups.md` (kable) that the note includes verbatim, and a `summary_bulk_reconcile.csv` row against the #9 BULK CSV; derived figures (`overstatement_factor`, `ff06_over_ff02`, `ratio_2018_2023`) are columns, not prose arithmetic. (Round 2 of code-check changed `overstatement_factor` from `100 / pct_sustained`, a rounded input, to `changed_ha / sustained_ha`.)
- **A1 — Q2 derivation confirmed** against `break_class_scan()`: `n_before == idx`, `n_after == n - idx`, `break_year == years[idx + 1]`, so for the consecutive 2017-2023 series `n_before == 1` is exactly `break_year == 2018` and `n_after == 1` exactly `break_year == 2023`. The script asserts the year set and equal valid-cell counts across years.
- **A2 — producer-path confound.** necr and kotl COGs were cut from a gdalcubes NetCDF cube (floodplains#83; stray `NC_GLOBAL`/`NETCDF_DIM` tags remain, no band scale/offset), bulk and lnth were not. Values read identically; if necr/kotl differ from bulk/lnth the note must name this.
- **A4 — scale.** kotl is 204.5M cells with 6.94M valid (BULK 4.11M), so the patch stages scale ~1.7x; `terra::patches()` inside `dft_transition_vectors()` has never run above 192M cells. Expected 7-9 min, 10-14 GB.
- **O1 — issue body edited before the run** (five -> four, PINE excluded, Q3 metric named, download-not-stream stated).
- **O2 — BULK reconciliation.** Published bulk has 4,108,972 valid cells per year against 4,108,901 in the #9 run (71-cell mask difference); totals should agree to < 0.1% and shares to about a point.

## Issue context

## Context

`dft_rast_break_class()` (#9, v0.14.0) was measured on one watershed group. On BULK, of the 4,620 ha the 2017 -> 2023 comparison reports as change, 19.7% is a switch sustained two years each side, 36.4% is a clean switch with 2017 or 2023 the odd year out (922 ha broke in 2018 — 2017 alone differs; 757 ha in 2023), and 44.0% flickers; 3,187 ha flickers while reading stable on the endpoints. Patches carrying the #44 artifact signature had an area-weighted clean-break share of 0.50 against 0.58 for the rest. Evidence in `data-raw/logs/benchmark_break_class/`.

floodplains is rerunning `bulk`, `necr`, `lnth`, `kotl`, `pine` with all seven IO LULC years and stac_floodplains_bc is publishing them (issues linked below). Once those land, this issue runs the temporal leg across all five from the published assets and answers the questions one group cannot.

## Questions

1. **Does the split generalise?** Sustained / endpoint-only / flicker share of the endpoint-changed area per group, against BULK's 19.7 / 36.4 / 44.0. If the sustained share sits near 20% everywhere, the published `transition_2017_2023` layers overstate real change by a factor the reports need to carry; if it varies widely, the variation is the result.
2. **Is 2017 the odd year product-wide?** Area with `n_flips == 1 & n_before == 1` (2018 break) per group, and the same for `n_after == 1` (2023). If 2017 is the outlier in every group, the first year of IO LULC v02 is the noisy one and the honest baseline is 2018 — which changes what "2017 to 2023 change" means in every report.
3. **Landscape or classifier?** Flicker share against floodplain shape (confined vs braided, via the #44 width evidence and the sub-basin geometry) — a share that barely moves across groups is the classifier's.
4. **Are the geometric and temporal legs independent everywhere?** `break_frac` by artifact signature per group, as the BULK patch-group table (`summary_patch_groups.csv`).
5. **What to build next.** Two decisions this run informs, to be filed as their own issues with the numbers behind them: (a) the corrected series the #9 body named — a per-pixel mode filter that keeps a sustained break and overwrites the flicker years — is worth building only if flicker is large everywhere; (b) whether the catalogue's items should carry the temporal evidence (`break_year`, `n_flips` COGs, or a corrected transition) beside the two-epoch transition.

## How

- Read the seven `classified_<year>` COGs per item straight from the published hrefs (`/vsicurl/`, already clipped to the floodplain), classify with `source = "io-lulc"`, run `dft_rast_break_class()`, then `dft_transition_vectors(changes_only = TRUE)` + `dft_transition_artifact()` + per-patch zonal — the BULK script (`data-raw/benchmark_break_class_bulk.R`) minus the fetch. `dft_stac_fetch()` assumes one asset name across items, so this is a `data-raw/` script, not a new source; if it turns out worth keeping, a `stac-floodplains-bc` source is a separate issue.
- One CSV per group in `data-raw/logs/break_class_groups/` plus a `summary_groups.csv` the notes quote from; RSS sampled (BULK's inputs alone are an 8.5-20 GB floor).
- Results as a short note (`inst/notes/` or the archive README), every number derived from the committed CSVs by the committed script (the round-8 lesson on #9).

## Acceptance

- Five groups measured with the same script; the four questions above each answered with a number per group.
- The two follow-up decisions filed as issues (drift and/or stac_floodplains_bc) with the measurements in their bodies, or explicitly closed as "not worth it" with the number that says so.
- Nothing in `R/` changes here unless the run finds a defect; this is analysis.

Relates to #9, #44, #30.

## Blocked on

- Rasters: NewGraphEnvironment/floodplains#79
- Published items: NewGraphEnvironment/stac_floodplains_bc#59


## Errors Encountered

| Error | Resolution |
|-------|------------|

## Code-check rounds (2026-09-05)

| round | findings | inside previous fix? |
|---|---|---|
| 1 | 2 — necr RSS trace sampled the wrapper shell; checksum remedy left a stale `item.json` | — |
| 2 | 6 — two prose ranges disagreed with CSV cells; `overstatement_factor` from a rounded share; hand-typed ratio replaced by a column; guard order; a plan claim | no |
| 3 | 4 — the note said the cube-cut groups do not separate when they are the two lowest on `pct_flicker`, `overstatement_factor`, `stable_flicker_over_changed`, `n_flips_sliver`, `n_flips_wider` and the two highest on `pct_sustained`, `break_frac_all`, `break_frac_other` (not on `pct_endpoint` or `pct_stable_flicker_of_valid`); reconciliation delta from rounded rows; two ratios from rounded areas (all cells verified unchanged from unrounded); a stale formula here | no |

Mechanism behind rounds 2-3: a sentence written from a reading of the emitted table, or a derived cell computed downstream of a display rounding. The verbatim-tables guard covers the tables; the sentences about them were enumerated by round 3 (49 claims, 2 mismatches, both fixed) and the eleven `round()` sites walked (three fixed or recorded).

Accepted after round 3: `ff06_over_ff02` divides `area_km2` rounded to 2 dp and `pct_area_artifact` divides `area_ha` rounded to 1 dp, both written by the per-group stage. Recomputed from the unrounded gpkg areas and `summary_patches.csv`, all eight cells are unchanged (relative effect ~1e-5, none near a rounding boundary). Re-running the four-group batch to carry an unrounded column would move every RSS and timing figure for no change in any reported value; recorded here and in the evidence README instead, to fix in the per-group stage the next time it runs.
| 4 | 3 — the stac_floodplains_bc#67 body carried three `overstatement_factor` cells from the pre-round-2 formula and drift#64 the pre-round-2 "0.5 to 1" range (both issue bodies edited); the "every temporal column" qualifier above; the README's list of post-batch script edits was incomplete | no |

Termination: no round found a defect inside a previous round's fix, but rounds 2-4 each found the same mechanism one artifact further out, so the loop ends by enumeration rather than by a quiet round. Artifacts that carry numbers from `summary_groups.csv`: the note, the evidence README, NEWS, CLAUDE.md, task_plan, findings, issue #62's body (carries only the #9 BULK context figures, unchanged), drift#64, stac_floodplains_bc#67, and the three commit messages (checked by hand: 19.7-31.0, 39.6-48.5, 1.09-1.25, 13.7-16.3 GiB, 100-323 s, 71 cells, all cells of the CSV). The PR body is the one artifact still to be written and will quote the CSV. Cost: four review rounds plus the plan review — five agents, the `karpathy.md` §6 bound.

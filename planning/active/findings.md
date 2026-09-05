# Findings — Temporal QA across watershed groups from the published annual series (#62)

## Plan-mode exploration (2026-09-05)

- Four items carry seven `classified_*` assets: bulk_co_ff04 (EPSG:32609, 14651 x 11552), necr_ch_ff04 (32610, 6288 x 8945), lnth_ch_ff04 (32610, 11212 x 5398), kotl_bt_ff04 (32611, 13437 x 15219). PINE was dropped upstream (floodplains#79 / stac_floodplains_bc#59; tracked in floodplains#76). The issue's "five" is four.
- STAC API `https://images.a11s.one/collections/stac-floodplains-bc/items?limit=10` paginates by `next` links; `page=` is ignored (same 10 items every time).
- Published COGs: ~0.5-1.3 MB, Byte, DEFLATE, nodata 255, palette + RAT (TIFF tag 42112), 512 blocks, overviews, NGE_* provenance tags. `terra::rast()` reads them as non-factor integer (cats NULL; unique = 1,2,4,5,7,8,9,11); `dft_rast_classify(source = "io-lulc")` works unchanged (probed necr 2018).
- `floodplain.gpkg` layers: `<sp>_ff02`, `<sp>_ff04` (1 feature), `<sp>_ff04_by_blue_line_key` (427/244/179 features for bulk/necr/lnth; fields valley, blue_line_key, wsg, species, scenario, gnis_name; EPSG:3005), `<sp>_ff06`, `layer_styles`.
- `R/dft_rast_break_class.R` spills only in-memory inputs to disk; file-backed inputs stack without copying. Reading local COG copies removes the 8.5-20 GB input floor the BULK run carried.
- Published BULK grid (14651 x 11552) differs from the #9 run's fetched grid (16000 x 12000), so BULK is re-measured here and reconciled against `data-raw/logs/benchmark_break_class/summary_change.csv`.
- Machine m1, 64 GB, 1.1 TB free.

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

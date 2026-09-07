# Temporal QA across four watershed groups: does the BULK split generalise? (drift#62)

`dft_rast_break_class()` (#9, v0.14.0) splits the area a two-epoch comparison calls change
into a clean switch sustained at least two years each side, a clean switch where one endpoint
is the odd year out, and flicker. It was measured on one group. This note runs it on every
watershed group whose published annual IO LULC series is complete — `bulk_co_ff04`,
`necr_ch_ff04`, `lnth_ch_ff04`, `kotl_bt_ff04` on stac-floodplains-bc (floodplains#79,
stac_floodplains_bc#59) — straight from the published `classified_2017 … 2023` COGs, with
`data-raw/break_class_groups.R`. PINE, named in the issue, was dropped upstream: its floodplain
predates `flooded` 0.5.0 (floodplains#76).

Every number below is a cell of `data-raw/logs/break_class_groups/summary_groups.csv`, written
by the `summarize` stage of that script from the per-group CSVs it also writes; the tables are
`summary_groups.md` included verbatim, and the script refuses to finish if this file's copy
differs. The README in that directory lists what is committed. "Changed area" means pixels
whose 2017 and 2023 labels differ — what `transition_2017_2023` publishes.

## Answers

**Q1 — the split generalises.** The share of changed area that is a switch sustained two
years each side is 19.7% (bulk), 31.0% (necr), 20.6% (lnth) and 24.7% (kotl). Flicker is the
largest category in every group (39.6-48.5%); an endpoint-only break (29.4-36.4%) is second
in three groups, and in necr the sustained switch (31.0%) edges it (29.4%). So the published two-epoch layer overstates change sustained two years each
side by a factor of 3.2 to 5.1 (`overstatement_factor`), and the variation between groups is
real but bounded: no group has a sustained share above a third. The area that flickers while
reading *stable* on the endpoints — invisible to the two-epoch layer — is 3.2-9.9% of every
floodplain, 0.63 to 0.97 times the changed area itself (`stable_flicker_over_changed`).

**Q2 — 2017 is the odd endpoint more often than 2023, in every group, by a modest margin.**
Breaks dated 2018 (2017 alone differs) exceed breaks dated 2023 (2023 alone differs) in all
four, with a ratio of 1.09 (kotl) to 1.25 (necr). As a share of the changed area a 2018 break is
16.3-20.0% and a 2023 break 13.1-16.4%. Clouds do not explain it: IO LULC code 10 appears in
2017 only in bulk (280 cells, 2.8 ha of a 925.7 ha 2018-break area) and lnth (62 cells) and
nowhere in 2017 for necr or kotl. The honest reading is that *both* endpoints inflate the
two-epoch layer — an endpoint break has one year of evidence on one side by construction —
and 2017 somewhat more than 2023. That argues for reporting the sustained share beside any
2017-2023 figure rather than for moving the baseline to 2018, which would trade a 2017
odd-year problem for a 2018 one.

**Q3 — mostly classifier.** Confinement is not a field in the data; the proxies are how much
the floodplain widens as the flood factor rises (`ff06_over_ff02`, 1.081 for the wide kotl to
1.264 for lnth) and the ff04 effective width `2A/P` (166.5 m to 423.2 m — perimeter-dominated
on these fragmented floodplains, so the perimeter and polygon count sit beside it). Across a
2.5x range of width the flicker share moves 9 points (39.6-48.5%) with no monotone
relationship: the widest group (kotl) is in the middle, and the two groups with near-identical
width (necr 186.7 m, lnth 196.4 m) have the lowest and highest flicker shares. Within every
group the #44 slivers flicker more than wider patches (`n_flips_sliver` 2.03-2.28 against
`n_flips_wider` 1.83-2.10), so the edge effect is universal too. With four groups there is no
test; the four rows are the answer.

**Q4 — the geometric and temporal legs are independent to nearly independent everywhere.**
Area-weighted clean-break share of artifact-signature patches against the rest: 0.494 vs 0.575
(bulk), 0.490 vs 0.621 (necr), 0.518 vs 0.515 (lnth), 0.550 vs 0.583 (kotl). Artifact-shaped
patches are somewhat less likely to be a clean break in three groups and indistinguishable in
lnth; the artifact signature covers 13.1-24.5% of the changed area. Neither leg predicts the
other well enough to stand in for it — a patch needs both tags.

**Reconciliation.** BULK re-measured on the published grid (14651 x 11552) against the #9 run
on the grid `dft_stac_fetch()` tiled from Planetary Computer (16000 x 12000): 71 more valid
cells, 4.62 ha more changed area, and the three shares within 0.03 of a point
(`summary_bulk_reconcile.csv`). The published pipeline reproduces the fetched one.

## What this does and does not support

- Four groups, all whole-WSG areas with a single sub-basin, all IO LULC v02 at 10 m. necr and
  kotl were cut from a gdalcubes cube upstream and bulk and lnth were not (floodplains#83). The
  pixel values read identically, but the two cube-cut groups are also the two that flicker
  least: `pct_unsettled` 39.6 / 42.3 against 44.0 / 48.5, `pct_sustained` 31.0 / 24.7 against
  19.7 / 20.6, and they are the two with no 2017 clouds. With four groups that is one correlated
  signal, and producer path cannot be separated from landscape here — a reason to read the
  between-group spread in Q1 and Q3 as bounded rather than explained, and a comparison for
  floodplains#83 to close when the two paths are run on one group.
- Nothing here is thresholded differently from #9: "sustained" is `n_flips == 1 &
  pmin(n_before, n_after) >= 2`.
- The follow-up decisions (Q5) are filed as their own issues with these numbers in their bodies:
  a corrected annual series in drift (#64 — flicker is the largest category everywhere, so the
  run-length filter the #9 body named is worth building), and `break_n_flips` / `break_year`
  assets beside `transition_2017_2023` in the catalogue (stac_floodplains_bc#67 — the two-epoch
  layer overstates sustained change 3.2-5.1x in every group and a consumer cannot see it).
- These results are stated for a reader who consumes the published products and does not use the
  package in the article
  [What a Land-Cover Change Figure Is Made Of](https://newgraphenvironment.github.io/drift/articles/temporal-composition.html)
  (#66), which uses BULK as the worked example and the other three groups as the test of
  generality. Its figures and tables are built from `inst/extdata/temporal-composition/`, written
  by the same script as the tables below.

## Tables (generated — do not edit here)


## Q1: split of the 2017 -> 2023 changed area

|group | valid_ha| changed_ha| pct_changed_of_valid| pct_sustained| pct_endpoint| pct_unsettled| overstatement_factor| stable_flicker_ha| pct_stable_flicker_of_valid| stable_flicker_over_changed|
|:-----|--------:|----------:|--------------------:|-------------:|------------:|-------------:|--------------------:|-----------------:|---------------------------:|---------------------------:|
|bulk  |  41089.7|     4625.0|                11.26|          19.7|         36.4|          44.0|                 5.09|            3186.5|                        7.76|                        0.69|
|necr  |  41838.1|     5779.4|                13.81|          31.0|         29.4|          39.6|                 3.23|            3828.3|                        9.15|                        0.66|
|lnth  |  16001.8|     1629.7|                10.18|          20.6|         31.0|          48.5|                 4.86|            1576.7|                        9.85|                        0.97|
|kotl  |  69377.6|     3537.8|                 5.10|          24.7|         33.1|          42.3|                 4.06|            2235.5|                        3.22|                        0.63|

## Q2: endpoint-only breaks by year

|group | break_2018_ha| pct_break_2018| break_2023_ha| pct_break_2023| ratio_2018_2023| cloud_cells_2017| cloud_cells_other|
|:-----|-------------:|--------------:|-------------:|--------------:|---------------:|----------------:|-----------------:|
|bulk  |         925.7|           20.0|         757.0|           16.4|            1.22|              280|                 0|
|necr  |         942.3|           16.3|         756.6|           13.1|            1.25|                0|                 0|
|lnth  |         272.6|           16.7|         232.1|           14.2|            1.17|               62|                 0|
|kotl  |         610.6|           17.3|         559.4|           15.8|            1.09|                0|                 5|

## Q3: floodplain shape against the unsettled share

|group | ff02_km2| ff04_km2| ff06_km2| ff06_over_ff02| ff04_width_m| ff04_perimeter_km| ff04_n_polygons| pct_unsettled| pct_sustained| n_flips_sliver| n_flips_wider|
|:-----|--------:|--------:|--------:|--------------:|------------:|-----------------:|---------------:|-------------:|-------------:|--------------:|-------------:|
|bulk  |   344.62|   386.42|   414.46|          1.203|        166.5|            4642.6|            5609|          44.0|          19.7|           2.28|          1.94|
|necr  |   354.39|   396.26|   432.18|          1.220|        186.7|            4245.6|            1718|          39.6|          31.0|           2.20|          1.83|
|lnth  |   136.25|   151.88|   172.24|          1.264|        196.4|            1546.5|            1761|          48.5|          20.6|           2.23|          2.10|
|kotl  |   636.82|   675.56|   688.56|          1.081|        423.2|            3192.4|            7226|          42.3|          24.7|           2.03|          1.92|

## Q4: temporal evidence by geometric signature (area-weighted clean-break share)

|group | n_patches| break_frac_all| break_frac_artifact| break_frac_other| pct_area_artifact| break_frac_sliver| break_frac_wider|
|:-----|---------:|--------------:|-------------------:|----------------:|-----------------:|-----------------:|----------------:|
|bulk  |     21701|          0.560|               0.494|            0.575|              17.8|             0.464|            0.590|
|necr  |     21990|          0.604|               0.490|            0.621|              13.1|             0.478|            0.629|
|lnth  |     12434|          0.515|               0.518|            0.515|              24.5|             0.478|            0.532|
|kotl  |     17042|          0.577|               0.550|            0.583|              17.8|             0.544|            0.588|

## Run

|group |crs        |     ncell| wall_s| break_class_s| peak_rss_gib|
|:-----|:----------|---------:|------:|-------------:|------------:|
|bulk  |EPSG:32609 | 169248352|  312.3|          61.2|         15.4|
|necr  |EPSG:32610 |  56246160|  137.9|          22.3|         14.2|
|lnth  |EPSG:32610 |  60522376|   99.9|          21.1|         13.7|
|kotl  |EPSG:32611 | 204497703|  322.6|          72.2|         16.3|

## Run

`bash data-raw/break_class_groups-run.sh bulk kotl lnth necr` then
`Rscript data-raw/break_class_groups.R summarize`. Peak RSS was 13.7-16.3 GiB on a 64 GB machine
for grids from 56M to 204M cells — terra sizing to available RAM, not a per-group requirement.
The COGs are downloaded once and verified against each asset's `file:checksum`.

# Does dated disturbance corroborate the temporal QA? (drift#67)

[`temporal-qa-groups.md`](temporal-qa-groups.md) (#62) split the area a two-epoch comparison
calls change into a clean switch sustained two years each side, a clean switch resting on one
endpoint year, and flicker, across four watershed groups. Every leg of that is **internal to the
imagery**: it says whether the labels settled, never whether anything happened on the ground.

`floodplains` tags each published change patch with dated provincial fire and harvest from DataBC.
Those dates come from a source with no relationship to the classifier, so comparing them against
`dft_rast_break_class()`'s `break_year` is the first external check the method has had.

Every number below is a cell of a CSV under `data-raw/logs/disturbance_compare/`, written by
`data-raw/disturbance_compare.R`; the tables at the bottom are `summary_groups.md` included
verbatim, and the script refuses to finish if this file's copy differs. Run with
`bash data-raw/disturbance_compare-run.sh bulk necr lnth kotl` then
`Rscript data-raw/disturbance_compare.R summarize`.

**No database is involved.** The tags are already published: `transition_vector.gpkg` in all four
items carries `in_fire`, `fire_year`, `fire_number`, `in_harvest` and
`harvest_start_year_calendar`. The one input that is *not* published is the sub-basin polygon used
to reproduce the clip (`floodplains/data/<group>/subbasins.gpkg`, gitignored there); its path and
md5 are recorded in each `group_meta.csv`, alongside a `script_sha` that `summarize` requires to
be identical across the four groups.

## Answers

**Q1 — the two BULK totals were never in conflict; they measure different populations.**
The published `transition_vector.gpkg` is drift's own change layer after two steps floodplains
applies and #62 did not: a **1 ha class-agnostic sieve**
(`dft_rast_transition(patch_area_min = 10000)`, which runs `terra::patches()` on a changed mask
that ignores class, so a mixed-class blob survives whole) and a **clip to the sub-basin polygon**
with `area_ha` recomputed from geometry. Re-running both functions from the current tree — both
files byte-identical to v0.13.0, the version that published the items — reproduces the published
layer in every group: **0 of 53 / 44 / 41 / 46 transition classes differ in count, max |Δha|
0.00**. On BULK that is 21,701 patches / 4,625.0 ha → 7,191 / 3,639.7 → 7,161 / 3,627.2, against
a published 7,161 / 3,627.2.

The sentence a report can quote: *the published transition layer and drift's change patches are
the same data at two filtering stages, and the 1.28x area ratio on BULK is the 1 ha sieve (985.3
ha of it) plus the sub-basin clip (12.5 ha).* The clip is not uniformly small — 12.5 ha on bulk
against **130.5 ha on kotl**, whose floodplain reaches further outside its sub-basin.

Two corrections to figures quoted elsewhere. The item property `gross_loss_ha` (1,565.1 on BULK)
is `from_class = 'Trees'` and **includes Trees → Water** (136.8 ha over 457 patches); excluding it
the figure is 1,428.2 ha. And 7,161 is the whole published layer, not a tree-loss subset — the
tree-loss subset is 2,101 patches.

**Q2 — break year agrees with the disturbance date, and the mode is +1, exactly the compositing
lag predicted in advance.** Pooled over the disturbance years that can discriminate at all:

| source | tagged | with a clean break | at lag 0 or +1 | of those that broke | of all tagged |
|---|---|---|---|---|---|
| fire | 150 (5 events) | 123 | 106 | **86.2%** | 70.7% |
| harvest | 308 | 250 | 180 | **72.0%** | 58.4% |

Offsets: fire `0 → 37, +1 → 69, +2 → 8`; harvest `0 → 75, +1 → 105, +2 → 22`.

**Both denominators are given because the rate is conditioned on its own outcome.** 27 fire and
58 harvest tagged patches produced no clean break cell at all and so contribute no offset;
quoting only the 86.2% / 72.0% would read as an unconditional agreement rate, which it is not.
Lag {0, +1} was **pre-registered** as agreement before the distribution was seen — IO LULC is an
annual composite and `harvest_start_year_calendar` is a *start*, so a stand cut late in a year
need not change class until the next composite. That the observed mode is +1 rather than 0 is the
prediction landing, not a fitted result.

**What this cannot support.** Fire is **five events across two groups** — necr's two 2018 fires
and kotl's 2020, 2021 and 2022 fires — so it is a case series, and 123 patches inside five fire
perimeters are not 123 independent observations. Harvest publishes no opening id, so its events
cannot be counted at all and the effective n is unknown and well below 250. **No rate and no
p-value is claimable from either.** What is claimable is that where a dated disturbance can
produce a datable break, drift's `break_year` lands on it or one year later for most of the
affected area.

Which disturbance years can discriminate is itself derived, not assumed. A break at index `idx`
has `break_year = years[idx+1]` and is *sustained* only for `pmin(idx, n-idx) >= 2`, i.e.
`break_year ∈ 2019..2022`; a disturbance in year `Y` reaches `break_year` `Y` or `Y+1`. So 2017
and 2023 discriminate nothing, 2018 and 2022 are **partial** (one of their two reachable years is
sustained), and 2019–2021 are **full**. A first pass used a flat `2019:2022` window and was wrong
in both directions — it excluded 2018, which holds the largest fire signal in the dataset (necr's
2018 fires put 414.7 ha at `break_year` 2019, a sustained break), and called 2022 full. The error
was caught by reading the output, not by review.

**Q3 — flicker is markedly LOWER in disturbed patches, which does not support the succession
reading.** Area-weighted flicker fraction in the `wider` stratum (excluding #44 slivers),
harvest-touching against patches matching no disturbance layer:

| group | harvest-touching | fire-touching | untagged residual |
|---|---|---|---|
| bulk | 0.205 | 0.136 | 0.450 |
| necr | 0.279 | 0.197 | 0.412 |
| lnth | 0.068 | 0.396 | 0.475 |
| kotl | 0.072 | 0.305 | 0.440 |

The hypothesis was that a cutblock genuinely passes through bare ground, rangeland and young
trees, so flicker inside one might be real succession imperfectly tracked. It is the other way
round: **dated disturbance produces a comparatively clean, well-dated switch** (`break_frac` 0.55
to 0.93), and the flicker #62 measured lives overwhelmingly in the residual that matches no
disturbance layer at all. That is a point in favour of reading flicker as classifier noise.

Four limits on it, and the second is the one that could change the sign:

- **The stratification is load-bearing.** In the `sliver` stratum the gap shrinks sharply and in
  places nearly closes. `in_harvest` is `st_intersects` — **touching, not containment** — and
  change concentrates at cutblock edges, which are exactly the sliver population #62 measured as
  the highest-flicker one. Quoting the unstratified number alone would overstate the effect.
- **The control group contains old cutblocks.** `config/disturbance.yml` loads the cutblock table
  filtered `HARVEST_START_YEAR_CALENDAR >= 2017`, so pre-2017 harvest is *absent from the
  database*, not merely untagged. The comparison is against a residual that contains old harvest,
  not against undisturbed floodplain — and mid-succession regrowth from a 2010 cutblock is
  precisely the signal the hypothesis was about.
- **No containment measure is available.** No overlap fraction is published, so "how much of this
  patch is inside the cutblock" cannot be asked from the published attributes. That needs the
  cutblock polygons, i.e. the database.
- **The residual is patches that were offered a tag and matched none**, not simply patches
  without one. The zone clip drops patches from the published layer entirely (30 / 18 / 9 / 219
  on bulk / necr / lnth / kotl), and those were never evaluated against fire or harvest; they are
  excluded rather than counted as untagged. `patches_not_tag_evaluated` in `join_audit.csv`
  carries the count.

## What this does and does not support

- Four groups, all whole-WSG areas with a single sub-basin, all IO LULC v02 at 10 m — the same
  population as #62, with the same caveat that producer path cannot be separated from landscape
  across four rows.
- The reconciliation (Q1) is exact and is the strongest result here: it is a reproduction, not a
  correlation, and it closes the "one fact derived twice" problem that blocked #66.
- Q2 and Q3 rest on a few hundred patches inside a handful of disturbance events. They are
  consistent across groups and in the direction the method predicts, which is worth more than any
  single group's number, and they are not a hypothesis test.
- Q2 and #62's sustained/endpoint split are **not independent evidence**: the split *is*
  `break_year` thresholded, so agreement on dates and the sustained share are one measurement
  read two ways. Do not report them as two corroborating legs.

## Measurement hygiene

The join is by `patch_id`, drift's own global key — `dft_transition_vectors()` assigns it before
the zone intersection, so the published ids are drift's with the clip having removed some.
Rasterizing the published polygons instead would drop sub-cell fragments, a perimeter-to-area
loss concentrated in slivers, which are the high-flicker population — it would have manufactured
Q3's result. `join_audit.csv` is the evidence the join is lossless: 0 patches with no cells, 0
published ids unmatched, and a per-patch `|area_ha − n_cells × cell_ha|` of 4e-11 to 2e-10.

Flicker and break fractions are cell fractions over the **unclipped** patch, weighted by the
unclipped area and thresholded on it — one footprint for measurand, weight and stratum. The
clipped area is published beside it as `area_ha_eval`, and the difference is bounded by
`patches_trimmed_by_clip` / `trimmed_ha`: 11 / 2.78 ha (bulk), 2 / 8.03 (necr), 4 / 2.91 (lnth),
30 / 11.17 (kotl).

## Run

Peak RSS 13.9 / 13.7 / 17.3 / 16.9 GiB (lnth / necr / bulk / kotl) on a 64 GB machine, wall
162 / 332 / 535 / 654 s, for grids from 56M to 204M cells. `dft_rast_transition()` holds six to
seven full-grid rasters because its sieve intermediates take no `filename =` — filed as #69; the
two heavy stages here are deliberately separated by `rm()` + `gc()` so they do not overlap.

## Tables (generated — do not edit here)

## Reconciliation: drift's change patches against the published transition layer

|group | drift_patches| drift_ha| pub_patches| pub_ha| repro_patches| repro_ha| sieve_ha| clip_ha| n_classes| n_classes_differ| max_abs_d_ha|reproduced |
|:-----|-------------:|--------:|-----------:|------:|-------------:|--------:|--------:|-------:|---------:|----------------:|------------:|:----------|
|bulk  |         21701|   4625.0|        7161| 3627.2|          7161|   3627.2|    985.3|    12.5|        53|                0|            0|TRUE       |
|necr  |         21990|   5779.4|        5692| 4712.6|          5692|   4712.6|   1049.4|    17.4|        44|                0|            0|TRUE       |
|lnth  |         12434|   1629.7|        2753| 1148.5|          2753|   1148.5|    477.7|     3.5|        41|                0|            0|TRUE       |
|kotl  |         17042|   3537.8|        4929| 2757.8|          4929|   2757.8|    649.5|   130.5|        46|                0|            0|TRUE       |

## Discriminating sample: disturbance years whose reachable break years are sustained

|group | fire_patches_full| fire_patches_partial| fire_ha_disc| fire_events_disc| harv_patches_full| harv_patches_partial| harv_ha_disc|
|:-----|-----------------:|--------------------:|------------:|----------------:|-----------------:|--------------------:|------------:|
|bulk  |                 0|                    0|          0.0|                0|                52|                   36|        303.0|
|necr  |                 0|                   87|        457.4|                2|                79|                   85|        583.6|
|lnth  |                 0|                    0|          0.0|                0|                12|                    1|         26.6|
|kotl  |                11|                   52|         20.0|                3|                32|                   11|        172.5|

## Agreement at lag 0 or +1, discriminating disturbance years only (full + partial)

|group |source  | n_tagged| n_with_break| n_lag01| pct_lag01_of_break| pct_lag01_of_tagged|
|:-----|:-------|--------:|------------:|-------:|------------------:|-------------------:|
|bulk  |fire    |        0|            0|       0|                 NA|                  NA|
|bulk  |harvest |       88|           70|      55|               78.6|                62.5|
|necr  |fire    |       87|           77|      68|               88.3|                78.2|
|necr  |harvest |      164|          129|      91|               70.5|                55.5|
|lnth  |fire    |        0|            0|       0|                 NA|                  NA|
|lnth  |harvest |       13|           12|       8|               66.7|                61.5|
|kotl  |fire    |       63|           46|      38|               82.6|                60.3|
|kotl  |harvest |       43|           39|      26|               66.7|                60.5|

## Flicker: harvest-touching against the untagged residual, by geometric stratum

|stratum   |population        | n_patches| area_ha_unclipped| area_ha_eval| flicker_frac_area_wtd| break_frac_area_wtd|group |
|:---------|:-----------------|---------:|-----------------:|------------:|---------------------:|-------------------:|:-----|
|all       |harvest_touching  |       120|             525.3|        525.3|                 0.207|               0.793|bulk  |
|all       |fire_touching     |        35|              69.9|         69.9|                 0.143|               0.857|bulk  |
|all       |untagged_residual |      7008|            3071.2|       3068.4|                 0.475|               0.525|bulk  |
|sliver    |harvest_touching  |        44|               4.5|          4.5|                 0.362|               0.638|bulk  |
|sliver    |fire_touching     |        19|               1.2|          1.2|                 0.554|               0.446|bulk  |
|sliver    |untagged_residual |      5700|             412.8|        412.6|                 0.634|               0.366|bulk  |
|wider     |harvest_touching  |        76|             520.8|        520.8|                 0.205|               0.795|bulk  |
|wider     |fire_touching     |        16|              68.7|         68.7|                 0.136|               0.864|bulk  |
|wider     |untagged_residual |      1308|            2658.4|       2655.8|                 0.450|               0.550|bulk  |
|ge_0.5_ha |harvest_touching  |        70|             518.8|        518.8|                 0.204|               0.796|bulk  |
|ge_0.5_ha |fire_touching     |        15|              68.2|         68.2|                 0.130|               0.870|bulk  |
|ge_0.5_ha |untagged_residual |      1030|            2625.9|       2623.6|                 0.441|               0.559|bulk  |
|all       |harvest_touching  |       193|             719.9|        719.9|                 0.280|               0.720|necr  |
|all       |fire_touching     |       189|             589.4|        582.5|                 0.201|               0.799|necr  |
|all       |untagged_residual |      5323|            3509.7|       3508.6|                 0.429|               0.571|necr  |
|sliver    |harvest_touching  |        49|               3.2|          3.2|                 0.545|               0.455|necr  |
|sliver    |fire_touching     |        98|               6.1|          6.1|                 0.557|               0.443|necr  |
|sliver    |untagged_residual |      4106|             290.3|        289.2|                 0.615|               0.385|necr  |
|wider     |harvest_touching  |       144|             716.7|        716.7|                 0.279|               0.721|necr  |
|wider     |fire_touching     |        91|             583.3|        576.4|                 0.197|               0.803|necr  |
|wider     |untagged_residual |      1217|            3219.4|       3219.4|                 0.412|               0.588|necr  |
|ge_0.5_ha |harvest_touching  |       135|             713.7|        713.7|                 0.278|               0.722|necr  |
|ge_0.5_ha |fire_touching     |        85|             581.6|        574.6|                 0.196|               0.804|necr  |
|ge_0.5_ha |untagged_residual |      1012|            3188.8|       3187.7|                 0.407|               0.593|necr  |
|all       |harvest_touching  |        15|              30.3|         30.3|                 0.078|               0.922|lnth  |
|all       |fire_touching     |         7|               9.0|          9.0|                 0.404|               0.596|lnth  |
|all       |untagged_residual |      2731|            1112.1|       1109.2|                 0.495|               0.505|lnth  |
|sliver    |harvest_touching  |         3|               0.7|          0.7|                 0.521|               0.479|lnth  |
|sliver    |fire_touching     |         4|               0.1|          0.1|                 1.000|               0.000|lnth  |
|sliver    |untagged_residual |      2186|             146.4|        146.4|                 0.631|               0.369|lnth  |
|wider     |harvest_touching  |        12|              29.6|         29.6|                 0.068|               0.932|lnth  |
|wider     |fire_touching     |         3|               8.9|          8.9|                 0.396|               0.604|lnth  |
|wider     |untagged_residual |       545|             965.7|        962.8|                 0.475|               0.525|lnth  |
|ge_0.5_ha |harvest_touching  |        13|              30.1|         30.1|                 0.073|               0.927|lnth  |
|ge_0.5_ha |fire_touching     |         3|               8.9|          8.9|                 0.396|               0.604|lnth  |
|ge_0.5_ha |untagged_residual |       411|             935.2|        932.3|                 0.469|               0.531|lnth  |
|all       |harvest_touching  |        44|             172.8|        172.8|                 0.074|               0.926|kotl  |
|all       |fire_touching     |        91|              28.8|         28.8|                 0.336|               0.664|kotl  |
|all       |untagged_residual |      4794|            2567.4|       2556.2|                 0.453|               0.547|kotl  |
|sliver    |harvest_touching  |        15|               1.6|          1.6|                 0.297|               0.703|kotl  |
|sliver    |fire_touching     |        72|               7.1|          7.1|                 0.432|               0.568|kotl  |
|sliver    |untagged_residual |      4006|             336.0|        334.6|                 0.543|               0.457|kotl  |
|wider     |harvest_touching  |        29|             171.2|        171.2|                 0.072|               0.928|kotl  |
|wider     |fire_touching     |        19|              21.7|         21.7|                 0.305|               0.695|kotl  |
|wider     |untagged_residual |       788|            2231.4|       2221.6|                 0.440|               0.560|kotl  |
|ge_0.5_ha |harvest_touching  |        25|             169.8|        169.8|                 0.070|               0.930|kotl  |
|ge_0.5_ha |fire_touching     |        15|              21.4|         21.4|                 0.296|               0.704|kotl  |
|ge_0.5_ha |untagged_residual |       673|            2253.4|       2242.9|                 0.435|               0.565|kotl  |

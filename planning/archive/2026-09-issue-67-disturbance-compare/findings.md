# Findings — Corroborate the temporal QA against dated disturbance (#67)

## Phase 0 verification: the snapshot, discharged

The issue body carries a snapshot of how `floodplains` tags disturbance, flagged as supplied
2026-09-06 and expected to drift. Verified 2026-09-06 against the published catalogue and the
`floodplains` source. Commands are given so each point is re-checkable.

### All four items carry the disturbance tags — no database needed

```bash
ogrinfo -so <item>/transition_vector.gpkg transition
```

`bulk_co_ff04`, `necr_ch_ff04`, `lnth_ch_ff04`, `kotl_bt_ff04` each hold, in layer `transition`:
`patch_id`, `transition`, `area_ha`, `name_basin`, `from_class`, `to_class`, `in_fire`, `fire_year`,
`fire_number`, `in_harvest`, `harvest_start_year_calendar`, `wsg`, `species`, `scenario`.

**No database, no `config/disturbance.yml`, no `fwapg` connection is required.** The issue's Phase 0
question is answered: the published catalogue is sufficient, and it generalises to all four.

### Published BULK layer

| | |
|---|---|
| features | 7,161 |
| total change | 3,627.2 ha |
| distinct `name_basin` | 1 |
| distinct transition classes | 53 |
| min `area_ha` | 0.00786 (78.6 m² — sub-cell at 10 m, so post-intersection) |
| geometry types | MULTIPOLYGON only (no GEOMETRYCOLLECTION) |

Feature counts for the other three: necr 5,692, lnth 2,753, kotl 4,929.

### Correction to the snapshot's tree-loss figure

The snapshot reports "1,565.1 ha gross floodplain tree loss". Measured, that is
`sum(area_ha) WHERE from_class = 'Trees'` — **it includes Trees → Water** (136.8 ha, 457 patches).
Excluding Trees → Water it is 1,428.2 ha over 1,644 patches. And 7,161 is the **whole layer**, not a
tree-loss subset; the tree-loss subset is 2,101 patches.

This is a correction to the issue body, not a discrepancy between pipelines. Note the drift side
reports Trees → Water as 276.8 ha against the published 136.8 ha, which is itself a reconciliation
datum for Phase 1.

## [R] `patch_id` is drift's own GLOBAL key, not a per-sub-basin one

`R/dft_transition_vectors.R:153` assigns `polys_sf$patch_id <- seq_len(nrow(polys_sf))` and the zone
intersection is at `:171` — **the id is assigned before the clip**. Measured across all four
published layers:

| group | features | distinct `patch_id` | max `patch_id` |
|---|---|---|---|
| bulk | 7,161 | 7,161 | 7,191 |
| necr | 5,692 | 5,692 | 5,709 |
| lnth | 2,753 | 2,753 | 2,761 |
| kotl | 4,929 | 4,929 | 5,016 |

No duplicates anywhere, and `max > n` in every group. That is the signature of a global sequence
with some ids removed by the zone clip — not per-basin numbering, which would repeat ids.

Two consequences:

1. **A direct column join on `patch_id` works.** Rasterizing the published polygons is unnecessary,
   and is actively worse (see below).
2. `max(patch_id) − n` is a free prediction of patches dropped entirely by the zone clip: bulk 30,
   necr 17, lnth 8, kotl 87.

The `floodplains` comment at `scripts/floodplain_lcc/03_lulc_classify.R:276-281` states the cause as
"dft_transition_vectors numbers patches within each sub-basin". That is wrong; its *conclusion* (ids
can repeat, do not group on `patch_id` alone) is right, arriving via splitting rather than numbering.

## [R] The sustained/endpoint split IS `break_year` — they are one measurement

`R/dft_rast_break_class.R:324-326`:

```r
break_year[one] <- years[idx[one] + 1L]
n_before[one]   <- idx[one]
n_after[one]    <- n - idx[one]
```

and the #62 category function is `pmin(n_before, n_after) >= 2` (`break_class_groups.R:101`). With
`years = 2017:2023` (n = 7):

- sustained ⟺ `idx ∈ [2, 5]` ⟺ **`break_year ∈ 2019..2022`**
- endpoint ⟺ `idx ∈ {1, 6}` ⟺ **`break_year ∈ {2018, 2023}`**

Deterministic, not statistical. Confirmed against #62's committed evidence for BULK:
`break_2018 + break_2023 = 925.7 + 757.0 = 1,682.7` ha against `pct_endpoint 36.4% × 4,625.0 =
1,683.5` ha.

**This is the finding that reshapes Phase 2**, because it means the two questions #62 and #67 ask
are one measurement, not two independent ones. Which disturbance *years* can therefore
discriminate is a separate derivation, and getting it wrong is easy — see the next section, where
the obvious reading of this paragraph turned out to be wrong in both directions.

## The discriminating sample — CORRECTED, and the first version was wrong both ways

A first pass took "only 2019-2022 discriminates" from the plan review and used it as a flat
window. **That is wrong in both directions, and the data caught it, not review.**

A disturbance in calendar year `Y` reaches `break_year` `Y` or `Y+1` (IO LULC is an annual
composite; `harvest_start_year_calendar` is a *start*). It discriminates the disturbance
hypothesis from endpoint noise only insofar as those reachable break years are *sustained*
ones — which is a three-level answer, not a window. Derived from `years`, not typed:

| disturbance year | reachable `break_year` | sustained? | classification |
|---|---|---|---|
| 2017 | {2018} | no | **none** |
| 2018 | {2018, 2019} | no, yes | **partial** |
| 2019 | {2019, 2020} | yes, yes | **full** |
| 2020 | {2020, 2021} | yes, yes | **full** |
| 2021 | {2021, 2022} | yes, yes | **full** |
| 2022 | {2022, 2023} | yes, no | **partial** |
| 2023 | {2023} | no | **none** |

The flat window excluded **2018**, which is partial and holds the largest fire signal in the
whole dataset — necr's 2018 fire put **414.7 ha at `break_year` 2019, a sustained break** —
and it called **2022** full when it is partial.

The tell was in the output: a 2018 fire showing 33 patches at offset +1 in a year the script
had labelled non-discriminating. The classification is now computed by `discriminates()` from
`years`, so a change to the series moves it.

Corrected sample. Harvest, full (2019-2021): bulk 52, necr 79, lnth 12, kotl 32 = **175
patches**; partial (2018, 2022): bulk 36, necr 85, lnth 1, kotl 11 = **133**. Fire, full:
11 patches over 2 fires (kotl 2020, 2021); partial: 139 patches over 3 fires (necr 2018,
kotl 2022). So fire remains a case series — five events in two groups — and harvest is 308
patches with no event id, so patches within one cutblock are not independent.

## [R] `in_fire` / `in_harvest` is `st_intersects` — touching, not containment

`floodplains/scripts/floodplain_lcc/fp_disturbance.R:59`:

```r
patches[[in_col]] <- lengths(sf::st_intersects(patches, poly)) > 0
```

TRUE for a boundary-only touch. `config/disturbance.yml` carries only
`[harvest_start_year_calendar]` and `[fire_year, fire_number]` — **no overlap area or fraction is
published**.

Two consequences for Phase 3:

1. The claim must be "patches **touching** a cutblock", never "inside". A containment measure needs
   the cutblock polygons, i.e. the database — out of scope.
2. The error is adversarial, not random. Change concentrates at cutblock *edges* (the
   harvest/retention boundary is where a classifier flips), and #62 measured slivers flickering more
   than wider patches (`n_flips_area_wtd` 2.28 vs 1.94 on bulk). So `in_harvest = TRUE` is enriched
   in exactly the high-flicker population, and an unstratified Q3 result is confounded with patch
   shape **by construction**. Stratify on `flag_sliver` and `area_ha >= 0.5`.

Also note `fp_disturbance.R:68-71`: `group_by(patch_id)` then `match()` returns the first hit, so on
a multi-sub-basin area every fragment of a straddling patch carries the year of the largest overlap
across *all* fragments. Bounded (fragments are the same patch) and not reachable here — all four
groups have one sub-basin — but worth recording so it is not discovered as an anomaly.

## [R] The untagged residual contains old cutblocks

`config/disturbance.yml` records that the cutblock table was loaded filtered
`HARVEST_START_YEAR_CALENDAR >= 2017`, and `03_lulc_classify.R:222` further windows the tag to the
scenario's `change_interval`. So **pre-2017 cutblocks are absent from the database, not merely
untagged**. The "matches no disturbance layer" residual therefore contains old cutblocks — which is
the succession signal Phase 3 is testing for, sitting in the control group. Without stating this the
Q3 result is uninterpretable in either direction.

## Reconciliation: the mechanisms, and the result

`floodplains/scripts/floodplain_lcc/03_lulc_classify.R` line 65 sets `patch_min_m2 <- 10000` and
line 120-122 passes it as `patch_area_min` to `dft_rast_transition()`; line 200-205 calls
`dft_transition_vectors(zones = subbasins, zone_col = "name_basin", changes_only = TRUE)`; line 213
recomputes `area_ha` from geometry post-intersection.

Reading drift's two functions, the count and the area move in **opposite** directions:

| # | mechanism | source | effect |
|---|---|---|---|
| 1 | sieve on a **class-agnostic** changed mask, 1 ha | `R/dft_rast_transition.R:113-114` | drops count and area |
| 2 | vectorize into **same-valued** components | `R/dft_transition_vectors.R:115` | a surviving mixed blob re-splits — raises count, area unchanged |
| 3 | zone clip trims patch geometry | `R/dft_transition_vectors.R:171` | drops area, count unchanged |
| 4 | zone clip drops patches entirely | same | drops count (predicted: bulk 30) |
| 5 | zone clip splits straddling patches | same | raises count — asserted zero here, one basin each |

Mechanism 2 is why 3,627.2 ha yields 7,161 polygons where a per-class 0.5 ha filter on drift's own
output gives 1,471 patches / 3,421.6 ha (#62 `summary_patch_groups.csv`). A reconciliation table
reporting only the total would miss it.

## [R] `terra::zonal()` is a memory trap outside its fast path

terra 1.9.34's `zonal()` C++ fast path is gated on `fun %in% c("max","min","mean","sum","notNA","isNA")`.
Anything else — `"modal"`, a quantile, an R closure — falls back to
`as.data.frame(c(x, z), na.rm = FALSE)` then `stats::aggregate()`. On BULK that is a 169,248,352-row
data frame per layer; on KOTL 204,497,703. #62 already peaks at 15.4 / 16.3 GiB.

So the natural answer to "use modal instead of mean for `break_year`" is a silent OOM.

**Use `terra::crosstab(c(zone, layer), long = TRUE, useNA = TRUE)`** — pure C++, streamed, returns
only observed combinations. It is already this repo's pattern (`break_class_groups.R:339`,
`R/dft_rast_break_class.R:248`). Two calls give cells per (patch × `break_year`) and
(patch × `n_flips`), from which the modal year, the within-patch distribution and exact denominators
all follow, with no statistic chosen in advance. It also keeps `terra::app()` out of the new script
entirely.

Related: `zonal(fun = "mean", na.rm = TRUE)` computes over non-NA cells, not over patch cells, and
returns `NaN` (not `NA`) for an all-NA zone — which `merge(all.x = TRUE)` will not surface as
missing. `crosstab(useNA = TRUE)` gives the NA count directly.

## [R] Rasterizing the published polygons would manufacture Phase 3's result

`terra::rasterize()` without `touches` takes a cell when its **centre** falls in the polygon. The
published polygons are post-intersection, so their boundaries no longer lie on cell edges and
sub-cell fragments frequently contain no centre at all; the default `fun` is last-wins, so two
fragments competing for one cell go to whichever is processed later.

The loss is a perimeter-to-area effect — concentrated in small slivers (the high-flicker population)
and near-zero for large blocky patches, which is what harvest-touching patches mostly are. The join
would therefore *produce* "harvest patches flicker less than the residual", which is Phase 3's
hypothesis.

Avoided by joining on `patch_id` and rasterizing drift's **unclipped** polygons instead, whose
boundaries are on cell edges by construction (`terra::as.polygons()`), making the grid join exact.
`join_audit.csv` asserts it: zero patches with no cells, and `sum(cells) * cell_ha` exactly equal to
`sum(area_ha)`.

## Zone input is a gitignored file from another repo

`subbasins.gpkg` is a `floodplains` step-2 product, not published in the STAC item (the published
`floodplain.gpkg` carries only `<sp>_ff02`, `<sp>_ff04`, `<sp>_ff04_by_blue_line_key`, `<sp>_ff06`).
It exists at `~/Projects/repo/floodplains/data/<group>/subbasins.gpkg`, gitignored, **one feature per
group** for all four.

So an exact reproduction depends on a machine-local file from another repo. Named and checksummed in
the evidence record, with the published `ff04` polygon as the fallback zone and the residual between
the two quantified, so the result does not silently depend on it.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `aggregate.data.frame: no rows to aggregate` at the last step of a 3-minute run | `stats::aggregate()` errors on an empty subset rather than returning a 0-row frame, and every one of the four n_flips subsets is legitimately empty on some input (lnth has no NA `n_flips` cells at all). Wrapped in `agg_cells()`, which returns a typed 0-row frame. |
| A 2018 fire reported 33 patches at offset +1 in a year the script had labelled non-discriminating | The flat `2019:2022` window was wrong. Replaced with `discriminates()`, deriving full / partial / none from `years`. Caught by reading the output, not by review — see the corrected-sample section. |
| `nohup ... &` inside a backgrounded tool call reported exit 0 in seconds for a 30-minute run | The wrapper's exit is not the work. Gated on the in-band `ALL STAGES DONE` marker and on `pgrep`, per `code-check-shell.md`. |

## Phase 1 RESULT: all four groups reconcile exactly

Re-running `dft_rast_transition(patch_area_min = 10000)` and `dft_transition_vectors()` from the
current tree — both files byte-identical to v0.13.0, the version that published the items —
reproduces the published layer in every group.

| group | drift (unsieved) | after 1 ha sieve | after sub-basin clip | published | classes differing |
|---|---|---|---|---|---|
| bulk | 21,701 / 4,625.0 ha | 7,191 / 3,639.7 | 7,161 / 3,627.2 | 7,161 / 3,627.2 | **0 of 53** |
| necr | 21,990 / 5,779.4 ha | 5,710 / 4,730.0 | 5,692 / 4,712.6 | 5,692 / 4,712.6 | **0 of 44** |
| lnth | 12,434 / 1,629.7 ha | 2,762 / 1,152.0 | 2,753 / 1,148.5 | 2,753 / 1,148.5 | **0 of 41** |
| kotl | 17,042 / 3,537.8 ha | — | — | 4,929 | **0 of 46** |

Max |Δha| is 0.00 in every group. **The two totals are not in conflict — they measure different
populations.** The sentence a report can quote:

> The published `transition_vector.gpkg` is drift's own change layer after a 1 ha
> class-agnostic sieve and a clip to the sub-basin polygon. On BULK that takes 21,701 patches
> and 4,625.0 ha to 7,161 patches and 3,627.2 ha, reproducing the published layer exactly.

The join is lossless in every group: 0 patches with no cells, `sum(cells) * cell_ha` equal to
`sum(area_ha)` to 2 dp, and every published `patch_id` matched.

Peak RSS 11.9 / 11.8 / 15.5 / 16.9 GiB (lnth / necr / bulk / kotl) on a 64 GB machine, wall
168 / 348 / 552 / 668 s.

## Phase 3 RESULT: disturbed patches flicker LESS, and it survives stratification

Area-weighted flicker fraction, harvest-touching against the residual matching no disturbance
layer:

| group | stratum | harvest-touching | fire-touching | untagged residual |
|---|---|---|---|---|
| lnth | all | 0.078 | 0.404 | 0.496 |
| lnth | wider (not sliver) | 0.068 | 0.396 | 0.475 |
| lnth | ≥ 0.5 ha | 0.073 | 0.396 | 0.469 |
| necr | all | 0.280 | 0.201 | 0.429 |
| necr | wider | 0.279 | 0.197 | 0.412 |
| necr | ≥ 0.5 ha | 0.278 | 0.196 | 0.406 |

This does **not** support the succession reading. Flicker is *lower* in disturbed patches, not
higher — dated disturbance produces a comparatively clean, well-dated switch, and the flicker
that #62 measured lives in the residual that matches no disturbance layer at all.

The stratification was not optional: in the **sliver** stratum the harvest effect shrinks or
inverts (lnth 0.521 vs 0.631; necr 0.545 vs 0.615), which is the edge confound the plan
predicted. Reporting the unstratified number alone would have overstated it.

Caveat that limits the reading in the other direction: cutblocks are loaded filtered
`HARVEST_START_YEAR_CALENDAR >= 2017`, so pre-2017 cutblocks sit *in the residual*. The
comparison is therefore against a control that contains old harvest, not against undisturbed
floodplain.

## Code review: five rounds, 31 findings, terminated by enumeration

`/code-check` ran five rounds (the floor is three; the loop continued because every round
through round 4 found a defect *inside* the previous round's fix). Full findings in
`review-round1.md` … `review-round5.md`.

| round | findings | bugs | inside a previous fix? |
|---|---|---|---|
| 1 | 8 | 1 | — |
| 2 | 6 | 2 | yes |
| 3 | 10 | 6 | yes |
| 4 | 6 | 2 | yes |
| 5 | 2 | 1 | yes (the guard added in round 4) |

### The mechanism

Named by round 2 and refined through round 4:

> Every derived number is computed from whichever frame is nearest in the code, and the frames
> differ in **population** (unclipped `pat_sv` / clipped `published` rows / `pat_cl` /
> `tag_evaluated` / `n_valid > 0`) or in **precision** (raw vs round-tripped through a rounded
> CSV). Nothing in the data names which population a column carries, so two columns meaning
> "the same thing" can be computed over different sets and no assertion in the script can see
> it.

At its worst the file had `area_ha` carrying three populations across four CSVs,
`n_patches` counting published rows in two files and `pat_sv` patches in two others, and
`break_frac_area_wtd` published under one name with two different weights.

The defects that would have changed a published number:

- **Clip-dropped patches were forced into Phase 3's control group** (round 1). `ev_patch` was
  built from the unclipped patches while the tags came from the clipped layer, so a patch the
  zone clip dropped was NA-filled to `in_fire = 0, in_harvest = 0` — indistinguishable from
  one evaluated against both layers and matching neither. One-directional, area-weighted, and
  **219 patches on kotl against 30/18/9 elsewhere**, which would also have broken the
  cross-group consistency the Q3 conclusion leans on.
- **The agreement rate's denominator was conditioned on its own outcome** (round 2), then
  computed over a *different population* from its numerator (round 3) — published rows against
  `pat_sv` patches. Both denominators are now published from one file.
- **Measurand and weight were on different footprints** (round 3). A fix for the trim had moved
  the weight to the clipped area while the flicker fraction stayed a cell fraction over the
  unclipped patch, producing neither statistic. All three — measurand, weight and the
  `ge_0.5_ha` threshold — are now unclipped, with `area_ha_eval` and
  `patches_trimmed_by_clip` / `trimmed_ha` published so the residual is bounded rather than
  half-corrected.
- **A comment claimed an assertion that did not exist** (round 4). "Asserted below against the
  sieved raster's class table" — there was no such check, and `rm(trans)` ran seven lines
  before `res` existed. Now the geometry and category table are captured before the `rm` and
  compared after.
- **The guard against mixing script versions stamped the wrong version** (round 5).
  `script_sha` was computed where `meta` is written, i.e. at the *end* of the run, so a file
  edited mid-run stamped the post-edit sha onto CSVs the pre-edit code produced — the
  uniformity check would then see one value and accept two definitions. Hoisted to `t0`.
  This mattered here because the file *was* edited mid-session repeatedly.

### Termination

Round 5 enumerated every derived column in every emitted CSV against its population and
precision and found **no column whose population disagrees with its name**. Every boundary a
reader could get wrong now has a published reconciling row —
`published_patch_ids_unmatched`, `patches_not_tag_evaluated`,
`patches_trimmed_by_clip` / `trimmed_ha`, `patches_no_valid_flip_cells` / `no_valid_flip_ha` —
and every clipped/unclipped pair is distinguished by column name.

Two residuals are named rather than hidden: `fire_patches_full + partial` (published rows) and
`n_tagged` (`pat_sv` patches) count the same phrase in two tables, equal iff
`published_patch_ids_unmatched == 0`, which is itself a published row; and `summarize` compares
the four script stamps to each other rather than to the file it is running from, which is a
deliberate scope choice recorded in the code (both stages share one file, so the stricter check
would force a full re-run on any cosmetic edit).

That enumeration is what ended the loop, not a quiet round — per `code-check`'s stopping rule,
once a round has found a defect inside a fix, only an enumeration terminates.

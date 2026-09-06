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

**This is the finding that reshapes Phase 2.** A fire or cutblock dated 2018 or 2023 is structurally
incapable of producing a sustained break, so the disturbance hypothesis and the endpoint-noise
hypothesis predict an identical signature there; and 2017 cannot produce a break at all (the minimum
`break_year` is 2018). Only **2019–2022** discriminates.

## [R] The discriminating window is nearly empty for fire

Tagged patches whose disturbance year falls in 2019–2022:

| source | patches | ha | events |
|---|---|---|---|
| fire | 63, all in `kotl` | 20.0 | 3 distinct `fire_number` |
| harvest | 225 | 858.2 | no opening id published |

Full year distribution of tagged patches:

| group | fire years (patches) | harvest years (patches) |
|---|---|---|
| bulk | 2023 (35, 2 fires) | 2017 (24), 2018 (23), 2019 (7), 2020 (35), 2021 (10), 2022 (13), 2023 (8) |
| necr | 2017 (40), 2018 (87), 2023 (62) | 2017 (20), 2018 (51), 2019 (24), 2020 (23), 2021 (32), 2022 (34), 2023 (9) |
| lnth | 2017 (6), 2023 (1) | 2017 (1), 2018 (1), 2019 (3), 2020 (6), 2021 (3), 2023 (1) |
| kotl | 2017 (28), 2020 (2), 2021 (9), 2022 (52) | 2018 (8), 2019 (7), 2020 (5), 2021 (20), 2022 (3), 2023 (1) |

bulk, necr and lnth fire is entirely 2017 / 2018 / 2023. So **fire is a three-event case series in
one group**, and harvest is the only usable distribution — with no event id, so patches within one
cutblock are not independent and the effective n is unknown and much smaller than 225.

This is pre-registered in `summary_events.csv` before any agreement number is computed.

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

## Reconciliation: the five mechanisms

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
| | |

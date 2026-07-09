# Issue #30 (continued) — Trajectory vignette rework: QA framing + interactive map

## Outcome

Continuation of `2026-07-issue-30-index-trajectory/` (which shipped the pipeline). This cycle reworked
the trajectory vignette after review showed the first example was a poor fit for the reach, and added
one function. Landed on the same PR (#33), released as **v0.3.0** (merged f126422, tagged).

The arc, driven by reconciling the continuous signal with the LULC categorical map and the user's own
imagery:

1. **The first vignette example was weak.** 2018–2023 / monitor-from-2022 produced a region-wide 2023
   dip (dry/smoke year) that swamped localized change; a known logging cut didn't clearly show.
2. **2017–2023 rebuild** (apples-to-apples with the LULC vignette) + longer 2017–2021 history halved
   the false breaks. Diagnosis: IO LULC "Trees→Rangeland" pixels had kNDVI baseline ~0.43 (vs 0.50
   intact), dropped only ~0.037 — on this **deciduous-riparian** reach the categorical product
   **over-calls** forest loss (borderline label flips; summer kNDVI can't separate deciduous trees
   from grass). So the trajectory's value is **QA of the categorical change** + **gradual
   degradation/recovery**, not tree-vs-grass mapping.
3. **Added `dft_rast_trend()`** — per-pixel Theil-Sen slope + Mann-Kendall significance (robust to a
   one-off anomalous season), for the gradual signal.
4. **Patch-level, complementary reframe** (user steer: no whole-floodplain averaging). Real cutblocks
   coincide with red break/trend patches; some red falls *outside* the LULC polygons (removal LULC
   missed) → the two methods catch different real change. Dropped the aggregate QA table and averaged
   group trajectory.
5. **Interactive leaflet map** mirroring the land-cover vignette (Light/Esri/Google basemaps, AOI
   centering) with toggleable break, trend, and the actual Trees→Rangeland polygons (filtered from
   stable Trees→Trees; filled Rangeland-beige #e3e2c3) to inspect cutblocks on satellite.
6. Neutral, methods-first vignette tone (advocacy removed).

Key lessons: a linear trend smears an abrupt cut (use break magnitude for cuts, trend for gradual);
`dft_transition_vectors` includes stable transitions (filter them out); `hcl.colors("Blue-Red 3")`
puts red at the HIGH end (needs `rev=TRUE` for red=loss — caught in self-review); auto-picking a
"clean cutblock" trajectory is unreliable (the interactive map is the honest verifier).

Closed by: PR #33 (commits aa55171..ac3ada0), merged f126422, tag v0.3.0.

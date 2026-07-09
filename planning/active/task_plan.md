# Task: Trajectory vignette redo — 2017–2023, LULC-comparable (#30, continued)

**Continuation of** `planning/archive/2026-07-issue-30-index-trajectory/` (v0.3.0 released,
PR #33 open). That cycle built and shipped the pipeline (`dft_stac_cube` / `dft_index_expr` /
`dft_rast_break`) and a first trajectory vignette. On review the vignette example was weak: it
used a 2018–2023 / monitor-from-2022 window, and the result was dominated by a region-wide 2023
kNDVI dip (dry/smoke year) rather than the localized change we care about — the intended
"scour vs stable" contrast was muddy and a known **logging cut (2022–2023)** did not clearly show.

**This cycle** refines the *example* (not the pipeline) so the trajectory vignette is apples-to-apples
with the existing LULC vignette (same Neexdzii Kwa reach, **2017–2023**) and actually surfaces the
logging. Commits land on the **same branch / PR #33**.

## Phase 1: Re-fetch 2017–2023 growing-season cube
- [x] `dft_stac_cube(datetime = "2017-01-01/2023-12-31", months = 6:9)` — offset split fired 87 pre / 85 post; 84 monthly layers; per-year kNDVI aligns across 2022. Built in **11 min**, cached

## Phase 2: Reduce + reducer decision
- [x] `dft_rast_break(start = c(2022, 1))`, 2017–2021 history → 13,112 finite breaks (vs 25,550 on the 2018 start — longer baseline halves false breaks)
- [x] Kept `bfastmonitor` — cuts are 2022–2023 (in-window); full `bfast()` not needed

## Phase 3: Validate against LULC ground truth
- [x] LULC Trees→Rangeland/Bare vs bfast breaks: tree-loss pixels break **25% vs 13%** (2×), median mag **−0.054 vs −0.020** (2.7×), dated **median 2023.58** (91% in 2023). Real, modest signal
- [x] Quantified: LULC brackets "2020–2023"; trajectory dates it to summer 2023. Caveats logged (IO LULC "Trees" generous; regional 2023 dip; 75% of tree-loss pixels no break)

## Phase 4: Rebuild the vignette honestly
- [x] `data-raw/vignette_data_break.R`: 2017–2023 window; precomputes break raster + LULC tree-loss mask + grouped trajectory (tree-loss/intact/background) + agreement stats → 140 KB artifact
- [x] `vignettes/trajectory-break-detection.Rmd`: reframed as complement to LULC (what/roughly-when vs exactly-when); agreement table; break map w/ tree-loss outlined; grouped trajectory; regional-2023-dip acknowledged. **User agreed to framing + trajectory panel**
- [x] Regenerated `inst/testdata/neexdzii_break.rds`

## Phase 5: Verify + land on PR #33
- [x] Vignette renders + re-builds clean under `R CMD check` (only a spurious future-timestamp NOTE); `devtools::test()` 286 pass; `lintr` clean on the two new files
- [x] Atomic commit on branch `30-continuous-index-trajectory-change-detec` (joins PR #33)
- [ ] `/planning-archive` (append to / supersede the existing #30 archive)

## Phase 6: Reframe as QA + degradation/recovery (goal-aligned rebuild)

Investigating why bfast's gentle signal disagrees with LULC's dramatic Trees→Rangeland
revealed the real value: LULC "tree-loss" pixels had kNDVI baseline 0.43 (vs 0.50 intact),
dropped only 0.037 by 2023, only 2% a real crash. So on this deciduous-riparian reach IO LULC
likely **overstates** forest loss (borderline label flips), and the continuous trajectory's job is
to **question/QA** the categorical change and catch **gradual degradation/recovery** the annual
labels miss — which is exactly the project goal (justify leave-standing / restoration). User
approved the reframe.

- [x] `R/dft_rast_trend.R`: new export — Theil-Sen slope + Mann-Kendall p, mclapply, `.dft_trend_pixel` helper. 16 tests pass, lint clean
- [x] NEWS 0.3.0 updated to list `dft_rast_trend`; docs regenerated
- [x] Rebuilt `vignettes/trajectory-break-detection.Rmd` around QA + degradation/recovery. **QA result (AOI): LULC tree-loss median trend ~0, only ~6% significantly declining (vs ~2% elsewhere); open floodplain greening (+0.013/yr, 17% recovering); intact forest stable.** So the mapped "forest loss" is mostly not real greenness decline — caution on area numbers. Fixed an inverted trend-map palette (red must = declining)
- [x] Generator precomputes break + trend + LULC-QA table + grouped trajectory (AOI-restricted groups) → artifact
- [x] Render + `R CMD check` (0/0/1 spurious-timestamp) + `lintr` clean + `/code-check` (stats verified correct; added nlyr>=2 + min_obs>=2 guards for clean failure); commit on PR #33

## Validation
- [x] Tests pass (302); check clean (0 err / 0 warn / 1 spurious NOTE)
- [x] PWF checkboxes match landed work
- [x] Commits on PR #33, not a new branch
- [ ] `/planning-archive` on completion

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
- [ ] `dft_stac_cube(datetime = "2017-01-01/2023-12-31", months = 6:9)` — matches the LULC vignette window. Offset split fires (2017–2021 pre / 2022–2023 post). Confirm valid kNDVI, note 2017 S2 sparsity. Cache it (one-time ~20 min fetch; iterate freely after)

## Phase 2: Reduce + reducer decision
- [ ] `dft_rast_break(start = c(2022, 1))` with 2017–2021 as history (longer, more robust baseline than the 2018 start). Cuts are 2022–2023 → inside the monitoring window, so `bfastmonitor` suffices
- [ ] Decide `bfastmonitor` (keep) vs full `bfast()` (catches breaks anywhere 2017–2023). Default: keep `bfastmonitor` unless the LULC check shows pre-2022 change we need to date

## Phase 3: Validate against LULC ground truth
- [ ] Cross-check the bfast break map against the LULC **Trees → Rangeland** transition, focused on the north-confluence clearing the user flagged (visible 2020→2023 in the LULC vignette). Confirm negative `break_mag` + `break_date` in 2022–2023 land on the cut. Isolate the tree-corridor drop from the broad rangeland dip
- [ ] If it lands: quantify (break date at the cut vs LULC's "sometime 2020–2023")

## Phase 4: Rebuild the vignette honestly
- [ ] `data-raw/vignette_data_break.R`: 2017–2023 window; save a genuinely divergent pixel pair (cut vs intact) for the trajectory panel if one exists
- [ ] `vignettes/trajectory-break-detection.Rmd`: reframe as the complement to LULC — **LULC says *what* and roughly *when* (annual snapshots); trajectory says *exactly when* (monthly)**. Be honest that a regional 2023 dip is present; highlight the dated cut
- [ ] Regenerate the committed artifact (`inst/testdata/neexdzii_break.rds`)

## Phase 5: Verify + land on PR #33
- [ ] Re-render vignette clean; `devtools::test()`; `R CMD check` 0/0/0; `lintr` clean
- [ ] `/code-check` on the diff; atomic commits on branch `30-continuous-index-trajectory-change-detec`
- [ ] `/planning-archive` (append to / supersede the existing #30 archive)

## Validation
- [ ] Tests pass; check clean
- [ ] PWF checkboxes match landed work
- [ ] Commits on PR #33, not a new branch

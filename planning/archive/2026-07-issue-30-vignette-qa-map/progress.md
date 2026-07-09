# Progress — Trajectory vignette redo (#30, continued)

**Continues** `planning/archive/2026-07-issue-30-index-trajectory/progress.md`. The #30 pipeline was
built, validated, and shipped as v0.3.0 (PR #33 open) in the prior cycle — see that archive for the
full log. This cycle refines the trajectory *vignette example* on the same branch / same PR.

## Session 2026-07-09

- Reopened PWF as an explicit continuation of the archived #30 cycle (see task_plan.md / findings.md
  headers). Not a new branch or issue — commits land on PR #33.
- Trigger: user review of the shipped vignette. It used 2018–2023 / monitor-from-2022 and the result
  was a region-wide 2023 dip (dry/smoke year), not the localized change; the intended scour-vs-stable
  contrast was muddy and a known 2022–2023 logging cut didn't clearly show.
- Plan approved: redo the example at **2017–2023** (apples-to-apples with the LULC vignette), validate
  the bfast break map against the LULC Trees→Rangeland transition at the north-confluence cut, and
  reframe the vignette as LULC (what / roughly when) vs trajectory (exactly when).
- Next: Phase 1 — re-fetch the 2017–2023 growing-season cube (offset split; ~20 min one-time,
  then cached).

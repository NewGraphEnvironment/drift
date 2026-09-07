# Progress — Corroborate the temporal QA against dated disturbance (#67)

## Session 2026-09-06

- Plan-mode exploration: verified the issue's snapshot section directly against the published
  catalogue and the `floodplains` source rather than relying on it
- Plan review (Plan agent, concurrent) returned four findings that changed the design; each was
  verified against the code and the published data before being folded in, and they are marked
  **[R]** in `task_plan.md` and `findings.md`
- Phases approved by user; branch `67-corroborate-the-temporal-qa-against-date` off main
- Scaffolded PWF baseline with the approved, review-corrected phases
- Next: Phase 0 — `summary_events.csv` pre-registered before any agreement number

## Session 2026-09-06 (continued)

- Phase 0: `summary_events.csv` written first for all four groups, pre-registering the sample
  before any agreement number existed. Issue #67 body reconciled in place — snapshot caveat
  discharged, `gross_loss_ha` correction, tag counts and the discriminating classification added.
- Phase 1: **all four groups reconcile exactly.** 0 of 53 / 44 / 41 / 46 transition classes differ
  in count, max |Δha| 0.00. The #66 blocker is closed.
- Phase 2: pooled agreement at lag {0, +1} is 86.2% for fire (123 patches, 5 events) and 72.0% for
  harvest (250 patches), mode +1 — the pre-registered compositing lag.
- Phase 3: flicker is markedly lower in disturbed patches, which does **not** support the
  succession reading. Survives stratification on the #44 signature; the sliver stratum shows the
  edge confound the plan predicted.
- Mid-run correction: the flat `2019:2022` discriminating window taken from the plan review was
  wrong in both directions. Caught by reading a 2018 fire's output, replaced with a three-level
  classifier derived from `years`, and **all four groups re-run** so the committed evidence is
  internally consistent. Logged in `findings.md`.
- Note `inst/notes/temporal-qa-disturbance.md` written from the generated tables; the summarize
  guard was proven to fire on a one-digit mutation and to pass when restored.
- Filed #69 (`dft_rast_transition()` holds 6-7 full-grid rasters — no `filename =` on the sieve
  intermediates), with the measured peak RSS from this run as evidence.
- Carried the three findings that change a published figure's description into #66 before its
  article is written.
- Next: `/code-check` rounds, archive, PR.

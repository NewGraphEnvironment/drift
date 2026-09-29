# Plan review — #81 (Plan agent, 2026-09-28)

Read-only reviewer, so its findings came back as reply text; I transcribed them here. Every finding is folded into `task_plan.md` except where the disposition says otherwise.

| id | finding | disposition |
|---|---|---|
| B1 | `terra::freq()` returns labels on factor strata while `readValues()` returns codes; `freq()` also rounds floats. Count and resolve steps could not join | **Confirmed by probe** (`Water -> Water` vs `1001`). Two passes on one chunked reader; `stratum_label` from `levels()` |
| B2 | Sizing through `ua` assumes strata = map classes; floodplains#93 needs per-stratum SD for an area target | Primary form takes `s_h` from the estimator's `$stratum`; `ua` kept as a convenience |
| B3 | FPC undecided; `n_h > N_h` refusal breaks on tiny strata (the tile has 2- and 3-cell strata) | A stratum with `n_h ≥ N_h` becomes a census, with a message. FPC is now fixed on by `mapaccuracy`, so there is no `fpc` argument (superseded 2026-09-28) |
| G1 | The sampler does not emit `map_class` | `map =` argument, extracted at each cell |
| G2 | One `blocks()` chunk on the tile, so the carry logic is untested | Explicit row chunks, capped at about 1e7 cells; chunk-invariance test |
| G3 | RNG save/restore under-specified (L'Ecuyer, absent seed) | Pin all three kinds; restore, or remove; three tests |
| G4 | A single seed across strata cannot extend a pilot | Per-stratum sub-seeds; `point_id` in draw order, independent of n. Prefix stability **confirmed by probe** |
| G5 | Nonresponse and coverage rules | Refusals listed in the contract |
| G6 | Change targets and union SEs | Composition recipe and "recode, then estimate" in the roxygen, plus a test |
| G7 | Per-stratum reporting | `$stratum` output |
| G8 | Estimator edge cases | Listed in the Phase 2 tests |
| A1 | Equation and table numbers were from memory | Verified against the PDFs in Phase 1 |
| A2 | `level` vs `z`, and relative tolerance | `qnorm`, and absolute tolerance on the pins |
| A3 | The train/test rationale was backwards | Rewritten |
| A4 | `x`/`y` duplicate the geometry; `cell` is grid-bound | `x`/`y` dropped; the grid identity is recorded in `$design` |
| A5 | Polygon rasterise traps (background written as 0, mask to footprint) | In the roxygen recipe |
| O1 | A census oracle validates the strata ≠ map-classes path without the PDFs | Added to Phase 2 |
| O2 | Freeze the output shapes in Phase 2 | Added |
| O3 | `_pkgdown.yml` has no reference index | Noted; out of scope |
| AC1–4 | The must-fail test must run package code; `rep()` expansion; BULK on the factor path | Added |
| S2 | A provenance record | `$design` |

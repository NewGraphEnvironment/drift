# Progress — LULC transition/classify OOMs on large-floodplain AOIs (#34, closes #28)

## Session 2026-07-09

- Committed pending memory-audit docs to `main` first (`a5ef052`: CLAUDE.md +
  inst/notes/gdalcubes-pc-gotchas.md, soul#47) so they stay out of this PR.
- Plan-mode exploration: 2 Explore agents (producers + vectorizer/test harness) +
  1 Plan agent (terra-native rewrite design, terra-1.9.11 semantics verified) + read
  the `floodplains` field caller. Diagnosed **two independent memory drivers**
  (producer ncell-driven = #28; vectorizer floodplain-area-driven stable-mosaic
  polygonize = the NECR field OOM). Reconciled #34 ≡ #28's OOM class.
- User decisions: both fixes on one branch (close #34 + #28), single 0.4.0 release;
  drift-only with documented `floodplains` caller follow-up.
- Created branch `34-lulc-transition-classify-ooms-on-large-f` off `origin/main`
  (6ba10bb), keeping `a5ef052` on local main only.
- Scaffolded PWF baseline with approved phases.
- Next: Phase 1 — `data-raw/benchmark_transition_oom.R` (terra semantics gate at the
  1.8-10 floor + synthetic profiling attributing the two drivers).

# Progress — dft_transition_vectors OOMs on large-extent rasters (#27)

## Session 2026-07-07

- Plan-mode exploration — approaches benchmarked empirically, phases approved by user
- Created branch `27-dft-transition-vectors-ooms-on-large-ext` off main
- Scaffolded PWF baseline from issue #27 with approved phases
- Phase 1 complete: single-pass `patches(values = TRUE)` rewrite + terra floor + 3 new tests
  (suite: 211 pass, 0 fail; lint clean). Regression guard captured from OLD implementation
  before the rewrite: 185 patches / 123.11 ha / 57 at patch_area_min = 1000 — new code matches.
- Final-implementation benchmark: 24M cells, 4,799 patches → 1.9 s (old code: 122 s with only
  1,232 patches)
- Next: Phase 2 (docs + release)

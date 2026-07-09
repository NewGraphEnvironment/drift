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
- **Phase 1 done** (commit pending): `data-raw/benchmark_transition_oom.R`. Semantics
  gate ALL PASS on terra 1.9.11 (floor not bumped — ops predate 1.8-10). Profiling on a
  4.0M-cell coherent synthetic: 4200 transition patches, **89% stable** (discarded by
  the caller) → `changes_only` ~9× working-set cut; ~1.24 GB peak RSS (current code).
  Two-driver diagnosis confirmed; rewrite cleared to proceed.
- **Phase 2 done** (commit pending): added a golden-snapshot test to
  `test-dft_rast_transition.R` capturing summary + raster cats/freq + removed across
  8 param combos (default, from_class, both filters, patch_area_min ∈ {0,500,1000,1e9},
  impossible). Canonicalized (sorted) digest → content-strict, order-independent.
  `expect_snapshot_value(style="serialize")` golden at `_snaps/dft_rast_transition.md`.
  Fixed empty-case handling (cats()[[1]] NULL + freq() errors on all-NA). 44 pass, 0 skip.
- **Phase 3 done** (commit pending): terra-native `dft_rast_transition` rewrite. Golden
  byte-identical; 303 pass / 4 skip; lint clean; /code-check round 1 Clean. Hit the
  imported-terra `%in%` non-dispatch gotcha (→ `subst`) and the freq-on-all-NA error
  (→ tryCatch). Producer peak RSS at 16M cells: 2.66 → 1.63 GB.
- Next: Phase 4 — vectorizer `changes_only` + small-patch raster pre-filter.

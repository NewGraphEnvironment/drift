# Progress — resampling typo silently becomes "near" (#96)

## Session 2026-10-01

- Plan-mode exploration — phases approved by user
- Created branch `96-resampling-typo-silently-becomes-near-in` off main
- Scaffolded PWF baseline from issue #96 with approved phases
- Next: start Phase 1
- Phase 1: `resampling_check()` + shared `cube_view_choice_check()`; checks at all three entry points and both `cube_view()` call sites. Plan review folded in (alias hint, call-site tests, `aggregation_check()` in `fetch_extent_to()`, version 0.21.0). Mutation table 11/11 killed (findings.md). `/code-check` rounds: 1 finding (vacuous `"near"` assertion, fixed), 2 clean, 3 clean. `devtools::test()`: FAIL 0, PASS 1508, SKIP 16.
- Phase 2: @param docs, gotchas note, NEWS 0.21.0. Docs review (1 round, fact-check against code + fresh round trip): clean; widened the old-caches bullet on its note.

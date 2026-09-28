# Progress — Dated reference imagery (#79)

## Session 2026-09-28

- Plan-mode exploration. The phases were approved after re-reading #79-#81 and floodplains#93, which pivoted the plan to #80 first and to floodplain scale.
- Created branch `79-dated-reference-imagery-true-colour-comp` off main, in a worktree (`../drift-79`) while the #80 suites ran in the main tree.
- Scaffolded the PWF baseline with the approved phases.
- Next: Phase 1 (NDWI/MNDWI).
- Phase 1 done. Added the `green`/`blue` S2 roles and the `ndwi`/`mndwi` registry rows. The tests evaluate the resolved expressions over known reflectance, and over post-2022 DN through the offset. A mutation check swapping NDWI's sign failed 4 tests. The frozen cube key is unchanged.

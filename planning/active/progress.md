# Progress — Dated reference imagery (#79)

## Session 2026-09-28

- Plan-mode exploration. The phases were approved after re-reading #79-#81 and floodplains#93, which pivoted the plan to #80 first and to floodplain scale.
- Created branch `79-dated-reference-imagery-true-colour-comp` off main, in a worktree (`../drift-79`) while the #80 suites ran in the main tree.
- Scaffolded the PWF baseline with the approved phases.
- Next: Phase 1 (NDWI/MNDWI).
- Phase 1 done. Added the `green`/`blue` S2 roles and the `ndwi`/`mndwi` registry rows. The tests evaluate the resolved expressions over known reflectance, and over post-2022 DN through the offset. A mutation check swapping NDWI's sign failed 4 tests. The frozen cube key is unchanged.
- Phase 2 refactor landed as `stac_cube_session()`, `stac_cube_cache_read()`, `stac_cube_items()` and `stac_cube_assemble(pixel_fn=)`. The offline cube tests pass 90/90, including the frozen key and the mocked cache gates. **Live byte identity:** an untiled NDVI cube (packaged AOI, 2021-07/08, parallel 4) from main against the refactor gives identical values and NA pattern, max diff 0, 77.1 s vs 77.7 s. Recorded in the scratchpad `cube_identity.R`. The tiled check is pending, in the worktree network run.
- Plan review (Plan agent) is in `review-plan.md`, with a verdict on each finding. Folded in:
  - the per-band shared stretch, with channel order pinned;
  - the composite refuses a window straddling the 2022 offset split;
  - the network e2e cache paths (also fixed on #80);
  - a cube key call-site characterization test;
  - chips are one call per point;
  - the composite key set;
  - an empty year is dropped with a warning (classed `drift_no_items` / `drift_empty_cube`);
  - the COG gdal options, with a NoData assertion;
  - a layer-order guard;
  - the rgb/x name clash check;
  - classified layers are handed to leaflet in 3857 (a pre-existing misregistration);
  - a shared titiler URL base;
  - the composite defaults to `clip = FALSE`;
  - wrap-year windows are documented.
- Probed A2 live: a date-only STAC end bound drops the last day (22 of 23 items). The composite queries with `T00:00:00Z/T23:59:59Z`. The cube has the same issue, pre-existing, and goes to a follow-up issue because fixing it changes what existing cache keys hold.
- Phases 3 and 4 are implemented. Mutation checks: band order, 4326 projection, key call site, offset split, per-image stretch and empty-year skip each turn a test red. The offline suite passes 1089, fails 0, skips 15.

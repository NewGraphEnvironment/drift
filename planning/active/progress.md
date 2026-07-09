# Progress — dft_stac_cube AOI-polygon clip (#32)

## Session 2026-07-09

- Plan-mode exploration — traced `dft_stac_cube` build path, the `filter_geom`
  removal (#30, commit c6953a0), the downstream NA-skip gate in
  `dft_rast_break`/`dft_rast_trend`, the proven `dft_stac_fetch.R:150` mask pattern,
  and the `gotchas` note. Confirmed example AOI non-rectangular (area/bbox ≈ 0.105).
- Plan-agent review — reframed the rationale (compute win illusory; real win is
  polygon-tight output + no caller-side mask), flagged the cache-key wiring Blocker,
  simplified the helper. Phases approved by user.
- Archived #34 PWF confirmed complete; #34 plan-mode scratch doc left to be overwritten
  (user decision — it's redundant with the archived findings/task_plan).
- Created branch `32-dft-stac-cube-restore-aoi-polygon-clip-f` off main.
- Scaffolded PWF baseline with approved phases.
- Phase 1 (commit pending): wrote the test contract — `clip` threaded through the
  `cube_key()` helper + `cube_key(clip = FALSE) != base`; offline `stac_cube_clip()`
  masking test (synthetic raster + half-covering polygon); network e2e high-NA-fraction
  assertion under default clip. Confirmed red against current code (FAIL 6 | SKIP 2 |
  PASS 1): 5 cache-key tests error on `unused argument (clip)`, offline test on
  `object 'stac_cube_clip' not found`. `/code-check` deferred to the Phase 2 impl diff
  (Phase 1 is test-only, self-reviewed).
- Next: Phase 2 — implement `clip` param + helper + cache-key wiring.

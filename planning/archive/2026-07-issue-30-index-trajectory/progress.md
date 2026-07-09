# Progress — Continuous index-trajectory change detection (Sentinel-2 + BFAST) (#30)

## Session 2026-07-08

- Plan-mode exploration — two Plan agents vetted the design against issue #30 and
  the codebase (acquisition half: config + index registry + cube; reduction half:
  bfast reducer + tests + vignette). Both independently confirmed the issue-sketch
  corrections. Phases approved by user (one branch, single 0.3.0 release).
- Empirically verified the gdalcubes/rstac/terra APIs read-only (see findings.md).
- Created branch `30-continuous-index-trajectory-change-detec` off main.
- Scaffolded PWF baseline from issue #30 with approved phases.
- **Phase 1 done** (config role-based schema + sentinel-2-l2a + fetch guard + tests).
  Fresh-eyes code-check caught a dangling `[dft_stac_cube()]` roxygen link (R CMD
  check WARNING) → downgraded to code spans until Phase 3; hardened the fetch guard
  to key on `isTRUE(cfg$cube)` alone. 27 config + 16 fetch assertions green.
- **Phase 2 done** (index registry `inst/indices/indices.csv` + `dft_index_expr()`
  + `dft_index_table()` + resolver internals; 15 assertions green; code-check Clean).
- **Phase 3 done** (`dft_stac_cube()` + `stac_cube_cache_key()`; 20 assertions green).
  Code-check caught a multi-feature-AOI `intersects` bug (silent NoData holes) →
  fixed by unioning the AOI. `eo:cloud_cover` NSE declared in globalVariables.
- Committed Phases 2+3 together (tightly-coupled acquisition pipeline; roxygen
  cross-refs only resolve once both exist). Full suite: 261 pass / 0 fail / 3 skip.
- **Phase 4 empirical gate RUN** (bfast 1.7.2 installed): proved closure-capture in
  the reduce_time R-callback DOES NOT WORK (worker process, any parallel setting) —
  the design must build a self-contained FUN. Embed-helper-object approach works at
  parallel 1 and 2. See findings.md.
- **Phase 4 done** (`dft_rast_break()` + `.dft_break_pixel`/`cadence_frequency`/
  `build_break_reducer`/`break_cache_key`; bfast→Suggests). 30 assertions green;
  full suite 291 pass. Code-check Clean.
- **Real-S2 E2E surfaced a `dft_stac_cube` bug**: `gdalcubes::filter_geom()` yields
  an all-NA cube (and intermittently segfaults the compute worker) on this gdalcubes
  build. Proven sibling `dft_stac_fetch` works on the same AOI, and the cube stages
  work WITHOUT filter_geom (valid kNDVI 0..1). Fix: drop filter_geom; the cube spans
  the AOI bbox (cloud-masked), callers clip the reduced raster with terra::mask()
  (matches how dft_stac_fetch masks). Fixed E2E verified (48-mo cube valid, break
  reduce 25 s, no segfault); committed (c6953a0).
- **User steer — growing-season tuning.** All-months fetch was ~30 min for 100 ha
  (the fetch, not the compute). User asked whether restricting to the growing season
  sharpens the veg signal AND cuts data — yes on both. Added `dft_stac_cube(months=)`
  calendar-month filter (default NULL); snow (SCL 11) now in the default S2 mask; GDAL
  /vsicurl config (on.exit restore); `dft_rast_break(order=)` harmonic knob. Growing-
  season E2E (months=6:9, 2018-2023): cube in 12 min (vs 30), 24 clean summer obs/pixel,
  breaks dated to summer months (2022.42-2023.67). 294 unit tests pass, lint clean.
- Committed growing-season enhancement (61eaa5d); code-check Clean.
- **Peer session + my E2E stats surfaced a real offset bug.** PC's uniform offset=-0.1
  is wrong for pre-2022-01-25 scenes (the +1000 DN baseline offset flips there). A
  series crossing the boundary shows a false whole-AOI break: my own growing-season
  E2E had 90903/91467 (99%) negative breaks all at 2022.42 — the offset boundary, not
  vegetation. User chose to fix it PROPERLY now (baseline-conditional split).
- **Re-architecture (terra route).** gdalcubes can't read a terra-written NetCDF
  (round-trip fails), so coalescing pre/post cubes at the gdalcubes level is out.
  Pivoted the reduction to terra: dft_stac_cube now returns a terra SpatRaster stack
  (materialized GeoTIFF, time set), splitting items at the offset boundary and
  correcting each side with its own offset (terra::cover coalesce). dft_rast_break
  reduces the stack via parallel::mclapply (fork -> closures + package internals work,
  no gdalcubes-worker serialization; validated 102400 px in 8.3 s). Dropped
  build_break_reducer/break_cache_key/gdalcubes reduce_time; .dft_break_pixel unchanged.
  Config: sentinel-2-l2a gains offset_boundary="2022-01-25" + offset_before=0. Full
  suite 286 pass, lint clean.
- Next: confirm the split kills the fake 2022 step (per-year kNDVI aligns; breaks
  sparse), regenerate artifact, Phase 5 (vignette + NEWS + 0.3.0 + archive + PR).

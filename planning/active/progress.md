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
  (matches how dft_stac_fetch masks). Verifying the fixed E2E, then committing the
  fix + Phase 5 (vignette + NEWS + 0.3.0).

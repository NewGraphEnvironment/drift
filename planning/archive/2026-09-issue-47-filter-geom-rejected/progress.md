# Progress — Adopt the fixed filter_geom (#47)

## Session 2026-09-01

- Plan-mode exploration — phases approved by user
- Created branch `47-adopt-the-fixed-filter-geom-now-that-the` off main
- Scaffolded PWF baseline from issue #47 with approved phases
- Exploration established two facts that reshape the issue and are recorded in `findings.md`:
  CRAN gdalcubes is also 0.7.4 and still broken (so no version check can discriminate), and
  `filter_geom` skips at **chunk** granularity — which at gdalcubes' default chunking is a 2 × 2 grid
  over the packaged AOI, i.e. **no skip at all**. Phase 1 is therefore measurement with a decision gate.
- User decisions: runtime capability probe with fallback; scope `dft_stac_cube()` only
- Next: Phase 1 — `data-raw/benchmark_filter_geom.R`

## Session 2026-09-01 (continued)

- Phase 1 measurement complete. Gate FAILED for `filter_geom`: no arm beat the
  baseline. Default chunking exactly cost-neutral (462 req / 236.9 s vs
  462 / 236.8), finest chunking 1.5x the requests and 47% slower — the 26.7%
  chunk skip is real and more than cancelled by losing COG-block alignment.
- The rival hypothesis won instead: drift never called `gdalcubes_options()`,
  so every cube read was single-threaded. `parallel = 4` is 2.05x, `8` is 2.47x,
  output byte-identical. Shipped as `dft_stac_cube(parallel =)`.
- Two live defects found while reviewing, both independent of #47: the only
  end-to-end cube test passed on an all-NA cube, and `stac_cube_clip()`
  documented cell-centre semantics when `terra::mask()` is `touches = TRUE`.
- Three adversarial review rounds found five defects in my own work, two of
  which I had introduced (a post-condition that aborted the documented
  `months = 6:9` workflow; a NEWS entry publishing the pre-fix behaviour).
- #48 filed: both frozen cache-key goldens fail on `main`, so the key moved and
  silently orphaned every cached cube and fetch.
- Commits: 8d21bd3, f5a6182, e9932a6, a2bba0d, 011f015

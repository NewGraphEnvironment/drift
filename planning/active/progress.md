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

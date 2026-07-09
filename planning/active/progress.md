# Progress — Tile dft_stac_fetch (#36)

## Session 2026-07-09

- Plan-mode exploration — read `dft_stac_fetch.R`, the cube sibling's assembly,
  the fetch test conventions, and the STAC config. Phases approved by user.
- Plan-agent design review caught: write tiled mosaic as `.tif` not `.nc`
  (terra NetCDF write fragile); test oracle compares over cropped common AOI
  cells not raw dimensions; guard `tile_size ≥ res` after snapping; golden hash
  regression for `tile_size = NULL`; GDAL `/vsicurl` config on the tiled path.
- Created branch `36-tile-dft-stac-fetch-to-bound-download-over-spars` off main.
- Scaffolded PWF baseline with approved phases.
- Next: start Phase 1 (tests-first for `tile_grid()` + `tile_size` normalization).

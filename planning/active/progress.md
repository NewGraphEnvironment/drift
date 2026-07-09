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
- Phase 1 done: `tile_size_check()` (validate + snap to res multiple) and
  `tile_grid()` (res-aligned tiles intersecting the AOI) added to
  `dft_stac_fetch.R`, with 6 offline test blocks written first (confirmed red,
  then green — 40 pass / 1 skip). Lint clean.
- Next: Phase 2 (cache-key conditional `tile_size` append + golden regression).

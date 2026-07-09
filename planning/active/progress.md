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
- Phase 2 done: `stac_cache_key()` gains optional `tile_size`, appended to the
  hash only when non-NULL — so an untiled fetch reproduces the exact legacy hash
  (frozen `79f67b7b9dae` golden test guards this) and a tiled fetch keys
  distinctly. Test helper snaps via `tile_size_check` to mirror production
  (504≡500). 45 pass / 1 skip; lint + code-check clean. Call-site wiring
  deferred to Phase 4 (arrives with the fetch param).
- Phase 3 done: extracted `fetch_extent_to()` (cube_view + raster_cube +
  write_ncdf); untiled path routes through it writing straight to the existing
  `<yr>_<key>.nc` — faithful code-motion, cube_view built identically, 45 pass /
  1 skip, lint clean. Shared primitive de-risks Phase 4 (tiles reuse it).
- Phase 4 done: `mosaic_tiles()` helper + `tile_size` wired end-to-end. Tiled
  branch fetches each intersecting tile via the shared `fetch_extent_to()`,
  `terra::merge(terra::sprc(...))`, writes a `.tif` mosaic (extension routed by
  `is.null(tile_size)`), unlinks temps, then masks. GDAL `/vsicurl` config with
  on.exit restore, scoped to the tiled path. Offline merge oracle (byte-for-byte
  reassembly + single-tile + .tif round-trip) + opt-in network e2e (tiled ==
  untiled, resampled onto the untiled grid). Roxygen `@param tile_size` + cache
  doc. 352 pass / 5 skip; document + lint + code-check clean. Code-check flagged
  the network test's sub-pixel-offset fragility → hardened via near-resample.
- Next: Phase 5 (gotchas note + NEWS 0.6.0 + DESCRIPTION bump).

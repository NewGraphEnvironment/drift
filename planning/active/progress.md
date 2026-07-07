# Progress — dft_stac_fetch cache key omits AOI (#25)

## Session 2026-07-06

- Plan-mode exploration — phases approved by user (extent check explicitly skipped)
- Created branch `25-dft-stac-fetch-cache-key-omits-aoi-secon` off main
- Scaffolded PWF baseline from issue #25 with approved phases
- Phase 1 complete: `stac_cache_key()` helper + `<year>_<key>.nc` filenames + 5 local key tests
  (suite: 192 pass, 0 fail; lint clean)
- Phase 2 complete: `write_ncdf(..., overwrite = TRUE)` + `@param force` doc caveat
- Next: Phase 3 (docs + release)

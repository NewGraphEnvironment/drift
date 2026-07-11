# Progress — Bound `dft_stac_cube()` streaming to the AOI (#38)

## Session 2026-07-11

- Plan-mode exploration — read `R/dft_stac_cube.R` + `R/dft_stac_fetch.R` (#36 tiling) in full; confirmed cube test patterns, S2 config (offset_boundary 2022-01-25), example AOI
- Plan-agent review caught B1 (local-closure vs @noRd), O1 (author cube-key golden guardian before refactor), G1/G3 (offline commutativity + clip=FALSE extent tests), A1 (uniform-nlyr guard), AC1/AC2 (float tolerance + 2022-straddling network window) — all folded into the approved plan
- Created branch `38-bound-dft-stac-cube-streaming-to-the-aoi` off main
- Scaffolded PWF baseline with approved phases
- Next: Phase 1 — freeze the cube-key golden guardian, then the conditional `tile_size` append

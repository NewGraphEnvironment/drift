## Outcome

Added an opt-in `tile_size` to `dft_stac_cube()` (#38) that bounds the STAC **read**
to the AOI footprint — the continuous-path twin of #36's `dft_stac_fetch(tile_size=)`.
By default one gdalcubes cube is streamed over the whole AOI bounding box, so for a
thin, diagonal floodplain corridor (area/bbox ≈ 0.1) the COG streaming (~10–30 min for a
multi-year monthly Sentinel-2 fetch) is ~10× larger than the polygon needs. When
`tile_size` is set, the bbox is split into a `res`-aligned grid and only tiles
intersecting the AOI polygon are streamed — each carrying the full SCL mask, spectral
index, and 2022 baseline-offset split — then mosaicked with a new `mosaic_stacks()`. The
`filter_geom`-independent path (the in-cube polygon clip segfaults on the pinned build).

Delivered tests-first across six atomic phases: the cube cache key gained a conditional
`tile_size` append guarded by a **frozen golden-hash** (`638a2be11fdf`, byte-for-byte
preservation of the untiled key so existing `cube_*.tif` stay valid); `mosaic_stacks()`
with three offline oracles (multi-layer merge, cover-then-merge == merge-then-cover
commutativity, tile-union extent); the core refactor into an `assemble_index_stack(extent)`
closure with the untiled path behavior-preserving and the tiled branch guarded on uniform
nlyr; an opt-in network e2e; docs; and the release bump.

**What was learned / decided (the network e2e earned its keep):**
- `terra::nlyr()` returns a **double** — the uniform-nlyr guard's `vapply(..., integer(1))`
  template errored on the live run; fixed to `numeric(1)`. The tiled fetch itself worked
  (all 12 tiles streamed, offset-split, covered) — only the strict guard tripped.
- The tiled and untiled cubes are **not co-lattice**: gdalcubes enlarges the untiled bbox
  extent symmetrically to align with `dx/dy` (~0.5 px), while tiles anchor at the bbox
  lower-left. So they cannot be compared pixel-for-pixel. Confirmed offline on saved real
  cubes that this is a **benign grid offset, not a bug**: bilinear-aligned correlation
  ≈ 0.997, per-layer means within ~1e-3, and **no tile seams** (edge |diff| == interior —
  gdalcubes reads the source margin at tile edges). The network test was rewritten to
  assert grid-robust equivalence (bilinear-aligned correlation + per-layer means), with
  thresholds measured on the real cubes. Offset-split-under-tiling stays covered by the
  offline commutativity oracle.
- Tile anchoring stays at bbox-LL (re-anchoring to gdalcubes' enlarged origin would couple
  `tile_grid()` to gdalcubes internals and change the shared #36 helper for no
  reducer-visible gain). The bilinear-tiling lesson is recorded in
  `inst/notes/gdalcubes-pc-gotchas.md`.
- The cube already caches `.tif` and already sets the GDAL `/vsicurl` config, so #36's
  `.nc`/`.tif` extension routing and scoped-config machinery were **not** needed here.
- `tile_size_check()` / `tile_grid()` were reused verbatim from #36 (same package
  namespace). Note: `object_usage_linter` resolves cross-file internals against the
  *installed* namespace, so a stale install shows false positives — reinstall to clear.

`devtools::check()` clean (0 errors / 0 warnings / 0 notes); 365 pass / 6 skip.
Released as **v0.7.0**.

Closed by: commits 90f9d93..d7a5094 on branch
`38-bound-dft-stac-cube-streaming-to-the-aoi` / PR (Fixes #38) → v0.7.0.

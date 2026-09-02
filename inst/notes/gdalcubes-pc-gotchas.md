# gdalcubes + Planetary Computer Sentinel-2 gotchas

Non-obvious gdalcubes + Microsoft Planetary Computer Sentinel-2 gotchas hit
building `dft_stac_cube()` / `dft_rast_break()` / `dft_rast_trend()`.

Provenance, because it is now mixed: the #30-era bullets were verified on
**gdalcubes 0.7.3** / rstac 1.0.1 / terra 1.9.11 / bfast 1.7.2. The `filter_geom`,
`parallel` and `tile_size` measurements (#47, 2026-09-01) were taken on
**gdalcubes 0.7.4** — specifically `NewGraphEnvironment/gdalcubes@newgraph`
(`8bad203`), which is 0.7.4 plus the `filter_geom` segfault fix — with terra
1.9.34. Each bullet says which.

- **`gdalcubes::filter_geom()` is not worth using — now for measured reasons, not
  because it crashes (#47).** The original defect was a segfault in the compute
  worker (`gc_exec_worker`, `address 0x120`) or, intermittently, a silent all-NA
  cube; that is genuinely fixed in `NewGraphEnvironment/gdalcubes@newgraph`
  (`8bad203`), which clears the upstream reproducer in `appelmar/gdalcubes#110`.
  Do NOT reach for it anyway. Three findings, all measured on the
  packaged AOI with `CPL_CURL_VERBOSE` request counts
  (`data-raw/benchmark_filter_geom.R`, `data-raw/logs/benchmark_filter_geom/`):
  - **It skips whole CHUNKS, not pixels**, and `gdalcubes:::.default_chunk_size()`
    targets `2 * parallel` spatial chunks with the edge clamped to `[64, 1024]`
    px. At `parallel = 1` that is a **2x2 grid** on a 3.3 km reach, which a
    corridor intersects entirely — so at the default it skips **nothing**:
    462 requests / 236.9 s against the bbox baseline's 462 / 236.8 s.
  - **Forcing chunking finer costs more than it saves.** Sentinel-2 L2A COGs are
    `Block=512x512`; a 64 px chunk sits inside one source block, so the same
    bytes are refetched per chunk. 64 px and 128 px chunking both measured
    **693 requests / ~345 s — 1.5x the requests and ~47% slower** — while
    skipping 26.7% and 11.1% of the ground respectively (predicted by
    `data-raw/benchmark_filter_geom_chunkskip.R`; the gap between that prediction
    and the wire is the whole finding — more skipping, more cost). The AOI/bbox area ratio (0.102) is the wrong bound: the read
    is chunk-granular and the cost is COG-block-granular.
  - **It clips at CELL CENTRE where `terra::mask()` is `touches = TRUE`.**
    Swapping them shrinks the analysed footprint by **15.5%** (49,244 -> 41,608
    non-NA cells). Values agree exactly where both have data (correlation 1.000,
    max abs diff 0) — it is the footprint that moves, silently. Any future
    adoption must hand `filter_geom` a polygon buffered by `>= res*sqrt(2)/2`
    and KEEP the `terra::mask()`, so the footprint does not move.
  - Upstream `appelmar/gdalcubes#110` is open and the fix PR #111 unmerged, so
    CRAN 0.7.4 still segfaults — and reports the **same version string** as the
    fork, so no version check can tell them apart.

  Use the AOI bbox in `cube_view(extent=)` and
  `terra::mask()` afterward, as `dft_stac_fetch()` does. **Resolved (#32):**
  `dft_stac_cube(clip = TRUE)` (the default) masks the assembled terra stack to
  the AOI polygon client-side (helper `stac_cube_clip()` = `terra::mask(stk,
  terra::vect(aoi))`), so the cube is polygon-tight and
  `dft_rast_break()`/`dft_rast_trend()` skip out-of-AOI pixels via their
  `rowSums(!is.na) >= min_obs` gate. **Residual (resolved, #38):** this clips the
  *output* only — `cube_view(extent = bbox)` streams the full bbox of COGs, so the
  clip alone does not cut fetch time. `dft_stac_cube(tile_size = <metres>)` now bounds
  the *read* by tiling the `cube_view` (see the next bullet). `clip = FALSE` keeps the
  full bbox (or, with `tile_size`, the AOI-intersecting tile union).
- **Download-side workaround without `filter_geom`: tile the `cube_view` (#36).**
  Since `filter_geom` can't push the AOI into the read, the categorical
  `dft_stac_fetch(tile_size = <metres>)` splits the AOI bbox into a `res`-aligned
  grid and streams only tiles that intersect the AOI polygon (skipping the empty
  bbox corners), then mosaics with `terra::merge()`. For a thin, diagonal
  floodplain corridor (measured ~10% of the bbox inside the polygon) this fetches
  near the AOI footprint instead of the full bbox. Tiles must be snapped to a
  multiple of `res` and anchored at the bbox lower-left so their pixel grids are
  co-lattice — otherwise the merge seams. The tiled mosaic is written with
  `terra::writeRaster()` to a **`.tif`** (terra's NetCDF *write* is fragile — see
  the round-trip bullet below), so tiled and untiled fetches cache under different
  extensions and keys. The continuous `dft_stac_cube(tile_size = <metres>)` (#38)
  applies the same technique to the reflectance-cube read (per-tile `cube_view` +
  SCL mask + the 2022 offset split + `terra::cover`, mosaicked by `mosaic_stacks()`;
  the cube already caches `.tif`, so no extension split there).
- **Bilinear tiling is not co-lattice with the untiled cube (#38).** The cube's
  default `resampling = "bilinear"` makes the tiled read sensitive to grid alignment
  in a way the categorical `near` path (#36) is not. gdalcubes *enlarges the untiled
  bbox extent symmetrically* to align with `dx/dy` (observed ~0.5 px on a ~3.3 km
  reach), while the tiles anchor at the bbox lower-left — so the tiled cube is **not
  co-lattice** with the untiled cube and is **not pixel-identical** to it. It is still
  a faithful resampling of the same source: bilinear-aligned correlation ~0.997,
  per-layer means within ~1e-3, and **no tile seams** (gdalcubes reads the source
  margin at tile edges, so |diff| at seams == interior). The only difference is a
  benign sub-pixel grid offset, immaterial to the per-pixel `dft_rast_break()` /
  `dft_rast_trend()` reducers. Consequence for tests/QA: compare a tiled cube to an
  untiled one by **bilinear-aligning** one onto the other (`terra::resample(...,
  method = "bilinear")`) and checking correlation + per-layer means — never
  pixel-for-pixel. Re-anchoring the tiles to gdalcubes' enlarged origin to force
  co-lattice was rejected: it would couple `tile_grid()` to gdalcubes internals and
  change the shared #36 helper for no reducer-visible gain.
- **`reduce_time()` R-callback runs in spawned worker processes at EVERY parallel
  setting** (incl. `parallel = 1`). A closure over enclosing locals fails there
  (`object 'band' not found`). Options: build a self-contained callback (inline
  literals via `substitute()`, `load_pkgs = "bfast"`), OR — cleaner — skip the
  gdalcubes reduce entirely and reduce a terra stack with `parallel::mclapply`
  (fork inherits namespace + closures; 102k px in ~8 s). drift uses the terra
  route.
- **gdalcubes CANNOT read a terra-written NetCDF** ("Failed to identify x,y,t
  dimensions"). So you can't coalesce/modify cubes in terra and hand them back to
  gdalcubes. drift's fix: `dft_stac_cube()` returns a terra `SpatRaster` stack
  (materialized GeoTIFF, `terra::time` set), not a gdalcubes cube.
- **Planetary Computer `sentinel-2-l2a` +1000 DN reflectance offset flips at
  2022-01-25** (processing baseline 04.00). Pre-boundary scenes have offset 0,
  post have -0.1. PC ships NO per-item offset metadata and `apply_pixel` can't
  express a per-date offset. A uniform offset produces a FALSE whole-AOI index
  step at 2022 (kNDVI's `tanh` hides it as bounded 0-1, so the cube looks valid;
  ~99% of pixels "break" at the boundary). Fix: split the item list at the
  boundary, correct each side, coalesce with `terra::cover`. Element84
  `sentinel-2-c1-l2a` is uniformly harmonized but has a 2022 data hole for tile
  09UXA.
- **`rstac::get_request()` truncates at 250 items** on PC (page cap) and
  `items_matched()` is NULL, so you can't detect truncation —
  `post_request() |> items_fetch()` is mandatory for multi-year monthly queries.
  `ext_filter(`eo:cloud_cover` <= {{var}})` needs `{{ }}` for a runtime variable.
- **The `next` link SURVIVES a successful `items_fetch()`, so "error if a `next`
  link remains" is a guard that aborts every correctly-paged fetch.** This is the
  obvious implementation and it is wrong. `rstac:::items_fetch.doc_items` mutates
  only `items$features` and never `items$links`, so what you get back is page 1's
  document with a concatenated feature list — carrying page 1's `next` verbatim.
  Measured 2026-09-01 on `io-lulc-annual-v02` over the packaged AOI (14 items):

  ```
  limit=NULL raw_n=14 raw_next=FALSE | fetched_n=14 fetched_next=FALSE | matched=NULL
  limit=1    raw_n=1  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
  limit=3    raw_n=3  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
  ```

  A surviving `next` means *paging happened*, not *paging is incomplete*. drift
  therefore **strips** the stale link rather than erroring on it (#51) — leaving it
  attached to `attr(result, "stac_items")` lets a caller re-run `items_fetch()` on
  an already-complete collection and silently duplicate pages 2..N.

  What completeness checks are actually available, and their reach:
  * **duplicate item ids** — never skipped, and the only one that works on PC.
    `gdalcubes::stac_image_collection()` drops duplicates behind a
    `.pkgenv$debug`-gated message, so nothing downstream would ever report them.
  * **`items_matched()` vs the item count** — works on STAC APIs that return
    `numberMatched`; **never executes against PC**, so it must be fixtured in tests
    or it is dead code.
  * Every non-`next_error` failure inside `items_fetch()`'s loop (transport, non-200,
    non-JSON) propagates rather than being swallowed, so after a successful
    `items_fetch()` the only remaining silent-truncation mode is a server omitting
    `next` while more data exists. That — not "the check skips on PC" — is why not
    asserting completeness there is honest.
- **GDAL /vsicurl tuning** (`GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR`,
  `VSI_CACHE=TRUE`, HTTP multiplex) helps modestly (~38→28 s/month); the real
  speed/quality win is fetching fewer better months (growing-season `months`
  filter). A 100-ha reach, 4 yr monthly = ~25-30 min fetch (COG-stream bound);
  the bfast reduce is seconds.
- **`gdalcubes_options(parallel =)` is the biggest single lever, and drift did
  not set it at all before v0.9.0 (#47).** Every cube read therefore ran
  single-threaded — not a considered choice, just the consequence of never
  calling `gdalcubes_options()`. gdalcubes also *derives the chunk size from*
  `parallel` (`gdalcubes:::.default_chunk_size()`), so raising it makes chunks
  finer as a side effect — but that is **not** where the win comes from. Arms
  isolating chunk size at `parallel = 1` measured finer chunks **45% slower and
  50% more requests** (343.7 s / 693 requests at 128 px against 236.9 s / 462 at
  the default), so the speedup below is concurrency alone. Measured on the
  packaged AOI, 4-month monthly kNDVI cube:

  | setting | wall clock | vs default | output |
  |---|---|---|---|
  | `parallel = 1` (the old behaviour) | 236.8 s | 1.00x | baseline |
  | `parallel = 4` | 115.8 s | **0.49x** | byte-identical |
  | `parallel = 8` | 96.0 s | **0.41x** | byte-identical |

  Byte-identical means it: correlation 1.000, max absolute difference 0, same
  grid, same 49,244 non-NA cells. So it is a pure cost knob and deliberately
  does **not** enter the cache key. `dft_stac_cube(parallel =)` now defaults to
  `min(4, cores - 1)` — capped rather than uncapped because each worker holds
  chunks in memory and drift has hit OOM on large AOIs before (#27, #34).
  Request *counts* go UP (462 -> 1134 at 4 workers, 1386 at 8) while wall clock
  falls, so counting requests alone would score this exactly backwards — the
  concurrency, not the byte volume, is the win.
- **`tile_size` is the slowest option, not the fastest (#47).** Measured at 640 m
  on the packaged AOI: **1263.6 s and 3213 requests** against an untiled
  236.8 s / 462 — 5.3x slower — because every tile rebuilds the
  `stac_image_collection` and reopens the COGs. It also lands sub-pixel-offset
  (correlation 0.996, max abs diff 0.254, recall 95.8%). Reach for it only when
  peak memory rather than wall clock is the binding constraint.

See `planning/archive/2026-07-issue-30-index-trajectory/findings.md` and
`planning/archive/2026-07-issue-30-vignette-qa-map/findings.md` for the full
empirical journey.

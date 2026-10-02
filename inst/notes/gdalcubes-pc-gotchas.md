# gdalcubes + Planetary Computer Sentinel-2 gotchas

Non-obvious gdalcubes + Microsoft Planetary Computer Sentinel-2 gotchas hit
building `dft_stac_cube()` / `dft_rast_break()` / `dft_rast_trend()`.

Provenance, because it is now mixed: the #30-era bullets were verified on
**gdalcubes 0.7.3** / rstac 1.0.1 / terra 1.9.11 / bfast 1.7.2. The `filter_geom`,
`parallel` and `tile_size` measurements (#47, 2026-09-01) were taken on
**gdalcubes 0.7.4** — specifically `NewGraphEnvironment/gdalcubes@newgraph`
(`8bad203`), which is 0.7.4 plus the `filter_geom` segfault fix — with terra
1.9.34. Each bullet says which.

**Where gdalcubes comes from now (#80, 2026-09-28).** gdalcubes was archived on
CRAN on 2026-09-16. drift lists `appelmar/gdalcubes` in `Remotes:` with no suffix,
and upstream master (0.7.5, `ed68331`) has merged the `filter_geom` fix (their
PR #111), so the `NewGraphEnvironment/gdalcubes@newgraph` fork is no longer needed.
Do not install the fork over 0.7.5.

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
- **Strip `next` case-SENSITIVELY, and keep a case-variant.** `items_next.doc_items`
  selects with `links(items, rel == "next")` — measured: `next` matches, `NEXT` and
  `Next` do not. Two consequences, and the second is the one that matters. A `NEXT`
  link is **inert** to `items_fetch()`, so it cannot cause the duplicate above and
  does not need stripping. And its presence means rstac **could not follow it and
  stopped after page one** — the truncation this whole entry is about — which on PC
  nothing else can see, since `items_matched()` is NULL and a short read produces no
  duplicate ids. So that link is the last local evidence of a truncated fetch, and a
  "safer" case-insensitive strip *destroys* it. drift warns and keeps it. Widening a
  matcher past what its consumer actually matches is the trap here: the guard stops
  agreeing with the library whose behaviour it is compensating for.

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

## Floodplain scale and multi-band reads (#79, 2026-09-28)

Measured on gdalcubes 0.7.5, rstac 1.0.1 and terra 1.9.50, with the BULK floodplain (`bulk_co_ff04`) and the packaged AOI. Scripts are `data-raw/benchmark_composite_bulk.R`; the numbers are in `planning/archive/2026-09-issue-79-dated-reference-imagery/`.

- **Planetary Computer rejects a search body over about 1 MiB with HTTP 413.** It accepted 21,348 vertices (860 KB of GeoJSON) and rejected 26,508 (1.07 MB). BULK's floodplain is 104,584 vertices (4.2 MB), so an `intersects` query on it failed in 9 s. `stac_query_geometry()` switches to the convex hull above 20,000 vertices. The hull is a superset, and pixels over the AOI are unchanged.
- **PC SAS tokens last about 45 minutes** (a token issued at 17:16:55Z expired at 18:01:55Z), and features were signed once, at query time. A 54-minute tiled read lost 15 of 30 tiles.
  - `stac_features_resign()` re-signs before each extent. rstac's signer refreshes an expired token and replaces the `sig` parameter of an already-signed href.
  - Verified live: corrupted tokens read 102,364 cells after re-signing, 0 without. With re-signing, a full 3 h 16 min BULK read had no failed tiles.
- **gdalcubes reports failed chunks only on stderr**, as `[WARNING] n out of m chunks have repoprted errors / incompleteness`. It is not an R warning. The cube is written with those chunks NA and passes an any-data check.
  - `capture.output(type = "message")` caught the line in 1 of 4 configurations, and never with `parallel > 1`, where workers write to the process's stderr directly.
  - Do not build a guard on it. The output file records the same failure reliably; see the #87 section below.
- **terra reads a multi-variable gdalcubes NetCDF with its variables in ALPHABETICAL order.** A true-colour `apply_pixel(names = c("red","green","blue"))` reads back as `blue, green, red`, so select layers by name, never by position. The composite does this in `composite_layers_order()`.
  - The layers also arrive carrying a time (step `yearmonths`).
  - Writing that to a COG makes terra emit a `.aux.json` sidecar. So do units, varnames, longnames, metags and scoff; names alone do not.
- **A date-only STAC end bound is read as 00:00Z**, so it drops that day's scenes, which in BC land around 19:00Z. A window ending on a scene day returned 22 of 23 items; the same window with `T23:59:59Z` returned 23. The composite uses explicit times. The cube still passes the user's string (#83).
- **CMR-STAC (NASA LPCLOUD, for HLS) differs from PC.** It returns 500 on `intersects` (use `bbox`) and ignores the CQL2 `eo:cloud_cover` filter (filter client-side). Its assets need a real Earthdata Login; `earthdatalogin`'s defaults return 401. See #82.

## Silent fallbacks and counting clear observations (#92, 2026-09-30)

- **`cube_view()` does not refuse an aggregation it does not know. It reads it as `"none"`.** The R wrapper checks only that the value is one string. The C++ side lower-cases it, and maps anything unrecognised to `AGG_NONE`, which copies every image in. That copy includes NaNs, so a masked item can blank a clear one. This is how `aggregation = "count"` came back as plausible reflectance.
  - Measured by round-tripping values through `cube_view()$aggregation`. `min`, `max`, `mean`, `median`, `first` and `last` survive, and so do the undocumented `count_values` and `count_images`. `count`, `sum` and `""` become `none`.
  - drift passes only the first six (`aggregation_check()`). `count_*` count **items**, so overlapping MGRS tiles double-count one acquisition, and every drift caller would read the result as reflectance, an index or a class code.
- **`resampling` has the same fallback, to `near` (#96, 2026-10-01).** Measured the same way through `cube_view()$resampling` on 0.7.5:
  - Twelve values come back unchanged: `near`, `bilinear`, `cubic`, `cubicspline`, `lanczos`, `average`, `mode`, `max`, `min`, `med`, `q1` and `q3`. Case is ignored (`Q1 -> q1`).
  - Two are honoured under another name: `mean -> average`, `median -> med`.
  - Everything else becomes `near`, including GDAL's own `sum`, `rms` and `gauss`, plus `nearest`, `none`, `""` and any typo.
  - drift passes only the twelve (`resampling_check()`). It refuses the two aliases, naming the spelling to use, so each method has one spelling and the pin test stays a plain round trip.
- **Count clear days, not items: `dt = "P1D"`, then `reduce_time(cube, "count(B04)", names = ...)`.** Masked pixels are NaN before aggregation, and every aggregation tried (first, max, median) skips NaN within a day. So two same-day tiles give one clear day, and a cloudy tile does not blank a clear one. The string reducer is C++, so the R-callback closure trap above does not apply.
  - `reduce_time()` passes a single-time-step cube through unchanged. A count over a one-day window is therefore the input, not a count.
- **A zero-clear pixel is 0 or NaN depending on chunk layout.** An all-NaN chunk stays empty (NaN), while a pixel in a chunk that holds a clear value somewhere reads 0. Measured on a 128 x 128 fixture: 12,544 zeros at 256 px chunks, against 4,352 zeros plus 8,192 NaN at 64 px. Chunk size follows `gdalcubes_options(parallel =)`, so the raw output depends on a setting drift documents as cost-only.
  - `count_zero_na()` maps 0 to NA, after which the chunkings agree.
  - NA rather than 0, because a failed chunk read is NaN too.
- **`create_image_collection(one_band_per_file = FALSE)` on two-band GeoTIFFs segfaulted a worker** (0.7.5). Separate files per band with a format JSON work. The #92 test fixture uses them.

## Detecting failed chunk reads (#87, 2026-10-02)

Measured on gdalcubes 0.7.5 (`appelmar/gdalcubes@ed68331`) with a local collection whose image is deleted after the collection is built, which fails the read the way an expired signed URL does. Fixture: `chunk_fixture()` in `tests/testthat/helper-gdalcubes.R`.

- **`write_ncdf()` records every chunk's status in the output file**, as an integer variable `chunk_status` with one value per chunk: `0` OK, `1` ERROR, `2` INCOMPLETE, `128` UNKNOWN (`src/gdalcubes/src/cube.cpp`, `cube.h`). A chunk with no status written keeps the netCDF integer fill, `-2147483647`: a worker skips writing a chunk that is OK and all-NA (no image, or fully masked), and a chunk whose merge threw keeps it too. A worker carries the status to the main process inside its chunk file, so the record does not depend on `parallel`:

  | parallel | stderr line | `chunk_status` non-OK | non-NA cells |
  |---|---|---|---|
  | 1, clean (daily, 2 scenes) | none | 0 | 3200 |
  | 4, clean | none | 0 | 3200 |
  | 1, one image gone | printed | 9 of 279 (`2`) | 1600 |
  | 4, one image gone | **not printed** | 9 of 279 (`2`) | 1600 |
  | 4, one image gone, monthly median | not printed | 1 of 1 (`2`) | **1600 of 1600, every cell** |

- **The last row is why a pixel check cannot do this.** A median over two scenes where one failed fills every cell from the survivor, so the holed cube has no NA at all. The issue's third option (require data under every item footprint) would have passed it.
- **Read it with ncdf4, not terra.** GDAL does not list a one-dimensional variable as a subdataset, so `terra::rast(f, subds = "chunk_status")` errors; the `NETCDF:"f":chunk_status` form opens but prints a stray `R_nc4_open` error line. ncdf4 is a gdalcubes import.
- **The `[WARNING]` line is C++ stdio**, so neither an R handler nor `capture.output()` silences it, even at `parallel = 1`.
- **Only one failure is recorded: a band image that fails to open.** gdalcubes sets `chunk_status` in six places, all in `image_collection_cube::read_chunk()`, and only band `GDALOpen` returning NULL can fire in practice; every other I/O step between `GDALOpen` and the final `nc_close` drops its return code or warns and continues. A code-check enumeration of the write pipeline (#87, round 3, `planning/archive/2026-10-issue-87-silent-chunk-read-failures/review-round3.md`) found 38 failure paths: 25 detected by drift (13 through `chunk_status` or the merge warning, 12 as an R error before anything is cached), 13 not. The ones that matter:
  - a band image that opens then fails mid-read: status OK, cells filled from the scenes that read;
  - **a mask (SCL) image that opens then fails mid-read: the scene is used UNMASKED** — cloud values in the median, not NA (measured: an all-cloud scene gave 1600 of 1600 cells, status OK);
  - a mask image that fails to open, or a scene with no mask asset: dropped, or used unmasked;
  - a worker that writes no chunk file, or a partial or unreadable one: status OK or fill, no R warning;
  - a worker killed by a signal: `write_ncdf()` hangs.
  These are drift#99. A chunk whose merge throws keeps fill and raises an R warning (`Chunk N could not be added to output`), which drift does catch.
- `cube_write_ncdf()` is drift's one `write_ncdf()` call, in `stac_cube_assemble()` and `fetch_extent_to()`. It notes the merge warning, lets gdalcubes return (aborting from inside an `Rcpp::warning()` handler would skip its C++ cleanup), then aborts on it or on `chunk_status`, so a failed read aborts before anything is cached. Before it, the offline fixture showed both `dft_stac_composite()` and `dft_stac_fetch()` caching the holed result, tiled and untiled.

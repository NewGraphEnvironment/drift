# Findings — Failed gdalcubes chunk reads are silent: a partial cube passes the empty check and is cached (#87)

## Issue context

## Problem

When gdalcubes cannot read some chunks of a cube (an expired signed URL, a refused or throttled request), it does **not** raise an R warning or error. It prints `[WARNING] n out of m chunks have repoprted errors / incompleteness` and writes the cube with those chunks NA. drift then:

- passes `cube_check_nonempty()` whenever any chunk succeeded;
- **caches the partial cube as complete**, and serves it forever under `force = FALSE`.

This affects `dft_stac_cube()` and `dft_stac_composite()` (shared `stac_cube_assemble()`), and probably `dft_stac_fetch()` (same gdalcubes write).

## How it was found (drift#79, 2026-09-28)

A floodplain-wide composite over BULK (`tile_size = 20000`, 30 tiles) ran for 54 min. Planetary Computer SAS tokens last about 45 min, and every asset had been signed once at query time. **15 of 30 tiles** reported "9 out of 9 chunks" failed. The run died later on an unrelated COG write; otherwise the holed composite would have been cached.

#79 fixes the cause it hit: features are re-signed before each read extent. With corrupted tokens, re-signing read 102,364 cells, against 0 without. **Detection is still missing.** A single extent that outlives a token, or a throttled request, still yields silent NA.

## Why the obvious guard does not work

Capturing stderr around `write_ncdf()` (`capture.output(type = "message")`) and aborting on the report line was tried and measured on the packaged AOI with corrupted tokens:

| gdalcubes `parallel` | image mask | report captured | cells read |
|---|---|---|---|
| 1 | no | 0 (1 in an earlier run of the same probe) | 0 |
| 1 | SCL | 2 | 0 |
| 4 | no | 0 | 0 |
| 4 | SCL | 0 | 0 |

With worker processes (drift's default is `min(4, cores - 1)`) the report never reaches R. A guard that fires sometimes reads as protection it does not give, so #79 did not ship it.

## Options

- Ask gdalcubes for a programmatic error count after compute (look for a debug/log option in 0.7.5). If none exists, propose one upstream: draft it here first, and do not post upstream without approval.
- Pre-flight each extent: `HEAD` one asset URL per item just before the read, and abort on 403 or 404. That catches expired tokens but not mid-read throttling.
- Post-check against an independent expectation: for each item footprint that intersects the extent, require some non-NA cells unless the SCL for that item is fully masked. Expensive, but it discriminates.

## Acceptance

- A read with corrupted tokens, at the default `parallel`, aborts and caches nothing.
- The same holds for a tiled read.
- A normal read is unaffected, and so is the cube cache key.

Relates: drift#79, drift#83


## Plan-mode exploration (2026-10-02)

### chunk_status

When gdalcubes cannot read chunks (expired SAS token, throttling) it prints a
`[WARNING] n out of m chunks …` line and writes NA. drift passes the empty check
whenever any chunk succeeded and caches the holed cube forever. Capturing stderr
was measured unreliable at `parallel > 1` (#79). The issue proposed three options:
ask upstream, HEAD pre-flight, or an independent pixel post-check.

**Exploration found a fourth option, already in gdalcubes 0.7.5.** `write_ncdf()`
writes a per-chunk `chunk_status` int variable into every output file
(`cube.cpp:785/969`; enum `OK=0, ERROR=1, INCOMPLETE=2, UNKNOWN=128`; chunks
never visited stay at NC_INT fill `-2147483647`). In multiprocess mode the status
travels from worker to master inside the chunk file (`cube.cpp:1833/1866`).
Probed offline (local fixture, one image deleted after collection creation):

| parallel | stderr `[WARNING]` | `chunk_status` failures | notNA cells |
|---|---|---|---|
| 1, clean | — | 0 | 3200 |
| 4, clean | — | 0 | 3200 |
| 1, broken | printed | 9 × `2` | 1600 |
| 4, broken | **not printed** | 9 × `2` | 1600 |
| 4, broken, monthly median | not printed | 1 × `2` | **1600 of 1600** |

The last row is the discriminating one: a median over two images where one
failed fills every cell from the survivor, so *no* pixel-based check (including
the issue's option 3) can see it. `chunk_status` does. No upstream ask is needed.

Reader: `ncdf4` (`nc_open` + `ncvar_get`). gdalcubes Imports ncdf4, so it is
present whenever these paths can run; terra/GDAL ignore the 1-D variable as a
subdataset (`rast(f, subds=)` errors) and the `NETCDF:` path form prints a stray
`R_nc4_open` error line. Add `ncdf4` to Suggests.

Write sites (only two): `stac_cube_assemble()`'s `build_stack()`
(`R/dft_stac_cube.R:642`, shared by `dft_stac_cube()` and `dft_stac_composite()`,
tiled and untiled) and `fetch_extent_to()` (`R/dft_stac_fetch.R:632`, both
`dft_stac_fetch()` paths). Both run before any cache publish:
`cache_write_atomic()` removes its temp on error, and the tiled paths abort before
the mosaic. Cache key untouched (no new argument).

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Plan review triage (2026-10-02)

Full summary in `review-plan.md`. Probed offline before acting (scratchpad `probe3.R`,
local fixture, `select_bands(B04)`, monthly median, 9 chunks of 16x16, p = 1 and 4):

| case | p=1 status | p=4 status | non-NA cells |
|---|---|---|---|
| clean, SCL mask | 0x9 | 0x9 | 1600 |
| B04 deleted (open fails) | 2x9 | 2x9 | 1600 |
| B04 truncated (open fails) | 2x9 | — | 1600 |
| **B04 opens, tile data corrupt (read fails)** | **0x9** | **0x9** | 1600 |
| **SCL deleted, SCL mask** | **0x9** | **0x9** | 1600 |

- **Reviewer right on its high-severity claim.** `chunk_status` records only a band
  asset that fails to OPEN. A read that fails after a good open, and a mask asset that
  fails to open, leave status 0 and every cell filled from the surviving scene.
  (A corrupted tile with the IFD intact: `terra::values()` errors, gdalcubes reports OK.)
- `gdalcubes_options(log_file =, debug = TRUE)` writes 11 identical lines for clean and
  failing reads alike, at p = 1 and 4: not a detector either.
- What the guard does cover: an expired or corrupted SAS token, a 403/404 at open — the
  #79 failure (every chunk of 15 tiles failed) and the issue's acceptance test.
- Reviewer's "fill appears only with workers" is wrong: probe 1 showed fill at p = 1
  too. Harmless — the tests run p = 4 regardless.

Plan changes (in the mandate; none touches stored data):
- message drops "throttled"; says a persistent failure is not fixed by re-running
- integration tests at `parallel = 4`; two-year composite (incomplete not swallowed as a
  skip); offset-split assemble with the broken read on the post side; un-wire → red
- tiled fetch: tile cleanup registered before the reads
- GDAL HTTP retries in both session/config blocks, since a transient open failure now
  aborts the run (and retries also shrink the undetectable mid-read class)
- untiled fetch caches are the gdalcubes `.nc`: check `chunk_status` on cache hit and
  treat a failed one as a miss, so holed caches from earlier versions re-fetch
- follow-up issue: read-after-open and mask-open failures are undetected; draft an
  upstream gdalcubes proposal there (set INCOMPLETE on warp/RasterIO and mask-open
  failure) — not posted
- not taken: build_stack's tempfile never unlinked (pre-existing); log_file route (dead)

## Code-check rounds (2026-10-02)

| Round | Findings | Fixed | Accepted / moved | Inside previous fix? |
|---|---|---|---|---|
| 1 | 1 (fill also = unmerged chunk) | 1 (`cube_write_ncdf()` merge warning) | worker-signal hang → #99 | — |
| 2 | 3 | 2 (abort after write returns; retries on every fetch) | unreadable worker chunk file → #99 | **yes**: aborting inside the `Rcpp::warning` handler skipped C++ cleanup |
| 3 | 3 + 4 low, + enumeration | test ordering; notes/roxygen | 9 gdalcubes paths → #99 by class | **yes**: round 2's merge test could not fail (mutant green) |

Ended by enumeration (round 3, `review-round3.md`): 38 failure paths in gdalcubes'
write pipeline — 25 detected by drift, 4 already in #99, 9 added to #99. The
mechanism: gdalcubes sets `chunk_status` only on band `GDALOpen` failure; every other
I/O step drops its return code. Nothing on the list is fixable in drift.

Worst undetected case (measured, round 3): a mask image that opens then fails
mid-read leaves the scene UNMASKED — cloud values in the result, status OK.

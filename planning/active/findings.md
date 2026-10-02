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

# Findings — gdalcubes read failures after open, mask-open failures and worker crashes are still silent (#99)

## Issue context

## Problem

#87 made drift abort on a gdalcubes chunk whose **band image fails to open** (an expired or refused signed URL), by reading the per-chunk `chunk_status` gdalcubes writes into its NetCDF. That is the only failure gdalcubes records. It sets `chunk_status` in six places, all in `image_collection_cube::read_chunk()`, and only band `GDALOpen` returning NULL can fire in practice. **Every other I/O step between `GDALOpen` and the final `nc_close` drops its return code, or warns and continues, leaving the status OK**: `ChunkAndWarpImage`, every netCDF call between worker and main process, `CPLMoveFile`, `sqlite3_step`.

A code-check enumeration of the write pipeline (#87 round 3: 38 failure paths, 25 detected by drift, 13 not; table in the #87 PR's `planning/archive/2026-10-issue-87-silent-chunk-read-failures/review-round3.md`) and offline probes on gdalcubes 0.7.5 (`appelmar/gdalcubes@ed68331`, `parallel` 1 and 4):

| case | `chunk_status` | cells |
|---|---|---|
| **mask (SCL) image opens, then a tile read fails** | OK | **scene used UNMASKED**: the mask buffer stays NaN, which never matches a mask value, so cloud values reach the median (all-cloud scene: 1600 of 1600 cells set) |
| scene with no mask asset | OK | scene used unmasked |
| worker writes no chunk file (`nc_create` / `CPLMoveFile` fails; worker exits 0) | fill, no R warning | those cells `NA` |
| worker chunk file partial (missing dims/vars, or `nc_get_var_double` fails unchecked) | OK | empty, or an uninitialised buffer merged as data (read from source) |
| `sqlite3_step` error in `find_range_st` | OK | chunk's image list silently truncated (read from source) |
| band image opens, then a tile read fails (corrupted tile here; a throttled or refused range request on the network) | OK | every cell set, from the scenes that read |
| mask (SCL) image fails to open | OK | that scene silently dropped |
| a worker chunk file the main process cannot open (e.g. truncated when the temp dir fills) | OK, no R warning | those cells `NA` (measured in the #87 round-2 review: 1536 of 6400 cells, a C++ stderr line only; `chunk_data::read_ncdf()` returns on `nc_open` failure without setting a status) |
| a gdalcubes worker killed by a signal (SIGKILL, segfault) | — | `write_ncdf()` hangs; never raises or returns (round-1 review of #87, measured to a 150 s timeout) |

`gdalcubes_options(log_file =, debug = TRUE)` writes the same 11 lines for clean and failing reads, so it is not a detector either.

Where in gdalcubes (paths under `src/gdalcubes/src/`, from the #87 plan review):
- `image_collection_cube.cpp:424-437` sets INCOMPLETE only when `GDALOpen` fails or `warp()` returns nullptr; `warp.cpp` writes into a MEM dataset it creates first, does not check `ChunkAndWarpImage` (`:256`), and logs a failure only at `GCBS_DEBUG` (`:650-654`).
- `image_collection_cube.cpp:569-579`: a mask that fails to open warns and `continue`s the image loop without `set_status`.

## Mitigation already in drift

#87 added `GDAL_HTTP_MAX_RETRY = 3` and `GDAL_HTTP_RETRY_DELAY = 5` to the cube/composite session and to every `dft_stac_fetch()`, so a transient 429/5xx is retried rather than left as a hole. Per-extent re-signing (#79) keeps tokens live.

## Options

1. **Upstream (preferred):** propose to gdalcubes that a failed warp/RasterIO and a failed mask open set the chunk to INCOMPLETE, and that a worker exiting on a signal is treated as a failed chunk rather than waited on. Draft below. **Do not post without approval.**
2. **drift-side worker timeout:** none exists in gdalcubes; a wall-clock deadline around `write_ncdf()` would need a subprocess. Probably not worth it before upstream answers.

### Draft upstream issue (NOT POSTED)

> **Title:** Failed image reads after a successful open, and failed mask opens, are reported as OK in `chunk_status`
>
> `write_ncdf()` records a per-chunk `chunk_status`, which is very useful for detecting failed reads from R (the console warning is not visible from worker processes). It records a band image that fails to open as INCOMPLETE. Two other failures are recorded as OK:
>
> 1. An image that opens but whose pixel read fails — for a MASK image this leaves the scene unmasked, since the NaN buffer never matches a mask value (e.g. a corrupted tile, or a throttled HTTP range request on `/vsicurl/`). `warp()` writes into a MEM dataset and the result of `ChunkAndWarpImage` is not checked, so the chunk is computed from the remaining images and marked OK.
> 2. A mask band image that fails to open: the image loop `continue`s without `set_status`.
>
> Reproducible offline: build a collection from local GeoTIFFs, then corrupt one band file's tile data with the IFD intact (or delete one mask file), and `write_ncdf()` a median cube: `chunk_status` is 0 everywhere. Would you accept a PR that sets `chunk_status::INCOMPLETE` in both cases?
>
> Also: a worker chunk file the main process cannot open is skipped with status OK (`chunk_data::read_ncdf()` returns on `nc_open` failure without `set_status`), and a worker process killed by a signal leaves the main `write_ncdf()` waiting indefinitely.

Relates: #87, #79




## Plan-mode reading of gdalcubes ed68331 (2026-10-02)


#87 made drift abort on a chunk whose band image fails to OPEN, by reading gdalcubes'
per-chunk `chunk_status`. Several other failures still record OK. The worst is a mask (SCL) image
that opens and then fails to read: the scene is used unmasked and clouds reach the median.
Reading gdalcubes `ed68331` (unchanged upstream as of 2026-10-14) shows the cause is small and
in C++. `gdalwarp_client::warp()` (`warp.cpp:650-655`) logs a failed `ChunkAndWarpImage` at
DEBUG and returns the dataset anyway. `read_chunk()` already sets INCOMPLETE when `warp()`
returns nullptr (band `:516-521`, mask `:627-632`), so returning nullptr there fixes both
mid-read cases. A mask that fails to open (`image_collection_cube.cpp:569-579`) `continue`s
without `set_status`. `chunk_data::read_ncdf()` (`cube.cpp` ~1859-1920) returns on `nc_open`,
missing-dim or missing-var failure without a status, and never checks `nc_get_var_double`.

Precedent: the filter_geom segfault was fixed on `NewGraphEnvironment/gdalcubes`, and upstream
merged it as appelmar/gdalcubes#111 in two weeks. Same route here.

- `raster_cube(incomplete_ok = FALSE)` maps to C++ `_strict`: a band open failure then returns an ERROR (empty) chunk. The strict mask-open branch returns a fresh chunk_data with no status set.
- The worker supervision loop (`src/multiprocess.cpp`) breaks on `exit_status > 0`, and TinyProcess returns 9 for SIGKILL, so a hang is not explained by the loop alone. #87 round 1 saw `returned 9` printed only after SIGTERM to the main process.
- `Missing mask band for image ..., mask will be ignored`: gdalcubes deliberately uses an item with no mask asset unmasked.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Fixture: corrupting a tile with the IFD intact (2026-10-14)

- A plain GTiff written by GDAL puts its IFD at the END of the file, so overwriting the tail
  corrupts the header and tests an OPEN failure. The first probe did exactly that and reported
  band-read failure as INCOMPLETE on unpatched 0.7.5, contradicting #87's measurement.
- COG layout puts the IFDs first. Overwriting the last 30 bytes of a 1391-byte COG still
  decoded (the bytes hit the DEFLATE tail and the COG trailer). What works: parse
  `TileOffsets` (tag 324) from the first IFD and overwrite 64 bytes at the tile start, giving
  `ZIPDecode ... incorrect header check` on read while `gdalinfo` still opens the file.
- `write_tif()` returns every file in the directory with the prefix, not just the ones it
  wrote; two calls with one prefix gave duplicate paths and `cannot add dataset to gdalrefs`.
- tinyexpr in `apply_pixel` has no `t` variable; build each date from its own dummy cube.

## Measurement: gdalcubes fork, branch 99-chunk-status-read-failures

| run | 0.7.5 (`ed68331`) | fork branch |
|---|---|---|
| `test_chunk_status.R`, 30 assertions | 10 fail: band_read / mask_open / mask_read status OK, mask_read lets the cloud value 900 through, strict mask_open not ERROR (each at parallel 1 and 2) | 30 pass |
| `test_worker_failure.R` | both fail at the 120 s `system2` timeout | pass in 0.9 s |
| full tinytest suite | — | 157 / 157 |

## Worker-crash hang: mechanism (2026-10-14)

- Killing a worker MID-write (SIGKILL or SIGSEGV, both builds, parallel 2) raised promptly:
  `[ERROR] worker process #0 returned 9`, then `one or more worker processes failed`, ~6 s.
- Killing a worker at STARTUP (a swapped worker script that SIGKILLs worker 1 before
  `gc_exec_worker()`, the #87 round-1 shape) hung to the 60 s deadline on both builds. Control
  (passthrough worker script): returned in 0.7 s.
- `sample` of the hung main process: no worker children left, state R (100% CPU), hot in
  `chunk_processor_multiprocess::apply()`. The supervision loop had already broken on exit 9.
  The spin is the log printer: `while (!wlogf.eof()) getline(...)` on a worker log that was never
  created; a failed ifstream never reaches eof. The "returned 9" line was buffered and only
  appeared once SIGTERM ended the process.
- Fix: `while (std::getline(wlogf, msg))`. Startup kill now raises in 0.4 s.
- Repro scripts were scratch-only: `hang_main.R`/`hang_run.sh` (mid-write kill),
  `hang_early.R` + `worker_kill9.R` (startup kill). The startup case is now
  `inst/tinytest/test_worker_failure.R` on the fork branch.

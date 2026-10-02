## Outcome

drift now aborts (`drift_incomplete_cube`) with nothing cached when gdalcubes fails to open a band image. That is the expired or refused signed URL that holed 15 of 30 tiles in #79. `cube_write_ncdf()` is drift's single `write_ncdf()` call, used by the cube, composite and fetch paths. It reads the per-chunk `chunk_status` gdalcubes writes into every output and aborts on gdalcubes' merge-failure warning after the write returns. None of the issue's three options was needed. The record already existed in the file, and a pixel post-check could never have seen a median filled from the surviving scene.

The work then found that this is the *only* failure gdalcubes records. Every other I/O step drops its return code. A band or mask image that opens and then fails mid-read leaves status OK, and a failed mask read leaves the scene unmasked. Those moved to #99, with an upstream draft (not posted); GDAL HTTP retries were added as mitigation.

Along the way the new tests found two defects:
- `terra::cover()`'s S4 dispatch stripped the abort class on the offset-split path;
- aborting inside an `Rcpp::warning` handler skips C++ cleanup (code-check round 2).

## Measurement

- **Offline fixture (local GeoTIFFs, one image deleted after the collection is built).** `chunk_status` held 9 × `2` (INCOMPLETE) of 279 chunks at `parallel` 1 **and** 4. The stderr `[WARNING]` line appeared only at 1. A monthly median with one of two scenes failed still had 1600 of 1600 cells set.
- **What is not recorded.** A band file with corrupted tiles but an intact IFD (it opens, then the read fails) gave status 0 × 9, all cells set. A deleted SCL gave 0 × 9. `gdalcubes_options(log_file =, debug = TRUE)` wrote 11 identical lines in clean and failing runs alike. This retracted the plan's claim that the guard covers throttling.
- **Before the fix,** the offline integration tests showed `dft_stac_composite()` and `dft_stac_fetch()` caching the holed result, tiled and untiled.
- **Live acceptance, 8 of 8.**
  - Bad tokens on every asset: composite untiled and tiled, cube, and fetch untiled and tiled all aborted with 0 cache files in 2–10 s.
  - Good-token controls returned and cached: cube over months 6:9 at parallel 4 (266 s), tiled composite (142 s), untiled fetch (8 s).
- **Cost of the check.** 2.3 ms on a 2000 × 2000 cube of 7,936 chunks, the size of one BULK tile at `tile_size = 20000`. It reads one integer per chunk and no pixels, which stood in for a BULK RSS run.
- **Code-check.** Three rounds, ended by enumeration. Round 3 counted 38 failure paths in gdalcubes' write pipeline: 25 detected by drift, 13 not (#99). Rounds 2 and 3 each found a defect inside the previous round's fix: aborting inside the warning handler, then a merge test whose mutant stayed green.

## Evidence

- `data-raw/logs/probe_chunk_status_live/20261002T14*`, made by `data-raw/probe_chunk_status_live.R`.
- The offline fixture is `chunk_fixture()` in `tests/testthat/helper-gdalcubes.R`.
- Review rounds: `review-plan.md`, `review-round[123].md` in this directory.
- Durable notes: `inst/notes/gdalcubes-pc-gotchas.md`, "Detecting failed chunk reads (#87)".
- Follow-ups: drift#99, soul#316.

Closed by: commit 36f2a6f / PR (see `gh pr list --search 87`)

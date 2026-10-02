# Task: Failed gdalcubes chunk reads are silent: a partial cube passes the empty check and is cached (#87)

## Problem

When gdalcubes cannot read some chunks of a cube (an expired signed URL, a refused or throttled request), it does **not** raise an R warning or error. It prints `[WARNING] n out of m chunks have repoprted errors / incompleteness` and writes the cube with those chunks NA. drift then:

- passes `cube_check_nonempty()` whenever any chunk succeeded;
- **caches the partial cube as complete**, and serves it forever under `force = FALSE`.

This affects `dft_stac_cube()` and `dft_stac_composite()` (shared `stac_cube_assemble()`), and probably `dft_stac_fetch()` (same gdalcubes write).

## Phase 1: Chunk-status guard + unit tests
- [x] `tests/testthat/helper-gdalcubes.R`: offline fixture builder (local B04 + SCL
      tifs, `create_image_collection()`), with an option to delete one image after
      the collection is built
- [x] Failing tests for `cube_check_chunks(nc_file)`: clean file passes at
      `parallel = 1` and `4`; broken file aborts (class `drift_incomplete_cube`) at
      both; the monthly-median case with every cell non-NA still aborts; a NetCDF
      with no `chunk_status` variable aborts (fail toward abort, not pass)
- [x] Implement `cube_check_chunks()` in `R/dft_stac_cube.R`: failure = any value
      not in `{0, NC_INT fill}` (so a future status code fails toward abort);
      message names n of m chunks, the likely cause (an image that would not
      open: expired or refused URL — "throttling" dropped, see findings) and that
      nothing was cached
- [x] `ncdf4` → Suggests; restore the bug (no-op the check) and confirm the
      tests go red

## Phase 2: Wire into both write sites
Amended after the plan review and code-check rounds 1-2 (findings.md, "Plan review
triage"; review-round1.md, review-round2.md).
- [x] `cube_write_ncdf()`: drift's one `write_ncdf()` call — notes gdalcubes'
      "could not be added to output" merge warning, aborts on it AFTER the write
      returns (round 2: aborting inside the `Rcpp::warning` handler skips C++
      cleanup), then `cube_check_chunks()`
- [x] Call it in `build_stack()` and `fetch_extent_to()`
- [x] Offset split: build both sides before `terra::cover()` (S4 dispatch was
      re-raising the abort without its class — found by the new test)
- [x] Integration tests at `parallel = 4`, written before the wiring and red
      against it: `dft_stac_composite()` and `dft_stac_fetch()` untiled and tiled
      abort and cache nothing; clean fixture still cached; a two-year composite
      aborts rather than skipping the holed year; offset split with the broken
      read on the post side
- [x] Un-wire (wrapper reduced to a bare `write_ncdf()`) → every wiring test red
- [x] Tiled fetch registers tile cleanup before the reads
- [x] `GDAL_HTTP_MAX_RETRY`/`RETRY_DELAY` in the cube session and (every path) in
      `dft_stac_fetch()`, restored on exit
- [x] Cache gate: an untiled fetch `.nc` whose `chunk_status` records failures is a
      miss and re-fetches (caches from before #87)
- [x] Existing cache-key frozen tests pass unchanged (key not affected)

## Phase 3: Live check, docs, notes
- [x] Live probe `data-raw/probe_chunk_status_live.R` (not a test: run by hand):
      bad tokens on every asset via a spoiling `sign_fn` → composite untiled +
      tiled, cube, fetch untiled + tiled all abort with 0 cache files; good-token
      controls (cube months 6:9 at parallel 4, tiled composite, fetch) return and
      cache. 8 of 8, `data-raw/logs/probe_chunk_status_live/20261002T140832Z.txt`
- [x] Cost instead of a BULK RSS run: `cube_check_chunks()` reads one int per
      chunk, no pixels — 2.3 ms on a 2000 x 2000 cube of 7,936 chunks (one BULK
      tile at `tile_size = 20000`)
- [x] `stac_features_resign()` roxygen; `inst/notes/gdalcubes-pc-gotchas.md`
      "Detecting failed chunk reads (#87)" with the probe table and what is NOT
      recorded
- [x] File drift#99: read-after-open, mask-open, unreadable worker chunk file and
      worker-crash failures stay silent; upstream gdalcubes draft (not posted)
- [x] Edit the #87 issue body: what was found, what is covered, what moved to #99
- [x] `devtools::document()`, `devtools::test()` (1548 pass), lint

## Not in scope (say so in the PR)
- Retrying a failed extent (re-sign + one retry) — would rescue a long tiled run
  instead of discarding it, but is new behaviour; file as a follow-up if wanted.
- Re-signing per tile in `dft_stac_fetch()` (it signs once, like #79's cube path
  did) — detection now catches it; the fix is a separate change.
- Failures `chunk_status` cannot see — drift#99.
- soul `code-check-spatial.md` says "gdalcubes reports failed chunk reads only on
  stderr" — now wrong; flag in the report (soul edits go through an issue).

## Validation
- [x] Tests pass
- [x] `/code-check`: three rounds, ended by enumeration (findings.md)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

# Task: Failed gdalcubes chunk reads are silent: a partial cube passes the empty check and is cached (#87)

## Problem

When gdalcubes cannot read some chunks of a cube (an expired signed URL, a refused or throttled request), it does **not** raise an R warning or error. It prints `[WARNING] n out of m chunks have repoprted errors / incompleteness` and writes the cube with those chunks NA. drift then:

- passes `cube_check_nonempty()` whenever any chunk succeeded;
- **caches the partial cube as complete**, and serves it forever under `force = FALSE`.

This affects `dft_stac_cube()` and `dft_stac_composite()` (shared `stac_cube_assemble()`), and probably `dft_stac_fetch()` (same gdalcubes write).

## Phase 1: Chunk-status guard + unit tests
- [ ] `tests/testthat/helper-gdalcubes.R`: offline fixture builder (local B04 + SCL
      tifs, `create_image_collection()`), with an option to delete one image after
      the collection is built
- [ ] Failing tests for `cube_check_chunks(nc_file)`: clean file passes at
      `parallel = 1` and `4`; broken file aborts (class `drift_incomplete_cube`) at
      both; the monthly-median case with every cell non-NA still aborts; a NetCDF
      with no `chunk_status` variable aborts (fail toward abort, not pass)
- [ ] Implement `cube_check_chunks()` in `R/dft_stac_cube.R`: failure = any value
      not in `{0, NC_INT fill}` (so a future status code fails toward abort);
      message names n of m chunks, the likely causes (expired token, throttling),
      and that nothing was cached
- [ ] `ncdf4` → Suggests; restore the bug (no-op the check) and confirm the
      tests go red

## Phase 2: Wire into both write sites
- [ ] Call `cube_check_chunks(tmp)` in `build_stack()` after `write_ncdf()`
- [ ] Call it in `fetch_extent_to()` after `write_ncdf()`
- [ ] Integration tests (offline; `stac_image_collection` mocked to return the
      broken fixture collection, STAC query helpers stubbed): `dft_stac_composite()`
      untiled and tiled, and `dft_stac_fetch()` untiled and tiled, each abort with
      `drift_incomplete_cube` and leave the cache directory empty; the clean fixture
      still returns a raster and caches it
- [ ] Existing cache-key frozen tests still pass unchanged (key not affected)

## Phase 3: Live check, docs, notes
- [ ] Live probe (opt-in, `DRIFT_TEST_NETWORK=true`): packaged AOI, corrupted `sig`
      on every asset, re-signing stubbed out, default `parallel` → aborts, nothing
      cached; same call with valid tokens succeeds
- [ ] Short-run timing per CLAUDE.md (`/usr/bin/time -l`) on a clean packaged-AOI
      read before/after: the check reads one int vector, so expect no change; record
      numbers for the PR body
- [ ] Update the `stac_features_resign()` roxygen (it says chunk failures cannot be
      reliably captured) and `inst/notes/gdalcubes-pc-gotchas.md` with the
      `chunk_status` finding and the probe table
- [ ] Edit the #87 issue body: the fourth option and why options 1–3 were not taken
- [ ] `devtools::document()`, `devtools::test()`, `lintr::lint_package()`

## Not in scope (say so in the PR)
- Retrying a failed extent (re-sign + one retry) — would rescue a long tiled run
  instead of discarding it, but is new behaviour; file as a follow-up if wanted.
- Re-signing per tile in `dft_stac_fetch()` (it signs once, like #79's cube path
  did) — detection now catches it; the fix is a separate change.
- soul `code-check-spatial.md` says "gdalcubes reports failed chunk reads only on
  stderr" — now wrong; flag in the report (soul edits go through an issue).

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

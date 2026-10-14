# Task: gdalcubes read failures after open, mask-open failures and worker crashes are still silent (#99)

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


## Phase 1: gdalcubes fork fix (NewGraphEnvironment/gdalcubes)
- [x] Clone the fork to `~/Projects/repo/gdalcubes` (no local clone exists). Branch
      `99-chunk-status-read-failures` off **upstream** `appelmar/master` (`ed68331`), kept clean of
      CLAUDE.md/planning so it can go upstream as is, the same way #111 was
- [x] Write the failing tinytest first: `inst/tinytest/test_chunk_status.R`, a local-GeoTIFF
      collection (port of drift's `chunk_fixture()`). It covers (a) a band file whose tile data is
      corrupted with the IFD intact, (b) a deleted SCL, (c) an SCL with corrupted tiles. Each must
      give `chunk_status != 0` in `write_ncdf()` output, at `parallel` 1 and 2
- [x] `warp.cpp`: on a failed `ChunkAndWarpImage`, warn, clean up (close `out`, free warp options), and
      return nullptr in both warp overloads (`:256` and `:650`)
- [x] `image_collection_cube.cpp`: a mask that fails to open sets INCOMPLETE before `continue`. The
      `_strict` branch sets ERROR, like the band path
- [x] `cube.cpp` `chunk_data::read_ncdf()`: set ERROR on `nc_open` / missing dim / missing var
      failure and check `nc_get_var_double`'s return. The legitimate empty-chunk return stays OK
- [x] Build into a scratch library (`R CMD INSTALL -l <scratch>/lib`), so the machine's
      installed gdalcubes is untouched. tinytest green, existing gdalcubes tests green
- [ ] Commit, push the branch to the fork, and open a PR **within the fork** (as fork PR #1 was)

- [x] Plan-review folds (review-plan.md): Initialize/overview-reopen failures, nc_inq_dimlen,
      clean controls (other CRS, partial footprint, overviews), cloud value visible, strict branch
- [x] `/code-check` on the fork branch (3 rounds, ended by a 39-row enumeration); sync fork
      `master` with upstream
- [ ] Push the fork branch; PR into fork `master` after Phase 2 (review G3/O1)

## Phase 2: worker-crash hang (time-boxed diagnosis)
- [x] Reproduce with the scratch-lib build: SIGKILL one worker mid-`write_ncdf()` at `parallel = 2`
      with an external deadline (`timeout`/`with_deadline`). Find where the main process blocks: the
      `multiprocess.cpp` loop, `kill(true)` on the siblings, the TinyProcess destructor, or the
      sh-wrapper pid vs. the R pid
- [x] If the fix is contained, add it with a test to the fork branch. If not, record the mechanism
      and repro in findings and file a drift issue for it
- [x] Either way, record the outcome in `inst/notes/gdalcubes-pc-gotchas.md`

## Phase 3: drift: drop items without a mask asset
- [x] Failing test first, in `test-dft_stac_cube.R`. A feature list where one item lacks the
      mask asset: the item is dropped and the message gives the count. Cover all items lacking it
      (that leaves nothing to read, so expect a legible error, not an empty cube)
- [x] Implement it in `stac_cube_items()` (moved there by plan review B2; was `stac_cube_assemble()`) (`R/dft_stac_cube.R`, before
      `stac_image_collection()`) or wherever `fetched$features` is built, keeping `is_pre`
      aligned. This covers both `dft_stac_cube()` and `dft_stac_composite()`; `dft_stac_fetch()`
      has no mask role and is unaffected

## Phase 4: drift: tests and docs that follow the fork fix
- [x] Capability probe helper in `helper-gdalcubes.R`: does the installed gdalcubes record a
      corrupted-tile read in `chunk_status`? (Test the capability, not a version.)
- [x] Offline tests through `cube_write_ncdf()`: corrupted band tile, deleted SCL and
      corrupted SCL each abort `drift_incomplete_cube` with nothing cached. They skip with a
      drift#99 reason when the probe says the installed gdalcubes lacks the fix. Run them green
      against the scratch-lib fork build, and as SKIP against the installed 0.7.5
- [x] Mutation check (as review O2: probe forced on against 0.7.5 -> exactly the gated tests fail; the tinytest was run against unpatched 0.7.5 too) in the scratch build and confirm the tests go red
- [x] `cube_check_chunks()` abort text: change "an image would not open" to cover open **or
      read** failures, without claiming coverage 0.7.5 lacks. Revise the roxygen for
      `cube_check_chunks()` / `cube_write_ncdf()` and `inst/notes/gdalcubes-pc-gotchas.md`
      ("Detecting failed chunk reads") to say what is recorded with and without the fix
- [x] NEWS.md entry — left to `/gh-pr-merge` (drift writes NEWS in the release commit; #87 did)

## Phase 5: upstream draft (not posted)
- [ ] Update the draft in the #99 body into a PR description for the fork branch: what changes,
      the offline repro, and the tinytest. Include the worker-hang outcome, and the cases left
      unfixed (worker-side `nc_create`/`CPLMoveFile`, `sqlite3_step`)
- [ ] Edit the #99 body to match what was built (body edited, not appended)

## Validation
- [ ] `devtools::test()` green (new tests SKIP on 0.7.5); new tests green on the fork build
- [ ] `lintr::lint_package()`, `devtools::document()`, `pkgdown::check_pkgdown()`
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive`, then `/gh-pr-push` (drift PR). The fork PR is linked; the upstream post is
      left to the user

## Decisions taken at the plan gate (2026-10-02)

- drift keeps `Remotes: appelmar/gdalcubes`. New tests that need the fix are gated on a
  capability probe and SKIP on 0.7.5, naming drift#99.
- STAC items with no mask asset are **dropped, with a message** before the collection is built.
- Worker-killed-by-signal hang: **time-boxed diagnosis**. Fix it in the fork branch if the fix is
  contained; otherwise put it in the upstream draft and a new drift issue.
- Upstream PR/issue: **drafted, not posted**. The user posts it.

## Verification
- Fork: `Rscript -e '.libPaths(c("<scratch>/lib", .libPaths())); tinytest::run_test_file(...)'`
  gives a nonzero `chunk_status` for all three cases, and 0 with the patch reverted
- drift: `NOT_CRAN=true` test run under the scratch lib (the new tests pass) and under the default
  lib (the new tests SKIP with a drift#99 reason)
- No BULK RSS run needed: the drift-side changes read no pixels. The fork patch changes error
  paths only, and the #87 cost measurement (2.3 ms per 7,936 chunks) still holds

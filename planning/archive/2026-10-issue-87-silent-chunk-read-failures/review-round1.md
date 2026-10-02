# Code review — round 1, #87 Phase 1 (`cube_check_chunks()` + tests)

Reviewed the staged diff (DESCRIPTION, R/dft_stac_cube.R, tests/testthat/helper-gdalcubes.R,
tests/testthat/test-dft_stac_cube.R, planning/active/task_plan.md). I worked in a copy
(scratchpad/drift_r1, with unstaged Phase-2 edits reverted to the index) and against gdalcubes
0.7.5 source at the installed SHA ed68331 (cube.cpp, cube.h, and src/multiprocess.cpp, fetched for this review).

## Findings

- **[fragile]** R/dft_stac_cube.R:776 (`failed <- ... & status != -2147483647L`), with the
  roxygen claim at :733-736 — **reading the fill value as "fine" lets an unmerged chunk pass.**
  The docstring says fill marks chunks "gdalcubes never visits, because no image intersects
  them". The source says otherwise. R's gdalcubes always runs `chunk_processor_multiprocess`
  (`gc_set_process_execution`, even at `parallel = 1`). A worker skips writing any chunk whose
  status is OK and whose data is all-NaN (`chunk_data::write_ncdf`, cube.cpp:1808-1811). The main
  process writes `chunk_status` only from inside `f()`, which it calls after a successful
  `read_ncdf()` of a worker's chunk file (multiprocess.cpp:126-142). So fill means **"no chunk was
  merged for this id"**, which covers two cases:
  (a) a worker skipped writing an OK all-NaN chunk. This is legitimate and includes chunks whose
  scenes were fully cloud-masked, not only chunks no image intersects.
  (b) the main process never merged a chunk. One way is a merge exception. That path only calls
  `Rcpp::warning("Chunk N could not be added to output.")` and `continue`s
  (multiprocess.cpp:133-141), so it is an R **warning**, not an error. Another way is a worker that
  exits 0 without writing its chunks.
  Measured (b) in the copy: I swapped the worker script for one where worker 1 exits 0 before
  `gc_exec_worker()`. `write_ncdf()` returned normally, `chunk_status` was 265 fill / 14 OK,
  notNA was 4864 of 6400, and **`cube_check_chunks()` passed**. So the guard is sound for chunks
  that were merged with a non-OK status. Nothing in `chunk_status` separates (a) from (b),
  though. When this is wired in (Phase 2), the write sites should also turn gdalcubes'
  `"could not be added to output"` R warning into an abort, e.g. with `withCallingHandlers()`
  around `write_ncdf()`. The docstring's description of fill should also be corrected, so the
  next reader does not take fill to mean "provably empty". Severity is fragile, not bug: the
  realistic trigger is a merge exception (e.g. `bad_alloc` while reading a chunk file back),
  not the common expired-token case, which this commit does catch.

## Verified clean (checked, no action)

- The tests pass in the copy (5 blocks, 0 failures, about 9 s). The guard is proven to fire.
  When I no-op the abort (`return` before `any(failed)`), tests 2, 3 and 4 go red. When I treat
  fill as failure, test 1 goes red. Both directions are pinned.
- The broken fixture writes status `2` (INCOMPLETE) for 9 chunks and `0` for 9, with 261 fill,
  at both `parallel = 1` and `4`. "9 of 279" matches. With and without `raw_datavals`, ncdf4
  returns the fill as `-2147483647L`, not `NA`: no `_FillValue` attribute is written and
  `missval` is `NA`. So the `!is.na()` term never masks a real value.
- The no-variable branch aborts with the right class (test 45). The message renders. The only
  blemish is a double space where a single `\` continuation meets the next line. That is
  cosmetic and not reported.
- `ncdf4::` from R/ code with ncdf4 in Suggests is not flagged by `R CMD check`. ncdf4 is a hard
  Import of gdalcubes, so it is present whenever the check can be reached.
- The helper's `gdalcubes_options(parallel=)` save/restore uses `on.exit`. Its tempfiles and
  tempdir are scoped to the calling test through `envir = parent.frame()`. It has no top-level
  side effects.

## Out of scope, but you should know (upstream gdalcubes, not this diff)

- When a worker is killed by a signal (SIGKILL as from the OOM killer, or signal 11), the main
  `write_ncdf()` **hangs**. In clean sequential re-runs, both SIGKILL and signal 11 were still
  hung at the 150 s timeout. An earlier SIGKILL run sat for 5 min until I killed it. While it
  hangs it neither raises nor returns, so no chunk-status check is ever reached. The main process
  printed `[ERROR] worker process #1 returned 9` only once it was sent SIGTERM. A worker that
  exits with status 1 (an R error) does raise promptly ("returned 1"). My first "SIGSEGV" probe
  was in fact an R error, because `tools::SIGSEGV` does not exist. The signal-11 result comes
  from the corrected re-run. This
  matters for the floodplain-scale runs CLAUDE.md asks for, and #92 records a real worker
  segfault. I have not diagnosed the mechanism. It may deserve its own issue. Nothing was posted
  upstream.

Probe scripts: scratchpad/r1_probe.R, r1_kill.R, worker_{exit0,segv,kill9}.R, r1_run.R.

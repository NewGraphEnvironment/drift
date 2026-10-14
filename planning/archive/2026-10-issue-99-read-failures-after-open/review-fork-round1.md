# Review: gdalcubes branch `99-chunk-status-read-failures`, round 1

Reviewed: `git diff upstream/master...HEAD` (5 commits, 83eea4c..4175ee1). All changed files were read in full where touched.
Runs: patched lib (scratch `lib`) and unpatched 0.7.5 (default user lib, plus a tinytest-only lib of my own).

## Findings

- **[bug] src/gdalcubes/src/warp.cpp: the new `in == NULL` guard is dead code. The reopen fallback still segfaults (warp_simple, and warp_complex the same way).**
  The fallback sets `in = GDALOpen(descr)` and only warns when that returns NULL. The next
  use is `psWarpOptions->nBandCount = in->GetRasterCount();`, about 50 lines further down,
  and it dereferences NULL before `bool warp_failed = (in == NULL);` is ever reached.
  So the path the guard was written for still crashes the worker.

  The path is reachable. A mask band in a multi-band image with overviews gives a mask
  `bandsel_vrt` made with `GDALTranslate("", ...)`. Its description is `""`, so both the
  `OVERVIEW_LEVEL` open and the full-resolution reopen of `""` fail.

  Reproduced on the patched build: a 2-band 600x600 px COG with overviews, mask = band 2,
  and a 40 m view. The worker log shows `Failed to open GDAL overview dataset for ''`, then
  the new `GDAL could not reopen ''`, then `*** caught segfault *** address 0x70`.
  `write_ncdf()` stops with "one or more worker processes failed". Unpatched 0.7.5
  segfaults the same way, so the branch does not make this worse. But the guard reads as
  handling the case and does not, and the mask read is one of the failures the branch is
  meant to record.

  Fix: before any use of `in` in the else-branch, clean up and `return nullptr`. That means
  destroying the transform, the warp options and `wkt_out`, and `GDALClose(out)`. Better
  still, open the overview dataset *before* closing the original, and close the original
  only when that open succeeds. Then no reopen is needed and the `""`-description VRT keeps
  working at full resolution instead of becoming INCOMPLETE on every chunk. The probe
  script is `scratchpad/rv1/ovprobe.R`.

- **[fragile] inst/tinytest/test_chunk_status.R: the "reprojected read is OK" control reads no pixels, so it passes without testing anything.**
  The fixture is EPSG:32610 x/y 0..400. In EPSG:32609 that sits at x ≈ 668,185..668,584,
  y ≈ 0..399. The view extent `c(-4500000, -4499000, 0, 1000)` does not overlap it.
  Measured: 0 of 20,000 values are non-NA, so no reprojecting warp ever runs.

  It cannot catch a spurious `ChunkAndWarpImage` failure under reprojection, and that
  false positive is the main risk of the warp change. With `extent = c(668000, 669000, -300, 700)`:
  - the clean case reads 1,600 values and every chunk is OK, so the code itself is fine;
  - `band_read` under reprojection gives status 2 on the affected chunks.

  Fix: use an overlapping extent, and add `any(!is.na(r$values))` to this control as the
  first control already has.

## Checked and fine

- Ownership on every warp path: `in` is closed exactly once inside `warp()` on success and
  on failure. `out` is closed only on failure and returned otherwise. The transform and the
  warp options are destroyed before return. No caller closes `g` or `bandsel_vrt` after
  `warp()`, so there is no double close. In warp_complex, `tmparg` is restored before
  `GDALDestroyGenImgProjTransformer` on the failure path too. In the overview-reopen
  fallback, the transformer built from the old `in` holds copied geotransform values (or a
  GenImgProj info that is still valid), not the closed handle. That is an improvement on
  upstream, where `hSrcDS` pointed at a closed dataset.
- `in->GetDescription()` in the new WARN runs only when `!warp_failed`, so `in` is non-NULL there.
- `read_ncdf`:
  - `buf(nullptr)` frees the buffer because `size()` is still non-zero at that point, and
    `size({0,0,0,0})` then makes the chunk `empty()`.
  - Every early return closes the file. The branch adds the missing close on the empty-chunk return.
  - Non-OK chunks are written by workers even when they are empty or all NaN
    (`chunk_data::write_ncdf` skips only OK + all-NaN), so ERROR and INCOMPLETE status
    reaches the main process.
- multiprocess log loop: a missing file fails the first `getline`. A final line with no
  newline is still printed because `getline` sets eof, not fail.
- Restore-the-bug, measured:
  - test_chunk_status.R: 30/30 pass on the patched build and 10/30 fail on unpatched 0.7.5.
    Those 10 are every status assertion for band_read, mask_open and mask_read, the
    mask_read 900 check and the strict check, at both parallel settings.
  - test_worker_failure.R: 2/2 pass in about 1 s on the patched build. The child prints
    `worker process #1 returned 9` and then `RESULT raised`. On unpatched 0.7.5 both
    assertions fail on the 120 s timeout (status 124, about 140 s wall). Afterwards no
    orphan main or worker R processes were left.
- The netCDF fill (-2147483647, NC_INT) is mapped to OK only for chunks that were never
  written. The clean controls would fail if the mapping were wrong. The overview control
  really does use an overview: the 600 px COG has 300 and 150 px overviews.
- The `sf`-absent skip of the "file still opens" check only weakens the check that
  band_read is not an open failure. In this environment the status assertions fail
  pre-branch, so they are not vacuous here.

## Noted, not findings

- Now that `warp()` can return nullptr, the `!gdal_out` `continue` in read_chunk's band loop
  is reachable, and it skips `filesystem::remove(bandsel_vrt_name)`. Each failed warp of a
  multi-band image leaks a few KB of `/vsimem` VRT. This is the same class as the accepted
  out-of-scope RasterIO-failure leak, and small.

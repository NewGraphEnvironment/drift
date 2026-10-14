# DRAFT — upstream PR to appelmar/gdalcubes (NOT POSTED)

Head: `NewGraphEnvironment:99-chunk-status-read-failures` → base: `appelmar:master` (`ed68331`).
Posting needs the user's explicit approval. Nothing below has been sent anywhere.

---

**Title:** Record failed image reads and mask failures in `chunk_status`; fix hang when a worker dies early

`write_ncdf()` writes a per-chunk `chunk_status`, which is the only signal R can rely on for failed
reads (the `[WARNING] n out of m chunks` line comes from C++ stdio and never reaches R from a worker
process). Today it records one failure: a band image that fails to open. Several others leave the
chunk OK. The worst is a mask image that opens and then fails to read: the scene is used
**unmasked**, since a NaN mask value never matches a mask class.

### Changes

- **`warp_simple()` / `warp_complex()`: a failed warp returns `nullptr`.** `ChunkAndWarpImage()`'s
  result was ignored in `warp_simple()` (every image with a geotransform), and only logged at DEBUG
  in `warp_complex()`, so the `INIT_DEST=nan` output came back as if it were data. Now a failed
  `Initialize()` or `ChunkAndWarpImage()` warns and returns `nullptr`, after the existing cleanup.
  `read_chunk()`'s existing `!gdal_out` branches then mark the chunk INCOMPLETE (ERROR when
  strict), for band and mask images alike. A partially warped image is discarded rather than
  merged, which is the intended INCOMPLETE behaviour.
- **Overview open no longer closes the source first.** If opening the overview level failed, the
  source had already been closed and `hSrcDS` pointed at it. The overview is now opened into its own
  handle, and the source is closed only when that succeeds.
- **`read_chunk()`: a mask image that fails to open sets INCOMPLETE** (the strict branch returns an
  ERROR chunk, like the band path). It used to `continue` without a status.
- **`chunk_data::read_ncdf()`: failures set ERROR.** A worker chunk file the main process cannot
  open, whose dimensions or variable are missing, whose dimension sizes cannot be read, or whose
  `nc_get_var_double()` fails, was merged with status OK (and in the last case an uninitialised
  buffer). These set ERROR and discard the buffer. The empty-chunk return keeps its recorded status
  and now closes the file.
- **`chunk_processor_multiprocess::apply()`: no more hang when a worker dies before writing its
  log.** After a worker fails, each worker's log is printed with `while (!wlogf.eof())`; for a
  worker killed by a signal at startup the log file never exists, the stream is in a failed state
  and never reaches `eof()`, and the main process spins at 100% CPU forever. Loop on `getline()`.

### Behaviour changes worth knowing

- `ChunkAndWarpImage()` also fails when GDAL cannot compute a source window (e.g.
  `ERROR_OUT_IF_EMPTY_SOURCE_WINDOW`, or the transformer failing). Such an image used to give
  silent NaN with status OK; it is now INCOMPLETE, and with `incomplete_ok = FALSE` its chunk is
  ERROR.
- `read_chunk()` escalates INCOMPLETE to ERROR only when `count_success == 0`, and
  `count_success` counts images processed, not images read; so a chunk where every band read
  failed is INCOMPLETE rather than ERROR. Warp failures inherit that existing rule.
- Opening the overview before closing the source also fixes a worker segfault on 0.7.5 when a
  band read through a band-selection VRT (one band of a multi-band file) goes through overviews
  with a mask (measured in review: 0.7.5 worker returns 11; this branch gives status 0).

### Tests

- `inst/tinytest/test_chunk_status.R` builds a two-date collection of single-band COGs (a band and
  an SCL-style mask) from dummy cubes, and breaks the second date three ways: a band file with its
  first tile corrupted (IFD intact, so it opens and then fails to decode), a deleted mask file, and
  a corrupted mask file. At `parallel` 1 and 2, each must give a non-OK status, and the cloud value
  of the second scene must never reach the output; strict mode with a missing mask must give
  ERROR. Clean controls must stay OK: same CRS, a source in another CRS, a view only partly covered,
  and a coarser view read through overviews. 32 assertions: **10 fail on 0.7.5, all pass here.**
- `inst/tinytest/test_worker_failure.R` runs `write_ncdf()` in a child R process, with a worker
  script that SIGKILLs worker 1 at startup, under `system2(timeout = 120)`: on 0.7.5 it times out,
  here it raises in about a second. Unix only.
- Full suite: 159 / 159 (macOS arm64, GDAL 3.13.0, R 4.5).

### Not covered

- The `read_ncdf()` ERROR paths have no test: there is no public hook to hand the main process a
  damaged chunk file.
- A worker that cannot create or move its chunk file (`nc_create` / `CPLMoveFile` unchecked in
  `exec()`) still leaves the chunk at fill with no warning, and an `sqlite3_step` error in
  `find_range_st` still truncates a chunk's image list silently.
- Pre-existing, separate: a two-band image with the mask in band 2 segfaults a worker (at full
  resolution and through overviews alike, on 0.7.5 too). Happy to open an issue with the repro.
- Pre-existing, separate: in `warp_complex()`, a successful overview open replaces a
  `GDALGenImgProjTransformInfo` through `destroy_transform()`/`create_transform()` (the
  `warp_simple()` transformer type), so a GCP- or geolocation-georeferenced image with overviews
  segfaults a worker when `use_overview_images` is on (the default), on 0.7.5 too. Not changed
  here; happy to open an issue with the repro (a GCP-only GTiff with `gdal_addo` overviews, 80 m
  view).
- Existing leaks on `read_chunk()`'s `continue` paths (the `/vsimem` band-selection VRT is not
  removed and `gdal_out` is not closed after a failed RasterIO) are left as they are, to keep this
  diff small.

---

Fork PR (our repo, inside the mandate): opened against `NewGraphEnvironment/gdalcubes:master`
after syncing fork `master` with upstream.

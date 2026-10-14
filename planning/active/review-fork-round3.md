# Review round 3: gdalcubes fork `99-chunk-status-read-failures` (HEAD 7afdd3e vs upstream/master ed68331)

Reviewer: subagent, round 3. Read in full: warp.cpp (warp, warp_simple, create_transform,
destroy_transform, warp_complex), image_collection_cube.cpp read_chunk, cube.cpp
chunk_data::write_ncdf / read_ncdf and the write_ncdf merge callback, cube.h chunk_data,
multiprocess.cpp apply/exec, tiny-process `try_get_exit_status`, both new tinytest files.

## Mechanism

Every finding so far comes from one assumption: **a handle and the state that refers to it
change together on every exit path.** The handle is `in`, the overview handle, `out`, the
transformer arg, a chunk buffer or the netCDF id. The state is `psWarpOptions->hSrcDS`,
`pTransformerArg`, `_size`, `chunk_status`, or what the caller assumes it still owns. The
plan-review bug: `in` was released before its replacement existed, so `hSrcDS` pointed at a
closed dataset. The round-1 bug, inside the fix for that: `in` was rebound to NULL and then
read (`GetRasterCount`) before the guard. The round-2 note: the transformer was swapped for
one of a different *type*, but the release code still assumed the original type. The tell
in each case is a reassignment or release that the code path after it does not see.

## Enumeration (table)

Every exit path, and every reassignment or release of a tracked object, in the functions the
diff touches. "Branch?" says whether the row is new or newly reachable on this branch.

### warp_simple

| # | path | what is held | released / set | consistent? | branch? |
|---|------|--------------|----------------|-------------|---------|
| S1 | MEM driver missing → `throw` | `in`, `wkt_out` | nothing | no (leaks) | pre-existing |
| S2 | `create_transform` throws (non-invertible geotransform), first call | `in`, `out`, `psWarpOptions`, `wkt_out` | nothing | no (leaks) | pre-existing |
| S3 | overview: `in_ov = GDALOpenEx(descr)` succeeds | `in`, `in_ov`, transformer(in) | `GDALClose(in)`; `in = in_ov`; transformer destroyed and rebuilt from `in_ov`; `hSrcDS = in` | yes: all three refer to `in_ov` | rewritten |
| S4 | overview: `in_ov == NULL` (e.g. mask VRT with description `""`) | `in`, transformer(in) | nothing changes; WARN | yes: `in`, `hSrcDS` and the transformer still match. Measured: mask path warns 18x, output correct | new (was a NULL deref) |
| S5 | S3, then `create_transform(in_ov)` throws | `in_ov` (as `in`), `out`, options holding a destroyed transformer | nothing | no (leaks; dangling arg never used because of the throw) | same order as before, pre-existing |
| S6 | `oo` | CSL list | `CSLDestroy(oo)` after either branch | yes | rewritten |
| S7 | `x`, `y`, `succ` | malloc buffers | freed after the overview block | yes | unchanged |
| S8 | nodata count mismatch | `src_nodata*` (CPLMalloc) | `std::free`, never assigned to the options | yes (CPLMalloc/free mix, pre-existing) | unchanged |
| S9 | `Initialize` fails | options, transformer, `wkt_out`, `in`, `out` | transformer, options, `wkt_out` freed; `in` closed; `out` closed; returns nullptr | yes | new |
| S10 | `ChunkAndWarpImage` fails | as S9 | WARN reads `in->GetDescription()` *before* `in` is closed; then as S9 | yes | new |
| S11 | success | as S9 | transformer, options, `wkt_out` freed; `in` closed; `out` returned | yes (ownership of `in` passes to warp, as upstream) | unchanged |
| S12 | `oOperation` destructor runs after `in`/`out` are closed (S9/S10: `out` too) | its own cloned options | WipeOptions / thread teardown, no dataset access | yes | `out` closed before dtor is new; harmless |

### warp_complex

| # | path | what is held | released / set | consistent? | branch? |
|---|------|--------------|----------------|-------------|---------|
| C1 | MEM missing → throw | `in`, `wkt_out` | nothing | no | pre-existing |
| C2 | `psInfo == NULL` → throw | `in`, `out`, options, `wkt_out` | nothing | no | pre-existing |
| C3 | overview `in_ov` succeeds | `in`, `in_ov`, GenImgProj `psInfo` with a cached reproj arg swapped in | `in` closed, `in = in_ov`; `psInfo` freed via `destroy_transform` (wrong type); a `gdalcubes_transform_info` is installed, but `pfnTransformer` is still `GDALGenImgProjTransform`, and the end-of-function `static_cast<GDALGenImgProjTransformInfo*>` writes through it | no | pre-existing (round 2); reachability unchanged, since the open succeeds under the same conditions as before |
| C4 | overview `in_ov == NULL` | `in`, `psInfo` | nothing changes; WARN | yes: `psInfo` was built from `in` and is restored and destroyed normally | new (was a NULL deref) |
| C5 | `oo`, `x/y/succ` | as S6/S7 | as S6/S7 | yes | rewritten |
| C6 | `Initialize` fails | `psInfo`, options, `wkt_out`, `in`, `out` | `pReprojectArg = tmparg`; `GDALDestroyGenImgProjTransformer`; options and `wkt_out` freed; `in` and `out` closed; nullptr | yes (off the C3 path) | new |
| C7 | `ChunkAndWarpImage` fails | as C6 | WARN before `in` is closed; then as C6 | yes | new |
| C8 | success | as C6 | as C6, `out` returned | yes | unchanged |

### image_collection_cube::read_chunk (paths that consume the changed warp contract or were edited)

| # | path | what is held | released / set | consistent? | branch? |
|---|------|--------------|----------------|-------------|---------|
| R1 | band dataset: warp returns nullptr, strict | `img_buf`, `mask_buf`, `agg`, `out` (calloc buf), `g` when bandsel is used, the /vsimem VRT file | bufs freed, `agg` deleted; `out` replaced by an empty chunk with status ERROR, and the old chunk's dtor frees its buffer; warp already closed `in` | yes for buffers and status; `g`/vsimem leak is pre-existing | newly reachable |
| R2 | band dataset: warp nullptr, non-strict | same | INCOMPLETE; `continue` (the `for` over datasets); the band slice stays NaN; image still fed to `agg`, `count_success++` | status yes; see P5 for `count_success` | newly reachable |
| R3 | the caller's `g` after warp | the caller's pointer | warp closed it (or closed the VRT); neither branch touches `g` after warp | yes (same contract as upstream, measured) | unchanged |
| R4 | mask open fails, strict | `img_buf`, `mask_buf`, `agg`, `out` | freed; `out` = empty chunk with ERROR (was OK) | yes | new |
| R5 | mask open fails, non-strict | as R4; `g` NULL | INCOMPLETE; `continue` (the `while`, so the image is skipped and not counted) | yes; matches the mask-warp and mask-RasterIO paths | new |
| R6 | mask warp nullptr, strict / non-strict | as R4; mask `g` when bandsel is used | as R4 / R5 | yes (`g` leak pre-existing) | newly reachable |
| R7 | end: INCOMPLETE and `count_success == 0` → ERROR; all-NaN → empty chunk keeping its status | `out` | status carried across the replacement | yes | unchanged |

### chunk_data::read_ncdf (multiprocess master)

| # | path | what is held | released / set | consistent? | branch? |
|---|------|--------------|----------------|-------------|---------|
| N1 | `nc_open` fails | nothing | ERROR; return | yes | new |
| N2 | dimension id missing | `ncfile` | ERROR (overrides the status read from the file); `nc_close` | yes on NetCDF-4 builds; see note A | status is new |
| N3 | variable missing | `ncfile` | ERROR; `nc_close` | yes | status is new |
| N4 | any `nc_inq_dimlen` fails | `ncfile` | ERROR; `nc_close` | yes | new |
| N5 | zero-length dimension (empty non-OK chunk) | `ncfile` | `nc_close` (was leaked); status from the file attribute | yes; measured an empty INCOMPLETE chunk reading back as 2 under `parallel = 2` | close is new |
| N6 | `nc_get_var_double` fails | `ncfile`, `_buf` (malloc), `_size` set | `buf(nullptr)` frees (size still > 0), then size zeroed, ERROR, `nc_close` | yes; buffer and size agree, and `empty()` is true for the merge callback | new |
| N7 | success | `ncfile`, `_buf`, `_size` | `nc_close` | yes | unchanged |
| N8 | malloc returns NULL on a huge chunk | NULL `_buf` | passed to `nc_get_var_double` | no | pre-existing |

### chunk_processor_multiprocess::apply, worker-log loop

| # | path | what is held | released / set | consistent? | branch? |
|---|------|--------------|----------------|-------------|---------|
| L1 | log file missing | failed `ifstream` | `getline` is false at once; dtor closes | yes (was an infinite loop) | new |
| L2 | log present, last line has no newline | stream | `getline` returns the line, then false | yes (that line is still printed) | new |
| L3 | read error (badbit) | stream | `getline` false | yes | new |
| L4 | merge callback on an ERROR chunk from N1–N6 | empty `dat` | status written; data write skipped because `empty()`; file removed | yes | newly reachable |

## Clean

None of the rows the branch introduced or made reachable is inconsistent. Every
inconsistent row is pre-existing: S1, S2, S5, C1, C2, C3 and N8.

What I checked:
- Both new tinytest files pass against the patched build: test_chunk_status.R 32/32,
  test_worker_failure.R 2/2.
- **Band-selection VRT and overview** (a 2-band 600 px COG with overviews; B04 requested
  alone, so it goes through `/vsimem/*.vrt`; SCL mask in band 1). On the patched build,
  with and without the mask and at `parallel` 1 and 2: status 0 and values 500. The debug
  log shows the "Failed to open GDAL overview dataset for ''" fallback 18 times, which is
  exactly 9 chunks x 2 dates on the mask path only. The `/vsimem` band VRT still opens
  its overview *before* the source is closed, because GDALTranslate flushes a named VRT.
  So the new open-then-close order did not cost the band path its overviews (rows S3/S4).
  The unpatched 0.7.5 build segfaults on the masked case (`address 0x70`, worker returned
  11): this is the bug the plan review found, and S4/C4 fix it.
- **Empty INCOMPLETE chunk through the multiprocess master** (rows N2/N5). One image is all
  nodata, the other is deleted after the collection is built. The output is 0 non-NA
  cells, and chunk_status reads 2 at both `parallel = 1` and `parallel = 2`, on both the
  patched and unpatched builds.
- The test fixtures do reach their failure modes: the corrupted COG still opens; the
  6000 m / dx 40 case does select overview level 1; the killed worker leaves no log; and
  under tiny-process a SIGKILL'd child of `sh -c` reports exit 137 > 0, so `any_failed` is set.

## Pre-existing (not findings)

- P1 (S1, S2, C1, C2, S5): leaks of `in`, `out`, options and `wkt_out` on throw paths in
  warp_simple and warp_complex.
- P2 (C3): the warp_complex overview success path replaces a GenImgProj transformer with a
  `gdalcubes_transform_info` without changing `pfnTransformer`, then
  `static_cast<GDALGenImgProjTransformInfo*>` writes `pReprojectArg` into it. It also
  `delete`s the original as the wrong type. Round 2, accepted, noted for upstream.
- P3: in the band path, when a band-selection VRT is used, `g` is never closed, and the
  `/vsimem` VRT file is not removed on any `continue`. The mask path leaks `g` the same way.
- P4 (N8): a NULL malloc in read_ncdf is passed straight to `nc_get_var_double`.
- P5: in read_chunk, `count_success` counts images *processed*, not images read. A band
  open, warp or RasterIO failure `continue`s only the inner `for`, so the image is still
  counted. As a result `INCOMPLETE && count_success == 0 → ERROR` fires only for mask
  failures. A chunk whose every band read failed is recorded INCOMPLETE, not ERROR. The
  branch follows the existing shape (the upstream open-failure path is identical), so the
  only effect is that warp failures inherit it. The tests assert `status != 0`, which is
  why they cannot see it.
- P6: the src_nodata mismatch branch frees CPLMalloc memory with `std::free`.

## Notes (behaviour changes, not defects)

- A. N2 under classic-model netCDF: only `USE_NCDF4 == 0` builds are affected, which
  `cube.cpp` sets only on Solaris. A classic file allows one unlimited dimension; I
  measured `nc_def_dim` returning -54 for the second zero-length dimension. So an empty
  non-OK chunk is written without `t`/`y`/`x`, and N2 now reads it back as ERROR instead
  of its recorded INCOMPLETE. This does not reproduce on NetCDF-4 builds (measured above).
- B. `ChunkAndWarpImage` also returns `CE_Failure` when GDAL cannot compute a source window.
  Two ways that happens: "Too many points failed to transform", where
  `ERROR_OUT_IF_EMPTY_SOURCE_WINDOW` defaults to TRUE (the option is in the linked GDAL
  3.13); and gdalcubes' own `transform()` returning 0 when OGR reports a partial
  reprojection failure. Before this branch, such an image silently contributed NaN with
  status OK. Now it is INCOMPLETE, and under `incomplete_ok = FALSE` it is ERROR, which
  discards the whole chunk, including the other images' data. This matches the PR's intent
  (a dropped image is now reported), but the PR body could say it, since strict users near
  a CRS domain edge would see chunks that used to succeed now fail.

# Review round 2: gdalcubes `99-chunk-status-read-failures` (HEAD 7afdd3e vs upstream/master ed68331)

## Findings

- **[severity: bug, pre-existing, not a regression]** src/gdalcubes/src/warp.cpp:574-580 (`warp_complex`, overview-success branch)
  When the overview opens, this branch treats `psWarpOptions->pTransformerArg` as a
  `gdalcubes_transform_info`, but in `warp_complex` it is a `GDALGenImgProjTransformInfo`
  (from `GDALCreateGenImgProjTransformer2`, line ~525). Three things go wrong:
  1. `destroy_transform()` `delete`s the GDAL struct through the wrong type.
  2. `create_transform()` installs a `gdalcubes_transform_info` while `pfnTransformer` is still
     `GDALGenImgProjTransform`.
  3. At the end, line ~683 casts that struct back to `GDALGenImgProjTransformInfo`, writes
     `pReprojectArg = tmparg` into it and calls `GDALDestroyGenImgProjTransformer()` on it.

  Result: heap corruption or a segfault every time a GCP- or geolocation-georeferenced image
  (no geotransform, for example Sentinel-1 GRD COGs) has overviews and `use_overview_images`
  is TRUE (the default).

  Reproduced on both builds. The image is a GCP-only GTiff (4 GCPs, EPSG:32609), read through
  a `stac_image_collection(url_fun = identity)`, with an 80 m view over the 10 m image:
  - With `gdal_addo` overviews, the worker dies with `caught segfault` / `worker process #0
    returned 11`, on HEAD 7afdd3e and on unpatched 0.7.5 alike.
  - Without overviews, the same image returns status 0 and values 7 on both builds.

  So the overview-first change in 7afdd3e fixes the overview-open **failure** path in both
  functions. In `warp_complex` it keeps the wrong transformer on the **success** path, which
  is the only path that still differs from `warp_simple`. That is the answer to "does the
  overview-first change leave the transformer wrong on any path".

  Fix options:
  - On success, set `psInfo->pReprojectArg = tmparg`, call
    `GDALDestroyGenImgProjTransformer(psInfo)`, rebuild the transformer with
    `GDALCreateGenImgProjTransformer2(in, out, trnsfrm_opts.List())`, save the new `tmparg`,
    and re-apply the cache override.
  - Or skip overview selection in `warp_complex` altogether.

  Out of scope for #99 if you prefer, but it sits inside the block this branch rewrote, so it
  is worth an upstream issue at least. Repro script:
  `/private/tmp/claude-501/-Users-airvine-Projects-repo-drift/385a1665-8b28-46b0-9826-7e0ccfdfac92/scratchpad/r2/gcp2.R`
  (args: `1 ov` or `1 noov`).

## Checked and found correct

- **`warp_simple`, overview failure** (for example the mask band-select VRT, whose description
  is `""`): `in`, `hSrcDS` and the transformer all still refer to the original dataset, and the
  original is closed exactly once at the end.
- **`warp_simple`, overview success:** the original is closed once (as on upstream). `in_ov`
  becomes `in`, with a matching transformer and `hSrcDS`, and is closed once at the end.
- **Caller-created VRT ownership** is unchanged from upstream: `warp()` owns and closes its
  input on every path. The /vsimem band-select VRT (band path) still opens its overview while
  the original is open. A 3-band COG with one band selected at 80 m gave status 0 and values 5,
  with no "Failed to open GDAL overview" warning, on both builds.
- **`warp_failed`:**
  - It is set only on an `Initialize` or `ChunkAndWarpImage` failure.
  - `ChunkAndWarpImage` is skipped after an `Initialize` failure.
  - `in` is non-null where its description is logged.
  - `out` is closed before `nullptr` is returned.
  - Every `warp()` caller (`image_collection_cube.cpp` lines 500/505 and 614/619) already
    handles `nullptr` (INCOMPLETE, or ERROR when strict).
  - Clean controls stay OK, including `warp_complex` without overviews (status 0 above).
- **`read_ncdf`:** the new ERROR paths free the buffer correctly. `buf(nullptr)` frees while
  size is still set, and size is then zeroed. The merge lambda writes the status for an empty
  chunk.
- **`multiprocess.cpp`:** the `getline` loop terminates on a missing file and still prints a
  final line that has no trailing newline.
- **Tests:** `test_chunk_status.R` passes 32/32 and `test_worker_failure.R` passes 2/2 against
  the patched library (R_LIBS = scratch lib).

## Verdict

No regression introduced by the branch. One pre-existing segfault remains in the code that
7afdd3e touched, on the `warp_complex` overview-success path.

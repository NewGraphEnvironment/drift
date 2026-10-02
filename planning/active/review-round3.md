# Code review: round 3, #87 (staged diff), enumeration of gdalcubes failure paths

Worked in a copy (`scratchpad/drift_r3`) against the gdalcubes source at the installed SHA
`ed683314` (0.7.5), fetched for this review: `src/multiprocess.cpp`, `src/gdalcubes.cpp`,
`src/gdalcubes/src/{cube.cpp,cube.h,image_collection_cube.cpp,image_collection_cube.h,
image_collection.cpp,warp.cpp,apply_pixel.cpp,apply_pixel.h,select_bands.cpp,reduce_time.cpp,
filesystem.cpp}`, `R/{cube.R,zzz.R,config.R,plot.R}`, `inst/scripts/worker.R`. Probes ran under
`timeout`; no worker process was left running (checked with `ps`).

## Mechanism

The assumption the earlier instances share is that every failure on the path from an image to
the output NetCDF either sets a non-OK `chunk_status` or raises in R. The source shows the
opposite design. gdalcubes sets a status in exactly six places, all in
`image_collection_cube::read_chunk()`: band open, band warp returns nullptr, band RasterIO, mask
warp returns nullptr, mask RasterIO, and all images failed. Every other failure is one of two
things. Either it is a dropped return code (`ChunkAndWarpImage`, every netCDF call on the
worker-to-master hand-off, `CPLMoveFile`, `sqlite3_step`), or it is a `GCBS_WARN` plus `continue`
that leaves the status OK. **Status is set at those six points. Nothing propagates it from the
I/O layers underneath them.** The six points are reachable in practice only through `GDALOpen`
returning NULL: the RasterIO calls read a MEM dataset, and `warp()` never returns nullptr after
`Create()` succeeds.

So the set drift#99 needs to cover is "every unchecked I/O return between `GDALOpen` and
`nc_close`", not a list of instances. The enumeration below finds five instances that are
neither detected nor in #99. Two are measured.

## Findings

- **[fragile]** gdalcubes `image_collection_cube.cpp:620-656` with `warp.cpp:650-654`; drift
  `R/dft_stac_cube.R` roxygen of `cube_check_chunks()` and `inst/notes/gdalcubes-pc-gotchas.md:450`.
  **A mask (SCL) image that opens and then fails mid-read unmasks the whole scene, with status
  OK.**
  - **Mechanism.** The mask is warped into a MEM dataset pre-filled with NaN. A failed
    `ChunkAndWarpImage` is unchecked, so `mask_buf` holds NaN. `value_mask::apply`
    (`image_collection_cube.h:55`) masks a pixel only when `_mask_values.count(v) == 1`, and NaN
    never matches. Every pixel is therefore kept.
  - **Measured** (`scratchpad/r3_maskread.R`). One scene with B04 = 500 and SCL = 9 (cloud)
    everywhere, `image_mask("SCL", values = c(8, 9))`, monthly median, 9 chunks:

    | SCL file | p=1 non-NA | p=4 non-NA | `chunk_status` |
    |---|---|---|---|
    | readable | 0 of 1600 | 0 of 1600 | fill x9 |
    | opens, DEFLATE tile corrupt (`ZIPDecode` error on read) | **1600 of 1600** | **1600 of 1600** | **0 x9** |

  - **Why it is not a duplicate of #99.** #99 row 1 (band mid-read) loses data from the median,
    which leaves fewer scenes. Row 2 (mask open fails) drops the scene. This one admits cloud and
    shadow **values** into the composite and the index trajectory: wrong numbers, not missing
    ones. No pixel check can see it, and nothing else does either. Retries reduce the risk; the
    upstream fix in #99's draft (failed warp sets INCOMPLETE) would close it only if it also
    covers the mask's warp. #99, its draft and the notes bullet at `gdalcubes-pc-gotchas.md:450`
    should name this case.

- **[fragile]** gdalcubes `src/multiprocess.cpp:241-244`, `cube.cpp:1801-1820`,
  `filesystem.cpp:193-195`. **A worker that produces no chunk file at all passes both guards.**
  - **Trigger.** `chunk_data::write_ncdf()` ignores `nc_create`'s return code. `exec()` then
    moves the file only `if (filesystem::exists(outfile_temp))`, and `CPLMoveFile`'s return is
    discarded. A worker that cannot create or rename its chunk file therefore skips the chunk
    silently and exits 0. Causes: `EACCES`, `ENOSPC`/quota at create, a failed rename-copy
    fallback.
  - **Consequence.** The master never merges the chunk. It keeps fill (read as OK), and no R
    warning is raised.
  - **Measured in round 1** (a worker exiting 0 without writing): 265 fill / 14 OK, 4864 of
    6400 cells, and `cube_check_chunks()` passed. The behaviour is source-read in this round;
    the consequence was measured then.
  - **Not in #99.** #99 row 3 is a file that *exists* and fails `nc_open`. This case is the
    same disk-full family with no file at all.

- **[fragile]** `tests/testthat/test-dft_stac_cube.R`, "a chunk gdalcubes could not merge
  aborts the write (#87)". **The assertion that pins round 2's fix cannot fail under the defect
  it names.**
  - The mock `file.copy()`s the clean file **before** `warning()`. With an abort from inside the
    handler (the round-2 defect), `out` already exists, so `expect_true(file.exists(out) &&
    file.size(out) > 0)` holds either way.
  - **Measured by mutation in the copy.** Replacing the handler body with
    `cli::cli_abort(class = "drift_incomplete_cube", ...)`, i.e. an abort inside the handler,
    leaves the block green: 3 expectations, 0 failed.
  - **Fix, also measured.** Swap the mock's two lines, so it raises `warning(...)` first and runs
    `file.copy(...)` after it. The mutant then fails 1 of 3, and the real `cube_write_ncdf()`
    passes 3 of 3.

- **[fragile, doc]** `inst/notes/gdalcubes-pc-gotchas.md:437`. **The notes still carry the
  claim round 1 refuted:** "A chunk that no image intersects is never visited and keeps the
  netCDF integer fill."
  - Fill means that no chunk was merged for that id. That covers an OK all-NaN chunk, which a
    worker visits and then skips writing (`cube.cpp:1808-1811`); fully cloud-masked chunks are
    included. It also covers an unmerged chunk.
  - The roxygen was corrected and this copy was not. A reader of the notes would take fill to
    mean "provably empty", which is the premise the round-1 fix exists to reject.
  - Related staleness, outside the diff: #99's "Mitigation already in drift" says the retries
    are on "the cube/composite session and the tiled fetch". This diff now sets them on every
    fetch.

- **[fragile, low]** gdalcubes `cube.cpp:1883-1901` and `:1919`. **A worker chunk file that
  opens but is partial is merged as OK, and the data-read case merges uninitialized memory.**
  - The status comes from the global attribute, which is read first. If the `x/y/t/b`
    dimensions or the `value` variable are missing, `read_ncdf()` returns empty with that status
    (OK), so those cells are NA.
  - If they are present and `nc_get_var_double` fails, its return is unchecked. The buffer was
    `std::malloc`ed and never filled, so **arbitrary values** are merged under status OK. These
    are not NA, so a pixel check passes them.
  - Not measured; it needs a crafted HDF5 file whose header is intact over unreadable data.
    #99 row 3 names only the `nc_open` failure. It should name the hand-off as a class.

- **[fragile, low]** gdalcubes `image_collection_cube.cpp:565-566`. **A scene with no mask
  asset is used unmasked, with status OK and only a stderr `[WARNING]`.**
  - **Measured** (`scratchpad/r3_nomask.R`). Scene 1 is B04 = 500 with SCL = 9. Scene 2 is
    B04 = 700 with no SCL file in the collection. The median is 700 in all 1600 of 1600 cells,
    status 0 x9, at p = 1 and 4.
  - **Reachability.** It needs a STAC item returned without its mask asset, which is rare on
    Planetary Computer S2 L2A. The same code shape also skips an image whose *band* asset is
    absent while its mask is present (`:411-412`, `image_datasets.empty()`).

- **[fragile, low]** gdalcubes `image_collection.cpp:~1429`
  (`while (sqlite3_step(stmt) == SQLITE_ROW)`). **A step error truncates a chunk's image list
  silently.** `SQLITE_BUSY`, `IOERR` or `FULL` mid-query ends the loop as if the rows had run out.
  The chunk is then computed from fewer images, or none, and the status is OK; an empty result
  returns early at `image_collection_cube.cpp:329` as OK. Low reachability: workers only read
  the collection DB, so a concurrent writer cannot cause it. It takes an I/O error, or a full
  temp dir during the ORDER BY sorter's spill. Source-read only.

### Round-2 fixes: checked, no defect

- **Muffling inside a C-raised warning is safe.** `Rf_warning` reaches R through
  `.signalSimpleWarning`, which establishes `muffleWarning` with `withRestarts()` in an R frame
  *below* the gdalcubes C++ frames. `invokeRestart()` therefore unwinds only R frames created
  after the C++ call and skips no destructor. Muffling hides nothing, because the abort that
  follows carries the count and the first message.
- **Bonus, measured.** Under `options(warn = 2)` the handler muffles before `.dfltWarn` can
  convert the warning to an error, so the wrapper also prevents the longjmp that `warn = 2`
  would otherwise cause. The run returned `drift_incomplete_cube` as intended.
- **`{unmerged[[1]]}` in cli is safe.** cli substitutes values without re-parsing them. A probe
  message containing `Chunk{x} ... {.val y} }{` rendered literally, and the class stayed
  `drift_incomplete_cube`. gdalcubes' real text is `"Chunk<N> could not be added to output."`
  (`multiprocess.cpp:139/143`), which contains no braces.
- **Unconditional retry block in `dft_stac_fetch()`.** Its names
  (`GDAL_HTTP_MAX_RETRY/RETRY_DELAY`) are disjoint from the tiled block's `gdal_cfg`. So the
  FIFO order of the two `on.exit(add = TRUE)` handlers cannot re-set a value the other
  restored. It is registered before every abort point that follows, including
  `tile_size_check()` and the config resolution.
- **Doc claims checked against source.**
  - **True:** the enum values (`cube.h:266-271`), "a chunk whose merge threw keeps fill"
    (`read_ncdf` throws before `f()` writes the status), "always multiprocess", "worker carries
    status in its chunk file" (`cube.cpp:1832-1833`, `:1866-1871`), and a missing attribute
    reads as UNKNOWN 128.
  - **Incomplete:** the notes bullet at `:450` ("Not every failure is recorded") omits findings
    1, 2, 5 and 6 above.

## Enumeration

(a) = detected: a non-OK `chunk_status` caught by `cube_check_chunks()`, the merge warning
caught by `cube_write_ncdf()`, or an R error that propagates out of `write_ncdf()` before
anything is cached (noted "err"). (b) = listed in drift#99. (c) = neither.

| # | where (gdalcubes @ed68331) | trigger | status / signal | class |
|---|---|---|---|---|
| 1 | R `cube.R:886-890` | not a cube; file exists without overwrite | R `stop()` | a (err), unreachable: drift passes `overwrite = TRUE` |
| 2 | R `cube.R:910-915` | cube-cache hit copies an earlier file | silent `file.copy` | n/a: the cache is populated only by `plot.R:109-118/345-354`; drift never plots its internal cubes, and a per-call collection path makes the hash unique |
| 3 | `gdalcubes.cpp:1339-1374` | `std::string` thrown anywhere in `write_netcdf_file` | `Rcpp::stop` | a (err) |
| 4 | `cube.cpp:621-634` | output is a dir / irregular space | throw → `Rcpp::stop` | a (err) |
| 5 | `cube.cpp:752-754` | output `nc_create` fails | unchecked; write returns | a (err): `ncdf4::nc_open` in `cube_check_chunks()` errors on the missing file; drift's outputs are fresh tempfiles, so no stale file can stand in |
| 6 | `cube.cpp:969,1094,1103` | output `nc_put_var1_int`/`nc_put_vara`/`nc_close` fail (output disk full) | unchecked | c, low: undetected only if the file still opens; otherwise `ncdf4`/terra raise (not a finding by itself; grouped with the hand-off class) |
| 7 | `multiprocess.cpp:22-25` | work dir already exists | throw → `Rcpp::stop` | a (err) |
| 8 | `multiprocess.cpp:90-102,178-189,227-228` | a worker exits > 0 (R error in a worker, incl. any C++ throw in `read_chunk`) | `Rcpp::stop` | a (err) |
| 9 | `multiprocess.cpp:149-160,223-225` | user interrupt | `Rcpp::stop` | a (err) |
| 10 | `multiprocess.cpp:137-145` | exception merging a chunk (`read_ncdf`/`f()` throws) | `Rcpp::warning("Chunk<N> could not be added")`, fill | a (`cube_write_ncdf`) |
| 11 | `multiprocess.cpp:84-102` + TinyProcessLib | worker killed by a signal | `write_ncdf()` hangs | b |
| 12 | `multiprocess.cpp:241` | `read_chunk` throws inside a worker (`exec` has no handler) | worker R error, exit 1 → row 8 | a (err) |
| 13 | `multiprocess.cpp:241-244`, `cube.cpp:1815-1820`, `filesystem.cpp:193` | worker `nc_create` or `CPLMoveFile` fails, so no chunk file | fill, no warning | **c** (finding 2) |
| 14 | `cube.cpp:1801-1804` | worker temp file already exists | `GCBS_ERROR`, no file | n/a: unique job dir |
| 15 | `cube.cpp:1808-1811` | OK and all-NaN chunk (no image, fully masked, all values NaN) | not written, fill | a (legitimate; fill read as OK by design) |
| 16 | `cube.cpp:1859-1862` | worker chunk file fails `nc_open` | OK, empty | b |
| 17 | `cube.cpp:1866-1871` | chunk file without the status attribute | UNKNOWN (128) | a |
| 18 | `cube.cpp:1883-1901` | chunk file lacks dims or `value` var | status from attribute (OK), empty | **c** (finding 5) |
| 19 | `cube.cpp:1919` | `nc_get_var_double` fails | unchecked; uninitialized buffer merged, OK | **c** (finding 5) |
| 20 | `image_collection_cube.cpp:317-321` | chunk id out of range | empty OK | n/a |
| 21 | `image_collection.cpp:1426` | query prepare fails | throw → row 8/12 | a (err) |
| 22 | `image_collection.cpp:~1429` | `sqlite3_step` error mid-query | truncated image list, OK | **c** (finding 7) |
| 23 | `image_collection_cube.cpp:329-331` | no image intersects | empty OK | a (legitimate) |
| 24 | `image_collection_cube.cpp:411-412` | image has no requested band (band asset absent) | skipped, OK | **c**, low (finding 6) |
| 25 | `image_collection_cube.cpp:414-416` | image outside the chunk's time range | skipped | n/a (legitimate) |
| 26 | `image_collection_cube.cpp:425-438` | band `GDALOpen` fails (strict: ERROR; drift is non-strict: INCOMPLETE) | 2 | a |
| 27 | `image_collection_cube.cpp:440-443` | dataset opens with 0 raster bands | skipped, OK | c, negligible: not reachable for COG assets; counted, not reported |
| 28 | `image_collection_cube.cpp:462-463,597-598` | `GDALTranslateOptionsNew` fails | throw → row 12 | a (err) |
| 29 | `warp.cpp:92-93,280,287,455-456,496-498` | MEM driver missing / transform cannot be inverted | throw → row 12 | a (err) |
| 30 | `warp.cpp:253-256,646-654` (band) | warp `Initialize` or `ChunkAndWarpImage` fails after a good open (range-request 429/5xx after retries, token expiry mid-extent, corrupt tile) | NaN, OK | b (row 1 of #99; `Initialize` failure falls through the same unchecked path) |
| 31 | `image_collection_cube.cpp:509-522` | band warp returns nullptr | 2 | a (unreachable: `warp()` returns its MEM dataset) |
| 32 | `image_collection_cube.cpp:538-551` | band RasterIO fails | 2 | a (unreachable: reads a MEM dataset) |
| 33 | `image_collection_cube.cpp:565-566` | image has no mask band | `GCBS_WARN`, used **unmasked**, OK | **c** (finding 6, measured) |
| 34 | `image_collection_cube.cpp:570-579` | mask `GDALOpen` fails | scene dropped, OK (strict: empty OK) | b |
| 35 | `image_collection_cube.cpp:620-633` | mask warp returns nullptr | 2 | a (unreachable, as row 31) |
| 36 | `warp.cpp:646-654` via mask path | mask opens, then the read fails | mask NaN → **nothing masked**, OK | **c** (finding 1, measured) |
| 37 | `image_collection_cube.cpp:636-649` | mask RasterIO fails | 2 | a (unreachable, MEM) |
| 38 | `image_collection_cube.cpp:663-665` | every image failed | ERROR (1) | a |
| 39 | `image_collection_cube.cpp:674-678` | all-NaN result keeps its status | INCOMPLETE/ERROR written by the worker | a |
| 40 | `apply_pixel.cpp:40-45` | input status / empty input | propagated | a |
| 41 | `apply_pixel.cpp:75-84` | `te_compile` fails in `read_chunk` | empty, input status | n/a: same expressions are validated in the constructor (`apply_pixel.h:106-111`, throws) |
| 42 | `select_bands.cpp:36,44-46` | passthrough / propagation | propagated | a |
| 43 | `reduce_time.cpp:533-535` | `size_t == 1` passthrough | input chunk as-is | a |
| 44 | `reduce_time.cpp:573` | unknown reducer | throw → row 12 | a (err) |
| 45 | `reduce_time.cpp:584-591,604-608` | input ERROR/INCOMPLETE, incl. the all-empty return | escalated | a |
| 46 | `cube.cpp:1108-1112` | `chunk_error_count > 0` | `GCBS_WARN` on C++ stdio only | not a signal; `chunk_status` carries it (a) |

Not used by drift, so not enumerated: `aggregate_time`, `filter_pixel`, `filter_geom`, `ncdf_cube`,
`write_chunks_netcdf` (`chunked = TRUE`), packing.

**Counts** (rows that are failure paths; n/a and legitimate-empty rows excluded):

- **(a) 25.** 13 via `chunk_status` or the merge warning: rows 10, 17, 26, 31, 32, 35, 37,
  38, 39, 40, 42, 43, 45 (46 shares 26's status). 12 via an R error propagating out of
  `write_ncdf()`: rows 1, 3, 4, 5, 7, 8, 9, 12, 21, 28, 29, 44. Rows 15, 23 and 25 are
  legitimate empties; rows 2, 14, 20 and 41 are unreachable from drift.
- **(b) 4:** rows 11, 16, 30, 34.
- **(c) 9:** rows 6, 13, 18, 19, 22, 24, 27, 33, 36.
  - **Reported as findings:** 13, 33 and 36 (two measured), and 18/19 and 22 (low, from
    source).
  - **Low:** 24 (finding 6, with 33).
  - **Not reported on its own:** 6 (output-side unchecked writes, low) and 27 (negligible).

The (c) rows share one mechanism with #99's rows 1 and 3: dropped I/O return codes under a
status that is set only at `GDALOpen`. Of the nine (c) rows, the one that changes values
rather than removing them is 36, which leaves clouds unmasked. That is the one to lead with in
#99 and the upstream draft.

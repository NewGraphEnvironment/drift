# Code review: round 2, #87 Phase 1 + 2 (staged diff)

I worked in a copy (`scratchpad/drift_r2`) and checked against the gdalcubes source at the
installed SHA ed68331. I fetched `multiprocess.cpp`, `image_collection_cube.cpp`,
`reduce_time.cpp`, `apply_pixel.cpp`, `select_bands.cpp`, `aggregate_time.cpp`,
`filter_pixel.cpp` and `filesystem.cpp` for this review.
All #87 test blocks pass in the copy. Counts are expectations (nb) per block:

| file | blocks | nb per block | failures |
|---|---|---|---|
| cube | 8 | 2, 4, 2, 3, 1, 2, 1, 2 | 0 |
| composite | 4 | 2, 2, 6, 2 | 0 |
| fetch | 4 | 2, 2, 4, 3 | 0 |

Every probe ran under `timeout`, and none was left running (checked with `ps`).

## Findings

- **[fragile]** R/dft_stac_cube.R:745-756 (`cube_write_ncdf()`, the `cli_abort()` inside the
  `withCallingHandlers(warning = )` handler). **The abort longjmps through gdalcubes' C++ frames.**
  - **How it happens.** gdalcubes raises the warning with `Rcpp::warning("Chunk" + id + " could
    not be added to output.")` (multiprocess.cpp:139/143). That call takes the
    `std::string` overload, which is a bare `::Rf_warning("%s", ...)` (Rcpp 1.1.2
    `include/Rcpp/exceptions.h:115-117`). An R calling handler runs synchronously inside
    `Rf_warning`, and a handler that aborts makes a non-local exit across C++. Rcpp's own header
    says so, at :190-194: "Rf_warning() may longjmp out of this frame ... A longjmp skips C++
    destructors".
  - **What it skips.** The call sits inside a `catch` block in
    `chunk_processor_multiprocess::apply()`. The jump therefore skips:
    - the worker-process teardown. The `TinyProcessLib::Process` objects are never destroyed,
      killed or waited on, so the workers keep reading images (network, CPU, memory) after R
      has reported the abort. They then linger as zombies.
    - `filesystem::remove(work_dir)`
    - `nc_close(ncout)` on the output file in `cube::write_ncdf()`
    - `__cxa_end_catch` for the caught exception
  - **Why it matters.** The abort message tells the user to re-run. Re-running starts a fresh
    set of workers alongside the orphans.
  - **Reachability.** At this SHA it is low. `chunk_data::read_ncdf()` never throws, so the
    warning fires only when an exception escapes `f()`, such as a `bad_alloc`. I could not
    trigger it without patching gdalcubes, so the consequence is read from source, not
    measured.
  - **Fix.** Record a flag in the handler and abort after `gdalcubes::write_ncdf()` returns:

    ```r
    unmerged <- character(0)
    withCallingHandlers(gdalcubes::write_ncdf(cube, out, overwrite = TRUE),
      warning = function(w) {
        if (grepl("could not be added to output", conditionMessage(w), fixed = TRUE))
          unmerged <<- c(unmerged, conditionMessage(w))
      })
    if (length(unmerged)) cli::cli_abort(class = "drift_incomplete_cube", ...)
    ```

    This keeps the same guarantee that nothing is cached, and gdalcubes gets to finish its own
    cleanup. The existing mocked test is unaffected, since its warning is raised at R level
    either way.

- **[fragile]** R/dft_stac_cube.R:738-743 and :760-781, and inst/notes "#87" section.
  **The reachable merge failure is recorded as OK and raises no warning, so it passes both
  guards.**
  - **The documentation's claim.** The roxygen says "a chunk the main process could not merge
    back from its worker raises an R warning" and "a chunk whose merge failed also keeps fill".
    Both statements are wrong for the most likely merge failure: a worker chunk file that the
    main process cannot open.
  - **Why upstream records it as OK.** `chunk_data::read_ncdf()` (cube.cpp:1862-1867) does a
    bare `return` when `nc_open()` fails. It never calls `set_status()`, and the
    `chunk_data` default is `OK` (cube.h:276). So `f()` writes `chunk_status = 0` with no data,
    and nothing throws, so the "could not be added" warning never fires.
  - **How a worker produces such a file.** The worker writes the chunk with unchecked
    `nc_create`/`nc_put_vara` return codes (cube.cpp:1815-1857), then renames it into place
    regardless. A tempdir that fills mid-run (floodplain-scale reads are GB-scale) can
    therefore leave a truncated `N.nc` for the main process to read.
  - **Measured** (`scratchpad/worker_garbage.R` + `r2_garbage.R`). Worker 1 drops an
    unreadable `N.nc` for each chunk it owns (70 of 279) and exits 0. The result:
    - `cube_write_ncdf()` **PASSED**
    - **0 R warnings**
    - `chunk_status` was 195 fill / **84 OK**
    - notNA 4864 of a clean 6400, so 1536 cells silently NA
    - the only signal was `[ERROR] Failed to open netCDF file ... nc_open() returned -51`
      on C++ stderr
  - **Recommendation.** Nothing drift can read separates this case from a complete cube. Fold it
    into the follow-up issue alongside read-after-open and mask-open failures; the upstream
    fix is `set_status(ERROR)` on read_ncdf's failure returns. Also correct both roxygen blocks
    and the inst/notes bullet, so the warning arm is not credited with covering merge failures.
    In practice it covers almost nothing at this SHA.

- **[fragile, low]** R/dft_stac_fetch.R:117-137. **The new HTTP retries reach only the tiled
  fetch.**
  - The `gdal_cfg` block sits inside `if (!is.null(tile_size))`. The default untiled
    `dft_stac_fetch()` therefore gets no `GDAL_HTTP_MAX_RETRY` / `GDAL_HTTP_RETRY_DELAY`.
  - The rationale written into the diff applies there too ("a transient 429 or 5xx now aborts
    a whole read"). Before this diff, an untiled fetch that hit one transient 503 at open
    silently cached a holed year. With it, the fetch aborts with no retry.
  - That is the correct direction, but the stated intent ("retries in both blocks") does not
    cover the default path. Setting the two retry variables unconditionally (restored on exit)
    would close it. The other tuning variables can stay tile-only.

## Verified clean (checked, no action)

- **Abort inside `cache_write_atomic()`.** For the untiled fetch, `cube_write_ncdf()` runs
  inside `write_fn(tmp)`, so the `on.exit(unlink(c(tmp, tmp_side)))` removes the temp. A file
  netCDF still holds open after the longjmp case is unlinked too (POSIX).
- **Cube and composite.** The abort fires in `stac_cube_assemble()` before any
  `cache_write_atomic()`. The tests confirm an empty cache dir for untiled and tiled reads, and
  that year 1 stays cached when year 2 fails.
- **ncdf4 handles.** `chunk_status_failed()` closes through `on.exit(nc_close)` on every path,
  including an `ncvar_get` error. Opening with ncdf4 while terra's `r` still references the
  file works; the cache-gate test exercises exactly that and passes.
- **Status propagation through `pixel_fn`.** apply_pixel, select_bands and filter_pixel copy
  the input status. reduce_time and aggregate_time escalate INCOMPLETE/ERROR, including on the
  all-empty return. So the check placed after `pixel_fn` sees the source status for the
  index, true-colour and count paths. In image_collection_cube, the healthy reads (GDALOpen,
  warp and RasterIO all succeed) never set a non-OK status.
- **Cache-gate arm false refusals.**
  - It is gated on the `.nc` extension, so cube and composite (`.tif`) and the tiled fetch
    (`.tif`) never reach it.
  - A terra-written `.nc` has no `chunk_status` and passes (tested).
  - Chunks with no image keep fill, and fill counts as OK at parallel 1 and 4 (R gdalcubes
    always runs the multiprocess executor).
  - Any non-OK status in a gdalcubes `.nc` is a genuine open failure, so refusing it is
    intended.
  - On a fresh untiled write it re-checks what `cube_write_ncdf()` already checked. That is
    redundant but harmless.
- **Building pre/post before `terra::cover()`.** The rasters are file-backed, and the argument
  order is unchanged, so results are unchanged. The only difference is that the post side is
  now built even when the pre side would abort. The order is pre then post, so a pre abort
  still short-circuits.
- **Tiled fetch `on.exit`.** It is registered inside the `function(yr)` closure, so it fires
  once per year when that call exits, with `add = TRUE`. `unlink()` of tiles not yet written
  is a no-op. A partially written tile is removed.
- **GDAL environment variables.**
  - Neither gdalcubes' `.onLoad` nor terra presets `GDAL_HTTP_MAX_RETRY` or
    `GDAL_HTTP_RETRY_DELAY` as config options, which would outrank the environment. So
    `CPLGetConfigOption` falls back to `getenv` and sees them.
  - TinyProcessLib launches workers with no env override, so they inherit the parent's
    environment, the same mechanism the existing tuning variables already rely on.
  - Both blocks restore every name in `gdal_cfg` (re-set or unset) on exit.
  - No test asserts the set of environment variables (grep of `tests/` for
    `GDAL_HTTP|VSI_CACHE|CPL_VSIL|READDIR|getenv`).
- **The real warning text.** gdalcubes writes "Chunk3 could not be added to output." with no
  space after "Chunk". The `fixed = TRUE` substring still matches it; the test mock's "Chunk 3"
  differs only there.

# Review round 1 — drift#47 staged diff

Scope: `git diff --cached` on branch `47-adopt-the-fixed-filter-geom-now-that-the`
(DESCRIPTION, R/dft_stac_cube.R, man/dft_stac_cube.Rd, tests/testthat/test-dft_stac_cube.R,
data-raw/logs/benchmark_filter_geom/*.csv).

Every claim below was probed, not reasoned. Probe output is quoted inline.

## Findings

- **[bug]** `R/dft_stac_cube.R:400-408` — the new all-NA post-condition **aborts on the
  package's own documented `months` workflow**, after the full network read, with nothing
  cached and no override.

  Layer 1 is the first calendar month of the `datetime` window (`month_times()` seeds from
  `substr(dr[1], 1, 7)`, and `cube_view()` fixes the time axis regardless of data). The
  `@param months` block on this very function states the rule that makes this fire:
  *"Months with no retained scenes become `NA` in the monthly cube, so the per-pixel series
  stays regular at `frequency = 12`."* So `months = 6:9` over a January-starting window makes
  layer 1 all-`NA` **by design** — 8 of every 12 layers are — and the guard reads that as the
  gdalcubes failure mode.

  That is not a hypothetical call shape. It is the call shape:

  | caller | line |
  |---|---|
  | `vignettes/trajectory-break-detection.Rmd` | 47-48 — `datetime = "2017-01-01/2023-12-31", months = 6:9` |
  | `data-raw/vignette_data_break.R` | 26 — same window, same months |
  | project `CLAUDE.md`, "Core Pipeline" | the advertised continuous-path example, same window, same months |

  Cost is asymmetric: the abort lands *after* the 10-30 min COG stream, `writeRaster()` is
  never reached, so the fetch is unrecoverable and re-running reproduces it. There is no
  argument to bypass it.

  Fix: assert the cube has data *somewhere*, not on layer 1 — e.g.
  `if (all(terra::global(stk, "notNA")$notNA == 0))`. That is the property the guard is
  actually for (an empty cube), it is unaffected by legitimately-empty leading months, and it
  is chunked, which also closes the next finding.

- **[bug]** `tests/testthat/test-dft_stac_cube.R:323-325` — the assertion commented
  *"kills a clip that did nothing"* **cannot fail**, so the diff reintroduces the defect class
  it exists to fix.

  ```r
  expect_gt(sum(is.na(vals[!inpoly, , drop = FALSE])), 0)
  ```

  Cloud masking alone puts `NA` outside the polygon, so a cube on which `stac_cube_clip()`
  never ran satisfies it. Measured on a synthetic 3-layer raster with scattered cloud-shaped
  `NA`s and **no clip applied at all**:

  ```
  clip-did-nothing: sum(is.na(outside)) = 178  -> expect_gt(..., 0) PASSES? TRUE
  ```

  The discriminating assertion is the strict one, and it is exactly valid here — I verified
  that `terra::mask(touches = TRUE)` (what `stac_cube_clip()` calls) and
  `terra::rasterize(touches = TRUE)` (what the test builds `inpoly` from) agree cell-for-cell
  on the same grid:

  ```
  clipped: all outside NA? TRUE
  mask==rasterize agreement: TRUE
  ```

  So use `expect_true(all(is.na(vals[!inpoly, , drop = FALSE])))`. Note this is the same
  shape as the bug being fixed two assertions above — an assertion that is correct and an
  input that cannot reach it.

- **[fragile]** `R/dft_stac_cube.R:400` — `terra::values(terra::subset(stk, 1))` materialises
  an entire layer in memory on the path where the AOI is largest. The diff's own roxygen
  (`R/dft_stac_cube.R:419-422`) cites drift's OOM history (#27, #34) as the reason to cap
  workers at 4, then adds an unconditional full-layer read immediately after the mask. At
  10 m over a large bbox that is tens of millions of doubles. `terra::global(stk, "notNA")`
  is chunked and answers the same question — and is the fix for the first finding anyway.

- **[fragile]** `R/dft_stac_cube.R:429-442` — `cube_parallel_check()`'s gate lets three
  wrong-but-plausible inputs through silently. Probed:

  ```
  cube_parallel_check(TRUE) -> 1
  cube_parallel_check(8.7)  -> 8
  cube_parallel_check(1e6)  -> 1000000
  ```

  `TRUE` is the worst of the three, because it is **gdalcubes' own idiom**:
  `gdalcubes_options(parallel = TRUE)` means *use all cores*. A caller reaching for the
  spelling they already know from the library drift is configuring gets `1L` — single-threaded,
  the exact opposite of intent, with no message, and indistinguishable from having asked for
  it. `8.7` truncates silently. `1e6` is passed straight into `gdalcubes_options()` with no
  upper sanity bound. Reject `is.logical()` and non-integer-valued numerics explicitly rather
  than funnelling everything through `as.integer()`.

## Checked and clean (the items the brief called out by name)

- **`on.exit` for the `parallel` restore cannot leak, and does not displace the GDAL-config
  handler.** `gdalcubes_options()$parallel` exists and returns `1` on a fresh session
  (verified against gdalcubes 0.7.4), so `old_parallel` is never `NULL`. The handler is
  registered at :164 immediately after the mutation at :163, with nothing between that can
  abort — `cube_parallel_check()` (:161) and the options read (:162) both precede any state
  change. Both handlers carry `add = TRUE`, so the second does not replace the first. The
  cache-hit early return at :251-256 unwinds both.

- **The `parallel` formal does not shadow the `parallel` package.** `::` is special-formed, so
  a local binding cannot capture it. Probed live rather than assumed — with
  `local_mocked_bindings(detectCores = ..., .package = "parallel")` installed inside
  `cube_parallel_check()`'s call path:

  ```
  real detectCores: 10
  MOCKED detectCores gives: NA
  cube_parallel_check(NULL) -> 1
  ```

  The mock takes and the `NA` floor works. testthat 3.3.2 is installed and the DESCRIPTION
  pin is correctly bumped to `>= 3.2.0` for `.package =`.

- **Keeping `parallel` out of the cache key is right — I tried to break it and could not.**
  Chunk size *is* derived from `parallel`; `gdalcubes:::.default_chunksize` deparses to
  `target_nchunks_space = ceiling(2 * nparallel)`, edge `ceiling(cx/64) * 64` clamped to
  `[64, 1024]`, so on the packaged AOI `parallel = 1/4/8` gives 256/128/128 px chunks. It is
  still value-neutral: chunks only partition the grid already fixed by `cube_view()`, the time
  chunk is always 1 so the `median` temporal aggregation is per-slice regardless of spatial
  chunking, and each chunk is warped independently by GDAL with its own source margin.
  `equivalence.csv` is consistent — `E_par4` / `E_par8` against `A_bbox_mask`: `same_grid TRUE`,
  identical 49,244 non-NA cells, `cor 1`, `max_abs_diff 0`.

- **Roxygen adjacency is intact.** `cube_parallel_check()` is inserted after
  `dft_stac_cube()`'s closing brace and carries its own `@noRd` block, so `@export` still
  binds to `dft_stac_cube`; `man/` shows only `dft_stac_cube.Rd` updated, no stray `.Rd`.

- **New `parallel` Imports entry** is used (`parallel::detectCores`) and needs no NAMESPACE
  change. `data-raw/` is already in `.Rbuildignore`, so the two new benchmark CSVs do not ship.

## Out of diff, but it will block the merge

`tests/testthat/test-dft_stac_cube.R:62` — the frozen legacy cache-key golden **fails on this
machine right now**:

```
FAILURE: 'test-dft_stac_cube.R:62:3'
Expected `cube_key()` to equal "638a2be11fdf".
`actual`:   "45685ccbda33"
[ FAIL 1 | WARN 0 | SKIP 3 | PASS 57 ]
```

Not caused by this diff — I diffed `stac_cube_cache_key()` and the `cube_key()` helper against
`HEAD` and both are byte-identical, and neither appears in the staged changes. It is
environment drift (sf 1.1.2 / GEOS 3.13.0 / GDAL 3.8.5 / PROJ 9.5.1 / rlang 1.3.0, R 4.5.2)
moving either the WKB or `rlang::hash()`.

Raising it because of what the test's own comment says it means — *"If this ever changes,
existing cube caches are invalid"* — so either every cached `cube_<key>.tif` on every machine
is already orphaned, or the golden needs re-pinning with a note recording what moved it.
Worth settling before merge either way, since the branch cannot go green as it stands.

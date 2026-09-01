# Review round 3 — drift#47 (`parallel` arm + all-NA post-condition + doc corrections)

Scope: `git diff main...HEAD -- R/ tests/ DESCRIPTION NEWS.md inst/`, read in full,
plus `data-raw/logs/benchmark_filter_geom/{summary,equivalence}.csv` and
`data-raw/benchmark_filter_geom{,_chunkskip}.R` as the evidence they are cited as.
Every claim below was probed on this machine (gdalcubes 0.7.4, terra 1.9.34).
Rounds 1–2 findings and the four stated accepted tradeoffs are not re-reported.

## Findings

- **[bug]** `R/dft_stac_cube.R:258-263` (cache-hit early return) vs `R/dft_stac_cube.R:402-424`
  (the new post-condition) and `NEWS.md:41` — **the all-NA guard has no cover on the read
  path, so an all-NA cube already on disk is still served silently, forever.** The guard sits
  after `stac_cube_clip()` on the *write* path only; the cache branch returns
  `terra::rast(cache_file)` before it. `stac_cube_cache_key()` is untouched by this branch, so
  upgrading to 0.9.0 does not invalidate anything a ≤0.8.0 run wrote — and the cubes at risk
  are exactly the ones the pre-0.9.0 code could produce, since NEWS itself records that
  drift's only end-to-end cube test was passing on all-NA cubes. `force = FALSE` never
  regenerates, so the empty cube is permanent for that key.

  Reproduced offline, no network (`/tmp/p7.R`): compute the key with
  `drift:::stac_cube_cache_key()` for the packaged AOI at
  `datetime = "2021-06-01/2021-08-31"`, plant an all-`NA` 3-layer
  `cube_5055e726766c.tif` under `<cache>/sentinel-2-l2a/`, call `dft_stac_cube()` →

  ```
  planted: cube_5055e726766c.tif
    cube: cached
  RETURNED. nlyr: 3  notNA total: 0
  all NA? TRUE
  ```

  No abort, no warning. NEWS.md:41 says *"so an empty cube can no longer be cached and served
  for every later call"* — the second half is not true. The check is one `terra::global()`
  pass over a local raster, i.e. the same cost the write path already pays, so hoisting it to
  cover both paths is cheap; alternatively NEWS has to say the guard is write-side only and
  tell readers to delete stale caches.

- **[fragile]** `NEWS.md:39`, `R/dft_stac_cube.R:100-103` (`@param parallel`),
  `R/dft_stac_cube.R:161-165` (comment), `inst/notes/gdalcubes-pc-gotchas.md:116-119` —
  **the "it cost twice over" chunking claim is contradicted by this branch's own committed
  evidence, and it ships in the public changelog and man page as measured fact.** All four
  places assert that `parallel = 1` was expensive *twice*: once for single-threading, and
  again because `default_chunksize()` derives from `parallel` so `parallel = 1` "also produced
  the coarsest possible chunking".

  The benchmark has a pair of arms that isolates chunk size with everything else held: in
  `data-raw/benchmark_filter_geom.R:38,40` `B_fg_default` and `C_fg_128` differ **only** in
  `chunking` (both `filter_geom = TRUE`, `pad_px = 2`, no `parallel`, so `parallel = 1`).
  From `summary.csv`:

  | arm | chunking | elapsed_s | requests |
  |---|---|---|---|
  | `B_fg_default` | default (256 px at `parallel = 1`) | 236.9 | 462 |
  | `C_fg_128` | forced 128 px | 343.7 | 693 |

  At `parallel = 1`, finer chunking measured **45% slower and 50% more requests** — the
  opposite direction — and it did so *while skipping more ground* (the committed
  `benchmark_filter_geom_chunkskip.R` gives 0% skip at 256 px, 11.1% at 128 px). The notes'
  own next bullet explains why: a sub-512 px chunk sits inside one COG block and refetches it.

  No arm isolates the chunk-size contribution to `E_par4`: it changes worker count and chunk
  size together (verified `2 * parallel` → `cx = ceiling(sqrt(nx*ny/(2*p))/64)*64` in
  `asNamespace("gdalcubes")$.pkgenv$default_chunksize`; 256 px at `p = 1` → 128 px at `p = 4`
  on this 326×314 cube). So the measured 2.05x is attributable to concurrency, and the only
  data on the chunk-size axis says it is a cost, not a saving. The claim should be dropped or
  restated as an untested mechanism.

- **[fragile]** `inst/notes/gdalcubes-pc-gotchas.md:21` and `:118` — **the citation that lets a
  reader re-derive the `2 * parallel` / `[64, 1024]` chunking claim is a dead pointer.** There
  is no `default_chunksize` in the gdalcubes namespace:

  ```
  $ Rscript -e 'print(gdalcubes:::default_chunksize)'
  Error: object 'default_chunksize' not found
  ```

  The function is `gdalcubes:::.default_chunk_size` (also stored as
  `get(".pkgenv", asNamespace("gdalcubes"))$default_chunksize`). The arithmetic in the notes is
  correct — I read the real function and it does target `ceiling(2 * nparallel)` spatial chunks
  and clamp to `[64, 1024]`, and 326×314 at `p = 1` does give a 2×2 grid of 256 px chunks, as
  the notes say. Only the name is wrong. This matters because CLAUDE.md instructs people to
  read this file before touching the continuous pipeline, and it is the one bullet whose
  premise cannot be checked without the pointer.

- **[fragile]** `inst/notes/gdalcubes-pc-gotchas.md:26-32` — **26.7% is a 64-px number
  attributed to both chunk sizes.** The sentence reads "64 px and 128 px chunking both
  measured 693 requests / ~345 s … to skip 26.7% of the ground (predicted by
  `data-raw/benchmark_filter_geom_chunkskip.R`)". Running that committed script:

  ```
  chunk  128 px: 9 chunks, 8 intersect -> skip 11.1%
  chunk   64 px: 30 chunks, 22 intersect -> skip 26.7%
  ```

  26.7% holds only for 64 px. `NEWS.md:40` and `R/dft_stac_cube.R:325` both scope it correctly
  to 64 px; this is the one place the round-2 correction landed on a sentence whose subject is
  two arms. (The rest of that round-2 correction reconciles: 26.7% at pad 2 px / 64 px, and
  AOI/bbox 0.1019 → the notes' 0.102.)

- **[fragile]** `R/dft_stac_cube.R:168-171` — **the `parallel = NULL` default silently
  overrides a session-level `gdalcubes_options(parallel = )` the caller set deliberately.** A
  user who ran `gdalcubes::gdalcubes_options(parallel = 8)` and then calls `dft_stac_cube()`
  with the default gets `min(4, cores - 1)` for the duration of the call and their value back
  afterwards — half the throughput they asked for, with no message. The comment at :166-167 is
  accurate about the *session* being restored, but neither `@param parallel` ("auto-detect as
  `min(4, cores - 1)`") nor NEWS says the auto path outranks an explicit global. Honouring a
  non-default session value, or documenting that it does not, would close it.

## Checked and clean (probed, not assumed)

- **`terra::global(stk, "notNA")` and `$notNA`.** Column name is `"notNA"` on terra 1.9.34 for
  1-layer, multi-layer, in-memory and file-backed stacks, so the `sum(NULL) == 0` trap that
  would abort every call is not reachable. It returns `0` rather than erroring on an all-NA
  raster (unlike `terra::freq()`, per the repo's own convention), and **counts `NaN` as `NA`**
  — verified on an all-`NaN` stack in memory and after a GeoTIFF round-trip — so a kNDVI cube
  that came back all-`NaN` still fires the guard.
- **The new `is.finite` / `.Machine$integer.max` clause rejects nothing legitimate.** `4`,
  `4L`, `8.0`, `1`, and `2147483647` all pass; `"four"` short-circuits on `!is.numeric()`
  before `is.finite()` can be reached, so no input reaches `is.finite()` with a type it cannot
  take. All five members of the test's `bad` list abort with a message matching `"whole
  number"`, so the grep still holds.
- **`NaN` does not take the new clause** — `is.na(NaN)` is `TRUE`, so it aborts one branch
  earlier, at `:453`. The message is byte-identical, so the test is unaffected; the comment at
  `:470-474` and the test's framing at `:449-456` imply otherwise, but nothing is broken. Worth
  knowing that `NaN` and `-Inf` are both vacuous members of that loop (they abort under the
  restored defect too); `Inf`, `1e10` and `2147483648` do discriminate — I restored the round-1
  clause and confirmed those three then fail on `"missing value where TRUE/FALSE needed"`
  instead, so the test as a whole does catch the defect it was written for.
- **`skip_if(before == 1L, ...)` is correctly scoped.** `before` is the unmocked
  `cube_parallel_check(NULL)`; it is `1L` exactly when `cores <= 2` or `detectCores()` is
  already `NA`, which is precisely where mocked and unmocked coincide. Where it does not skip,
  the mock must move the answer or the test fails. Confirmed the mock takes:
  `local_mocked_bindings(detectCores = ..., .package = "parallel")` makes
  `parallel::detectCores()` return `NA` inside the block (10 → NA → 10 after), and
  `cube_parallel_check(NULL)` goes 4 → 1. On this 10-core machine the test runs rather than
  skips.
- **`parallel` as a formal argument does not shadow the package** — `::` takes its LHS as a
  literal symbol, so `parallel::detectCores()` at `:447` and `:484` resolves correctly even
  with a local `parallel` bound to an integer; exercised by the passing explicit-value tests,
  which reach `:484`.
- **`gdalcubes_options()$parallel` is never `NULL`** on a loaded gdalcubes (`.pkgenv$parallel`
  is set at load; observed `1`, numeric), so the `on.exit` restore cannot hit
  `gdalcubes_options(parallel = NULL)`, which does error
  (`Not compatible with requested type: [type=NULL; target=integer]`). Both `on.exit` calls use
  `add = TRUE`, so neither replaces the other.
- **The network test's `all(is.na(vals[!inpoly, ]))` oracle holds.** Independently re-ran the
  claimed equivalence — `terra::mask(touches = TRUE)` vs `terra::rasterize(touches = TRUE)` —
  over 60 random irregular polygons: **0 disagreements**. `!is.na(...)[, 1]` parses as
  intended (`[` binds tighter than `!`).
- **Number reconciliation, everything except the two items flagged above.** 236.8 / 115.8 /
  96.0 s and 462 / 1134 / 1386 requests, 49,244 → 41,608 non-NA (−15.5%), 1263.6 s / 3213
  requests (5.34x), cor 0.99603 / max abs diff 0.254362 / recall 0.9584, 348.2 s (+47%) and
  693 requests (1.5x) at 64 px, 0.1019 AOI/bbox — all match `summary.csv` / `equivalence.csv` /
  the chunkskip script.
- **`man/dft_stac_cube.Rd` is current** — `devtools::document()` produces no diff, so the
  round-2 `touches = TRUE` correction and `@param parallel` are in the shipped man page.
- **`lintr::lint("R/dft_stac_cube.R")` → no lints.** `devtools::test()` on the branch:
  `FAIL 1 | SKIP 3 | PASS 68` for this file, the one failure being the frozen golden cache-key
  hash at `:62` declared out of scope.
- **Cached-artifact content vs key**: nothing besides `parallel` (accepted) alters written
  content; `stac_cube_cache_key()` is untouched, `.Rbuildignore` still excludes `planning`,
  `data-raw` and `CLAUDE.md`, and the new `.gitignore` rules exclude only `*.log`/`*.tif`/`*.rds`
  under `data-raw/logs/`, leaving both committed CSVs tracked.

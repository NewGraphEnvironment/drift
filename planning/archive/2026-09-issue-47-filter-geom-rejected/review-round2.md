# Review round 2 — drift#47

Scope: the staged diff on `47-adopt-the-fixed-filter-geom-now-that-the`, which was
committed as `f5a6182` partway through this review. Every finding below was
re-verified against `HEAD = f5a6182` after the commit landed, so the line numbers
are the committed ones.

Every claim was probed. Probe output is quoted inline. Round 1's three findings are
not re-reported; two defects **introduced by / left behind by those fixes** are.

## Findings

- **[bug]** `NEWS.md:5` — the changelog documents the **pre-round-1-fix** behaviour, and
  what it documents is the defect round 1 removed.

  ```
  `dft_stac_cube()` also now aborts, before writing anything to the cache, when the
  assembled cube has no data on its first layer
                                     ^^^^^^^^^^^
  ```

  The shipped guard is `R/dft_stac_cube.R:409`:

  ```r
  if (sum(terra::global(stk, "notNA")$notNA) == 0) {
  ```

  — the whole stack, deliberately, because layer 1 is all-`NA` by design under the
  documented `months = 6:9` workflow. The code comment at :401-405 says exactly that.

  This is not a cosmetic drift. `NEWS.md` is rendered as the pkgdown changelog, so the
  published release note tells every reader that the abort fires on the package's own
  advertised continuous-path example (`CLAUDE.md` "Core Pipeline", the
  `trajectory-break-detection` vignette, `data-raw/vignette_data_break.R`). A reader
  hitting a legitimately-empty leading month will read the changelog and conclude the
  abort is expected; a reader planning a `months`-filtered call will avoid the function.
  The sentence needs to say **"no data on any layer"**.

  Same class as `code-check.md`'s *"a fix to code that writes data is not done until the
  written data is reconciled"* — the fix landed in the writer and not in what the reader
  reads.

- **[bug]** `R/dft_stac_cube.R:463-479` — `cube_parallel_check()`'s numeric gate has **no
  upper bound**, so `Inf` and any value `>= 2^31` pass every check and are then silently
  coerced to `NA_integer_`. The validator either dies with a message that does not name
  the argument, or returns `NA`.

  `Inf` clears the gate because `trunc(Inf) == Inf` and `Inf < 1` is `FALSE`; `1e10`
  clears it because it is a whole number `>= 1`. Then `n <- as.integer(parallel)` at :469
  warns and yields `NA_integer_`. Measured (`parallel::detectCores()` = 10):

  ```
  Inf         -> [warn: NAs introduced by coercion to integer range] ERROR: missing value where TRUE/FALSE needed
  1e10        -> [warn: NAs introduced by coercion to integer range] ERROR: missing value where TRUE/FALSE needed
  2147483648  -> [warn: NAs introduced by coercion to integer range] ERROR: missing value where TRUE/FALSE needed
  -Inf        -> ERROR: `parallel` must be a single whole number >= 1  (correct)
  ```

  The `missing value where TRUE/FALSE needed` comes from the **round-1 fix itself** —
  line 473, `if (!is.na(cores) && n > 4L * cores)`, evaluates `NA > 40`. Before that
  branch existed, `1e10` merely returned `NA_integer_` quietly; the fix converted a silent
  wrong answer into an opaque base error, which is better but still not a validation
  message.

  The worse arm is the one the function's own roxygen (:433-436) cites as the reason the
  `NULL` path floors to 1 — a container where `detectCores()` is `NA`. There `!is.na(cores)`
  short-circuits, the warn branch never runs, and **a function whose entire job is validation
  returns `NA_integer_`**, which then reaches `gdalcubes_options()`:

  ```
  # detectCores() mocked to NA_integer_
  cube_parallel_check(NULL)  -> 1            (mock took)
  cube_parallel_check(1e10)  -> NA           <- validator returns NA
  gdalcubes_options(parallel = NA) -> ERROR: parallel >= 1 is not TRUE
  ```

  Neither message names `parallel`, on the exact machine class the auto path was hardened
  for. Fix is one clause at :463 — reject non-finite and out-of-`integer` input before the
  coercion, e.g. `!is.finite(parallel) || parallel > .Machine$integer.max`. The junk loop
  at `tests/testthat/test-dft_stac_cube.R:167` should gain `Inf` and `1e10`; as it stands it
  covers `0, -1, NA, "four", c(1,2), numeric(0), 8.7` and cannot reach this.

- **[fragile]** `tests/testthat/test-dft_stac_cube.R:155-161` — the `NA`-floor test has no
  premise assertion and is **vacuous on any machine reporting <= 2 cores**, which includes
  the container class it was written for.

  The auto path is `max(1L, min(4L, cores - 1L))`, which is `1L` at 1 and 2 cores — the same
  value the mock is asserted to produce:

  ```
  cores= 1 -> auto=1 ; NA-mock=1 ; test can distinguish: FALSE
  cores= 2 -> auto=1 ; NA-mock=1 ; test can distinguish: FALSE
  cores= 3 -> auto=2 ; NA-mock=1 ; test can distinguish: TRUE
  cores=10 -> auto=4 ; NA-mock=1 ; test can distinguish: TRUE
  ```

  So the `.package = "parallel"` mock could fail to take — or be deleted outright — and the
  test still passes there. It passes for the right reason on this machine (10 cores) and on
  4-core GitHub runners, which is exactly what makes it invisible. Capture the unmocked value
  first and assert the premise beside the property:

  ```r
  before <- drift:::cube_parallel_check(NULL)
  skip_if(before == 1L, "machine's auto value is already 1 — mock is indistinguishable")
  local_mocked_bindings(detectCores = function(...) NA_integer_, .package = "parallel")
  expect_identical(drift:::cube_parallel_check(NULL), 1L)
  ```

- **[fragile]** `R/dft_stac_cube.R:42` and `:107` — the `touches = TRUE` correction landed
  **only in the `@noRd` block** of the internal helper. The exported documentation — the
  pkgdown page a user actually reads — still says only:

  ```
  :42   clip the returned stack to the AOI polygon with `terra::mask()`
        (cells outside → `NA` on every layer)
  :107  the stack is clipped to the AOI polygon (cloud-masked, cells outside the polygon `NA`)
  ```

  Neither mentions that the boundary is inclusive by up to one cell. This diff's own NEWS
  entry argues the rule "matters to anyone reasoning about boundary hectares" and measures it
  at 15.5% of the analysed footprint — and `stac_cube_clip()`'s roxygen is `@noRd`, so that
  correction reaches nobody outside the source tree. Same shape as `karpathy.md`'s inventory
  rule: the fix is complete relative to the wrong boundary. One clause on `@param clip` and
  `@return` closes it.

- **[fragile]** `DESCRIPTION:3` — `Version: 0.8.0`, while `NEWS.md:2` opens a `# drift 0.9.0`
  section and the **shipped** roxygen says "Prior to v0.9.0 drift never called
  `gdalcubes_options()`" (`R/dft_stac_cube.R:94`, rendered into `man/dft_stac_cube.Rd:407`).
  The installed package reports 0.8.0 while its own help page and changelog describe 0.9.0 as
  already past. `r-package.md` puts the bump as the final commit of the branch, so this may be
  pending — noting it so it is not missed, since `NEWS.md` and `man/` both shipped in
  `f5a6182` and nothing else on the branch will prompt for it.

  Related, in the same NEWS bullet (`NEWS.md:3`): *"is roughly **2× faster out of the box**"*
  is false on a 1- or 2-core machine, where `min(4, cores - 1)` resolves to `1` and behaviour
  is byte- and time-identical to v0.8.0. The roxygen states the formula honestly; the
  changelog states the speedup as unconditional.

## Lower priority — `inst/notes/gdalcubes-pc-gotchas.md`

`CLAUDE.md` mandates reading this file before touching the continuous pipeline, so its
claims carry more weight than ordinary prose.

- `:9` — *"The segfault **below** is genuinely fixed"* now dangles. The bullet that described
  the segfault (`crashes gc_exec_worker, address 0x120`) is the text this diff replaced, so
  there is no "below" any more; the only remaining mention is `:31-33`, which says CRAN 0.7.4
  *still* segfaults. A reader arriving at :9 cannot find what was fixed.
- `:3-6` — the header still reads *"gdalcubes 0.7.3 … All verified by running code on
  gdalcubes 0.7.3"*. Every new measurement in this diff was taken on **0.7.4** (`:31-33` says
  so explicitly, and 0.7.4 is what is installed). The file's own provenance statement no
  longer covers half its content.
- `:22` and `NEWS.md:4` and `R/dft_stac_cube.R:318` — *"to skip 27% of the ground"* is not
  derivable from either committed CSV, and the benchmark scripts compute no such quantity
  (`grep -n "0.102\|ratio\|area" data-raw/benchmark_filter_geom.R` returns nothing). The
  neighbouring `0.102` area ratio **is** reproducible — I recomputed it at `0.1019289` — so
  this is the one number in the set with no evidence behind it. Either cite where it came from
  or drop it.

## Fixed in flight — not a live finding

The originally-staged blob carried *"Request counts go up (462 -> 1004 at 8 workers)"* in the
`parallel` bullet, contradicting `summary.csv` (`E_par8` requests = 1386, `req_vs_A` = 3.0). I
re-counted the ground truth from the raw log rather than trusting the CSV:

```
A_bbox_mask    Range-lines=462
E_par4         Range-lines=1134
E_par8         Range-lines=1386
```

`f5a6182` ships *"462 -> 1134 at 4 workers, 1386 at 8"*, which is correct. Recording it only
so the check is on the record.

## Checked against the brief's checklist and clean

- **`terra::global()` semantics.** `$notNA` is the right column name on terra 1.9.34 for
  1-layer, multi-layer, and duplicate-layer-name stacks (`names(global(r,"notNA"))` ->
  `"notNA"`), so the `NULL`-column trap — where `sum(NULL) == 0` is `TRUE` and the guard would
  abort **every** call — does not fire. Column type is `double`, not `integer`, so a stack
  large enough to exceed `2^31` non-`NA` cells cannot overflow to `NA`. An all-`NA` stack
  returns 0 per layer and the condition fires as intended; the abort message renders correctly
  (the `\\` continuations, `{terra::nlyr(stk)}`, `{cfg$collection}` and `{datetime}` all
  resolve — verified by executing it).

- **The guard cannot fire on the documented `months` workflow.** Confirmed on the real
  benchmark cube: `months = 6:9` gives `notNA` of `0 0 0 0 0 12311 12311 12311 12311 0 0 0` —
  eight empty layers, January first, whole-stack sum 49,244, guard silent. This is the
  round-1 defect, and the fix reaches it.

- **The network test's oracle matches the production clip cell-for-cell on the real grid.**
  The round-1 fix tightened `sum(is.na(outside)) > 0` to `all(is.na(outside))`, which is only
  safe if the test's `rasterize(touches = TRUE)` oracle is exactly the set
  `mask(touches = TRUE)` keeps — including the fact that the test transforms the AOI via
  `terra::crs(cube)` (a WKT) while the function transforms via the EPSG integer. Measured on
  `A_bbox_mask.tif`, the real 314x326 cube grid:

  ```
  geometry identical? FALSE    max coord diff: 0     <- different sfc objects, same coordinates
  test oracle inside cells : 12311
  production kept cells    : 12311
  disagreements            : 0
  cells prod keeps but test calls OUTSIDE (would fail all-NA assertion): 0
  real A_bbox_mask cube: all outside NA? TRUE   non-NA outside: 0
  ```

  The strict assertion holds on real data with zero margin consumed. `expect_lt(mean(is.na(inside)), 0.9)`
  is also safe: the packaged AOI shows **zero** cloud `NA` inside the polygon in its data
  months.

- **`terra::mask()` default really is `touches = TRUE`** on the installed terra 1.9.34
  (`.local(x, mask, inverse = FALSE, updatevalue = NA, touches = TRUE, ...)`), and empirically
  `mask(r, v)` == `mask(r, v, touches = TRUE)` == 150 cells vs 122 at cell centre on the new
  fixture. The new test's `expect_gt(touch, centre)` premise is a real premise — the fixture
  separates the two rules — and is not satisfied by the happy path's structure.

- **Base-name shadowing.** The new formal is literally `parallel`, and `parallel::detectCores()`
  still resolves in both call sites (the auto branch at :440 and the warn branch at :470) —
  `::` does not evaluate its first argument. Proved by execution rather than by reasoning:
  `cube_parallel_check(NULL)` returns 4 on a 10-core machine, and returns 1 under a mocked
  `detectCores()`.

- **`on.exit` ordering and leaks.** `cube_parallel_check()` (:161) and the options read (:162)
  both precede the mutation at :163, so an abort in validation cannot leave gdalcubes altered.
  Both handlers carry `add = TRUE`, so the GDAL-config restore does not displace the `parallel`
  restore. The new `cli_abort` at :410 unwinds both. `gdalcubes_options()$parallel` returns
  `1` (a `num`, never `NULL`) on 0.7.4, so the restore is well-formed — worth knowing that
  `gdalcubes_options(parallel = NULL)` **errors** (`Not compatible with requested type:
  [type=NULL; target=integer]`), so a `NULL` here would throw from inside `on.exit` and mask
  the original condition. Not reachable on 0.7.4; noted because nothing guards it.

- **Zero-length / `NA` traps in `cube_parallel_check()`.** Swept every shape:
  `NULL, 1, 4L, NA, NaN, TRUE, FALSE, "4", c(1,2), numeric(0), list(4), factor(4), 4+0i, 0, -1,
  8.7, -Inf` all take the intended branch with the intended message. Length is tested before
  `is.na()`, so a length-2 input cannot reach `||` with a length-2 test; `is.na()` precedes the
  logical branch, so bare `NA` is reported as missing rather than as a flag. The only holes are
  `Inf` and `>= 2^31`, reported above.

- **Roxygen adjacency and generated docs.** `cube_parallel_check()` sits after
  `dft_stac_cube()`'s closing brace with its own `@noRd` block, so `@export` still binds to
  `dft_stac_cube`. `devtools::document()` on the committed tree produces **no** diff — no
  `NAMESPACE` churn, no stray `.Rd`, nothing deleted.

- **Numeric claims against the committed evidence.** Apart from the `27%` noted above, every
  figure in `NEWS.md`, `inst/notes/` and the roxygen reconciles with `summary.csv` /
  `equivalence.csv`: 236.8 / 115.8 / 96.0 s; 2.05x and 2.47x; 462 / 462 / 693 / 3213 / 1134 /
  1386 requests; 47% slower at 64 px (348.2/236.8 = 1.470); 5.3x for `tile_size` (1263.6/236.8 =
  5.336); 15.5% footprint loss (1 - 41608/49244 = 0.1551); 49,244 non-NA; `cor 0.996`,
  `max_abs_diff 0.254`, `recall 95.8%` for `D_tile_640`; and the `0.102` AOI/bbox area ratio,
  which I recomputed independently at `0.1019289`.

- **Nothing changes cached-artifact content without changing its key.** `parallel` is the only
  new parameter and it is out of the key by decision; `stac_cube_cache_key()` is untouched by
  this diff. The new post-condition sits before `terra::writeRaster()`, so its abort cannot
  leave a partial `cube_<key>.tif`.

- **Offline suite.** `testthat::test_file("tests/testthat/test-dft_stac_cube.R")` — all new
  tests pass; the only failure is the frozen cache-key golden at `:62`, which the brief
  excludes as out of scope.

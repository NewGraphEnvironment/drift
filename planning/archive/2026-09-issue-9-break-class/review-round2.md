# Code-check round 2 — `dft_rast_break_class()` (staged diff, 2026-09-05)

Reviewed the round-1 fixes first, then the rest of the staged diff, against
`code-check.md`, `code-check-shell.md`, `code-check-r.md`,
`code-check-spatial.md`. Every claim below was measured with terra 1.9.34 from
scratchpad scripts (`r2_app_src*.R`, `r2_probe_[abc].R`, `r2_restore2.R`);
nothing in the repo was edited. The staged test file is green:
113 passed / 0 failed / 0 skipped / 0 warnings under
`NOT_CRAN=true testthat::test_file()`.

## Round-1 fixes: restore-the-bug

Each fix was reverted in a copy of the function patched into **both**
`load_all()` bindings (`asNamespace("drift")` and `package:drift`), with a
probe confirming the patched line was visible from each, then the test file
re-run. (A first attempt patching the namespace only read 113 green on every
restore — the two-bindings trap in `code-check.md`; discarded.)

| restored defect | result | verdict |
|---|---|---|
| `INT2S` (handler on) | 1 error, 1 fail — ESA test aborts with `class codes overflow the transition encoding` | fix pinned |
| `INT2S`, handler off | 5 fails — ESA test sees silent `NA`s, summary count 3 ≠ 4 | test reaches the silent-NA failure mode |
| `same.crs()` guard off | 1 fail (`input guards`) | fix pinned |
| `nlyr == 1` guard off | 1 fail (`input guards`) | fix pinned |
| `if (!is.matrix(v)) stop()` → `v <- matrix(v, ncol = n)` | **113 passed** | fix NOT pinned — see finding 2 |

## Findings

### 1. [fragile] `R/dft_rast_break_class.R:230-240` — the overflow abort leaves a half-written `out_file` that nothing unlinks

Direct answer to the round-2 question: `withCallingHandlers(warning = )` does
see terra's overflow warning — it is an R `warning()` raised from
`writeValues()` per chunk — and `stop()` inside the handler unwinds cleanly
(R error, no hang, no corrupted return). But it fires **before** `writeStop()`
(a `trace()` on `writeStop` printed nothing), so the abort leaves a partial
GeoTIFF on disk. Measured with the ESA fixture on an `INT2S` copy: one
`dft_break_class_*.tif` of 843 bytes left in `tempdir()`, readable by
`terra::rast()`.

`out_file` is deliberately kept out of `files` so the *success* return can
point at it (line 181-183 comment), which means the `on.exit(unlink(files))`
also skips it on **every** error path after line 230 — the overflow abort,
and any failure in `app()`, the `status` write or `crosstab()`. Benign today
(tempdir, cleared at session end; with `INT4S` the overflow branch needs a
class code above 2,147,483 so it is effectively unreachable), but on the BULK
grid an abort partway through leaves a file in the hundreds of MB that the
function's own cleanup contract says it owns. One-line shape that keeps the
success path unchanged:

```r
files <- c(files, out_file)              # after out_file <- tempfile(...)
...
files <- setdiff(files, out_file)        # immediately before each return
```

### 2. [fragile] `R/dft_rast_break_class.R:208-209` — the round-1 #1 fix (vectorised `app()` path) has no guard; a restore stays green

Reverting the `is.matrix()` refusal to the original `matrix(v, ncol = n)`
passes all 113 assertions, because the per-cell and per-chunk paths produce
identical values and nothing in the suite observes call count or time. So
the 57x regression round 1 measured can be re-introduced by anyone
"simplifying" that `stop()` — it reads as a pointless guard — with the suite
green. The BULK benchmark (`data-raw/benchmark_break_class_bulk.R`, fetch in
progress) is the instrument that can see it; record its `app()` timing in
NEWS.md/PR body as the CLAUDE.md scale-test rule asks, so a future run that
comes back ~55 min instead of ~1 min has a number to be compared against.
No test recommended beyond that — the property is performance, not values.

## Probed and clean (round-2 questions, in order)

- **`withCallingHandlers` sees the warning**: yes, R-level, message
  `[writeValues] detected values outside of the limits of datatype INT2S`;
  `grepl("outside of the limits of datatype", ...)` matches. Non-matching
  warnings are not muffled and still propagate.
- **`stop()` in the handler**: unwinds cleanly out of `app()`; the `out`
  SpatRaster in `app()`'s frame is dropped and GDAL closes the dataset (the
  partial file is readable afterwards). Leftover-file half is finding 1.
- **`gdal = "COMPRESS=LZW"` in `wopt`**: applied — `describe()` on the
  output reports `COMPRESSION=LZW`, five `Int32` bands, NoData
  `-2147483648`. Bundled 3-year tile: 132 KB on disk.
- **`terra::same.crs()`**: semantic, not string. `EPSG:32609` == its WKT ==
  `+proj=utm +zone=9 +datum=WGS84 +units=m` (all `TRUE`); 32609 vs 32610
  `FALSE`. `compareGeom()` on the EPSG/WKT pair is also `TRUE`, so an
  equivalent-CRS raster is neither refused nor needlessly resampled.
- **`nlyr` guard order**: runs at line 152, after `is.list`/`inherits` and
  before `names()`, `dft_check_crs()`, `deepcopy()`, `levels<-`, `rast()` —
  nothing multi-layer-sensitive precedes it. `vapply(..., numeric(1))`
  accepts `nlyr()`'s integer return.
- **`datatype()` on `out[[2:5]]` from the LZW file**: `INT4S INT4S INT4S
  INT4S`; `$raster` also `INT4S`.
- **`crosstab(long = TRUE, useNA = TRUE)` on the INT4S file**: plain
  `numeric` columns in layer order, count last; interior-NA rows arrive as
  `NaN`, which `as.integer()` turns into `NA` so the `c("stable","break",
  "flicker")[NA]` indexing gives `NA` as intended.
- **ESA test reaches the failure mode**: `95 -> 100` = 95100 and `100 -> 100`
  = 100100, both > 32767; measured red on the INT2S restore both with and
  without the handler (table above).
- **`status` app on a single layer is vectorised** — not a re-instance of
  round-1 #1: terra's `app()` has `if (nl == 1) { r <- fun(v); usefun <-
  TRUE }`, so `pmin(v, 2L)` is called once per chunk with the n x 1 matrix.
- All-NA series: `crosstab()` does not error the way `freq()` does; the
  empty-summary early return runs (0 rows, 4 evidence layers). Endpoints-NA
  with valid interior: 0 summary rows, evidence `NA` — consistent with the
  accepted NA design. Plain (non-factor) code rasters work; inputs are left
  unmutated in both the factor and non-factor case.
- Whole function on the bundled tile (326 x 314 x 3): 0.10 s; on the 12-pixel
  fixture 0.15 s — the vectorised path is what ships.
- `.Rbuildignore` still covers `^planning$`; NAMESPACE gains exactly one
  export; `man/dft_rast_consensus.Rd` matches its roxygen; `.gitignore` line
  is inert for tracked files.
- The staged roxygen example uses only 2017/2020/2023, so the staged commit
  does not depend on the untracked `inst/extdata/example_2018/2019/2021/2022.tif`
  or the unstaged `vignettes/land-cover-change.Rmd` / `CLAUDE.md` edits.
- Shell/R sweep (partial `$` on parsed documents, `nzchar`, `vapply
  USE.NAMES`, `on.exit` at function level, roxygen block/function adjacency,
  `glue`, `system2` quoting): nothing applicable in this diff.

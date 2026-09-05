# Code-check round 3 — `dft_rast_break_class()` (staged diff, 2026-09-05)

Reviewed the two round-2 fixes first, then enumerated every terra call in
`R/dft_rast_break_class.R` against the mechanism that produced rounds 1-2,
against `code-check.md`, `code-check-shell.md`, `code-check-r.md`,
`code-check-spatial.md`. Every claim below was measured with terra 1.9.34 from
scratchpad scripts (`r3_src.R`, `r3_app_full.R`, `r3_stale.R`,
`r3_restore_strand2.R`, `r3_shipped_strand.R`, `r3_tol.R`, `r3_nc5.R`,
`r3_example.R`, `r3_base.R`); nothing in the repo was edited. Shipped test
file: **123 passed / 0 failed / 0 errors / 0 warnings** under
`NOT_CRAN=true testthat::test_file()`.

## The mechanism

Rounds 1 and 2 were four instances of one shape: **a terra internal contract
written into the code from reading or recollection rather than from a
measurement** — `app()`'s dispatch order (assumed vector-probe-then-matrix; it
is `apply()`-per-row-first), `writeValues()` overflow (assumed error; it is a
warning), `resample()` (assumed to reproject; it does not), and the
warning-to-abort's timing relative to `writeStop()`. Each was invisible to
the suite because the fixtures share the property the contract depends on
(small, 12- or 40-column, codes 1-4, one CRS).

The place that mechanism still reaches in the staged diff is the **shape
inference** inside `app()`, which the code relies on without naming it:
`app()` decides how many output layers `fun` produces — and whether to
transpose every chunk — from the dimensions of a *13-cell test chunk*, and
that chunk is only 13 cells wide when the raster has at least 13 columns.
Finding 1 below is the instance. The enumeration table is the deliverable
for the rest.

## Round-2 fixes, reviewed first

**Cleanup-list `setdiff()` before each return.** Correct. Walking every path
after `out_file <- tmpf()` (line 181):

| path | `out_file` on `files` at exit? | result |
|---|---|---|
| overflow abort inside `app()` (line 187) | yes | unlinked — measured 0 stranded on a real INT4S overflow (`3e6 * 1000 + 3e6 > 2^31`, plain code rasters) |
| `names<-`, `status` app, `crosstab()` error | yes | unlinked — measured 0 stranded with `crosstab` mocked to `stop("boom")` |
| `set.cats()` error in either branch (lines 209, 243) | yes — both `set.cats()` calls precede their `setdiff()` | unlinked |
| empty-summary return (line 217) | removed at 216 | kept |
| success return (line 247) | removed at 246 | kept |

Nothing after line 246 can error (`out[[2:5]]` is guaranteed 5 layers by the
`names<-` at 192), so there is no window where the file is off the list and an
error still fires. No path deletes the output the caller holds: `unlink()` runs
against `files` after `setdiff()`, the strings are identical, and the returned
rasters read `out_file` only (the resample and `status` intermediates are not
referenced by anything returned; `inMemory()` FALSE on both, test pinned).

**Does the stranded-file test reach the failure mode?** No — see finding 2.

## Findings

### 1. [bug] `R/dft_rast_break_class.R:183` — a raster with exactly 5 columns is silently scrambled by `terra::app()`

`app()` runs `fun` once on a test chunk of `ntest` cells taken from the
middle row, where `ntest = 1 + min(teststart + 12, ncol(x)) - teststart` and
`teststart = max(1, 0.5 * ncol(x) - 6)` — so `ntest == ncol(x)` for any raster
narrower than 13 columns. It then decides the output shape with
(`selectMethod("app", "SpatRaster")`, lines 66-75):

```r
if (NCOL(r) > 1) {
    if (ncol(r) == ntest) {  nlyr(out) <- nrow(r); trans <- TRUE; ... }   # checked FIRST
    else if (nrow(r) == ntest) { nlyr(out) <- ncol(r); ... }
```

`break_class_scan()` always returns 5 columns. When `ncol(x) == 5`,
`ncol(r) == ntest` is TRUE on the 5x5 test result, `trans` is set, and
**every real chunk is transposed before `writeValues()`** — cell values are
written across layers. No warning, no error, `nlyr(out)` is still 5, so
`names(out) <-` succeeds.

Measured (`r3_nc5.R`, `r3_base.R`): a 4x5 grid where every pixel is a clean
Trees -> Rangeland switch in 2020 —

```
                            5 columns                          6 columns
from_class to_class status break_year n_cells  |  from_class to_class status break_year n_cells
<NA>       Water    break           1       4  |  Trees      Rangeland break      2020      24
<NA>       Rangeland flicker        3       4  |
<NA>       Bare     flicker         4       4  |
Trees      Rangeland flicker     2003       4  |
Trees      <NA>     flicker     2020       4  |
transition == dft_rast_transition(): FALSE     |  TRUE
warnings: 0                                    |  0
```

4, 6 and 13 columns all match the closure exactly; only 5 fails. The
documented invariant *"identical to `dft_rast_transition(...)$raster`"* is
false for that width, and `dft_transition_vectors()` on `$raster` would
polygonise the garbage with plausible-looking labels (`Trees -> <NA>`).

It is a fixture-cannot-reach-the-failure-mode case: the fixtures are 1x12,
1x4, 3x?, 40x40 and 326x314. Low likelihood on a floodplain (thousands of
columns), but it is silent corruption on a legal input, and the same
heuristic fires on any future `app()` whose `fun` returns as many columns as
the raster is wide (<13). Two fixes, either is one or two lines:

- refuse: `if (terra::ncol(ref) == 5L) stop("5-column rasters are ambiguous to terra::app() ...")`,
  or
- pad: `terra::extend()` the stack by one column of `NA` before `app()` and
  `crop()` back to `ext(ref)` afterwards (streamed with `filename =`), which
  keeps every width legal.

Either way, add a 5-column case to the suite and assert `$raster` against
`dft_rast_transition()` — that assertion is what turns this red.

### 2. [fragile] `tests/testthat/test-dft_rast_break_class.R:253-263` — the stranded-file test cannot reach the failure mode it exists for

The test forces an abort with a CRS mismatch, which fires inside the `codes`
lapply (line 162) — **before `out_file <- tmpf()` at line 181**. Measured: that
path creates 0 files, so "no new `dft_break_class_*` files" holds regardless
of where the `setdiff()` sits.

Restore-the-bug (`r3_restore_strand2.R`): `files <- setdiff(files, out_file)`
moved back to immediately after `out_file <- tmpf()`, patched into both
`load_all()` bindings (offset from `tmpf()` measured as 1 in each), then
`testthat::test_file()` — **123 passed / 0 failed**, the stranded-file test 2/2
green. The same restored code strands 1 file when the abort is placed after
`app()`. So the round-2 fix is correct and unguarded: the test passes for
nothing.

Two shapes that do reach it, both measured on the shipped code returning 0
stranded:

```r
# (a) the real overflow path — no mocking; also pins the INT4S handler
big <- lapply(2017:2019, function(y) {
  r <- terra::rast(matrix(c(3e6, 1, 2, 3e6), 1)); terra::ext(r) <- c(0, 40, 0, 10)
  terra::crs(r) <- "EPSG:32609"; r })          # plain code rasters are accepted
names(big) <- 2017:2019
ct <- tibble::tibble(code = c(1, 2, 3e6), class_name = c("a", "b", "c"), color = "#000000")
expect_error(dft_rast_break_class(big, class_table = ct), "overflow the transition encoding")

# (b) any post-app() abort
testthat::with_mocked_bindings(
  expect_error(dft_rast_break_class(x_cases, class_table = ct), "boom"),
  crosstab = function(...) stop("boom"), .package = "terra")   # intercepts terra::crosstab from inside drift (measured)
```

then the same before/after `list.files()` assertion. (a) is the better one:
it exercises the exact branch the round-2 comment names ("the overflow
handler") and the handler's `grepl()` at the same time.

## Enumeration: every terra call in `R/dft_rast_break_class.R`

Rounds column: R1/R2 = measured in that round; R3 = measured here; *test* =
pinned by the shipped suite.

| line | call | assumption the code makes | holds on 1.9.34? | how verified |
|---|---|---|---|---|
| 125 | `terra::nlyr(r)` in `vapply(..., numeric(1))` | returns a length-1 integer that `vapply` promotes to double | yes | R2; `vapply` allows logical<integer<double promotion |
| 146 | `dft_check_crs()` → `terra::is.lonlat(perhaps = TRUE, warn = FALSE)` | rejects geographic CRS before `res()` is used for area | yes (pre-existing helper) | *test* (`projected CRS`) |
| 162 | `terra::same.crs(ref, r)` | semantic comparison, so EPSG vs WKT vs proj4 of one CRS is not refused | yes | R2 |
| 167 | `terra::deepcopy(r)` | returns an independent C++ object so `levels<-` does not touch the caller's raster | yes | R1, R3 (`caller still factor: TRUE`) |
| 168 | `levels(r) <- NULL` (primitive `levels<-`, S4 dispatch with terra imported not attached) | strips cats; values are the raw codes; dispatches without `library(terra)` | yes | R1; the coltab survives (`has.colors` TRUE, R3) — harmless, `app()` reads values |
| 169 | `terra::compareGeom(ref, r, stopOnError = FALSE)` | returns FALSE (no error, no warning) on extent/rowcol mismatch; TRUE for equivalent CRS spellings; leaves no stale error state on `ref` (the *caller's* object, whose `@pntr` the method reads) | yes | R2 (CRS); R3: `has_error()`/`has_warning()` FALSE on the caller's raster after the disagg path, and no message surfaces from `values`, arith, `freq`, `writeRaster`, `crop`, `rast(list)` or `dft_rast_transition` on it afterwards |
| 169/174 | `compareGeom` tolerance == `rast(list)` tolerance | a grid that `compareGeom` calls equal can be stacked by `rast()` without error | yes | R3: `spatOptions()$tolerance` 0.1; offsets of 1e-9 .. 1 m on 10 m cells → `compareGeom` TRUE and `rast(list)` ok; 5 m → FALSE and `[rast] extents do not match`. No gap. (An offset under 10 % of a cell is stacked by position without resampling — terra-wide, same in `dft_rast_transition()`.) |
| 170 | `terra::resample(r, ref, method = "near", filename = tmpf())` | aligns grid only (no reprojection — hence the `same.crs` guard); default FLT4S holds integer codes exactly; streams to the temp file | yes | R1 (no reprojection); *test* (disagg round-trips to identical evidence) |
| 174 | `terra::rast(codes)` | list order == layer order (== sorted years); mixed in-memory / file-backed elements stack | yes | *test* (shuffled names, disagg) |
| 183 | `terra::app(stack, fun = scan, filename, wopt)` — dispatch | tries `apply(v, 1, fun)` first, `fun(v)` only on error; chunks are always matrices | yes | R1 (measured 2 calls vs 360,013); source read R3 lines 44-56, 121-141: once `usefun` is chosen on the test chunk, real chunks are not re-`try`'d |
| 183 | `app()` — output shape | 5-column return → 5 layers, cells in rows | **only when `ncol(x) != 5`** | **R3 — finding 1** (source lines 66-75) |
| 183 | `app()` — factor input | no `factors are coerced` warning because levels were stripped | yes | R3 source line 30; suite 0 warnings |
| 184 | `wopt = list(datatype = "INT4S", gdal = "COMPRESS=LZW")` | `from * 1000 + to` fits INT4S for any code ≤ 2,147,483; `NA` → nodata -2147483648; LZW applied | yes | R2 (`describe()`: five Int32, LZW, nodata); *test* (`datatype()` INT4S) |
| 185-190 | `withCallingHandlers(warning = …)` over `app()` | terra's overflow is an R `warning()` from `writeValues()` matching `outside of the limits of datatype`; `stop()` in the handler unwinds; non-matching warnings propagate | yes | R2; R3 re-measured on a real INT4S overflow: abort message carries `INT4S`, 0 files stranded |
| 192 | `names(out) <-` | `app()` produced exactly 5 layers | yes when finding 1 does not apply | *test*; note `app()` already set `wopt$names` from `colnames(r)` (source line 79-80), so this is a redundant no-op except in the transposed case where `rownames(r)` is NULL |
| 196 | `terra::app(out[["n_flips"]], fun = pmin(v, 2L), wopt INT1U)` | single layer takes the `if (nl == 1) fun(v)` branch (no per-cell path); `NA` → nodata 255 → reads back `NA` | yes | R2; source line 39-41; *test* (`status` NA row) |
| 198 | `c(out[["transition"]], status, out[["break_year"]])` | primitive `c` dispatches to terra's SpatRaster method with terra imported not attached | yes | *test* (every summary assertion goes through it) |
| 198 | `terra::crosstab(…, long = TRUE, useNA = TRUE)` | streamed (no full-grid read into R); columns in layer order, count last; NA kept as NA/NaN; zero counts dropped | yes | R3 source: `x@pntr$crosstab(digits, !useNA, opt)` is C++; `res[res$Freq > 0, ]`; positional `names(ct) <-` is safe; R1/R2 for NA/NaN |
| 203 | `terra::res(ref)` | metre units (guarded by `dft_check_crs`) | yes | *test* (area 0.01 ha / 100 m²) |
| 209, 243 | `terra::set.cats(r_trans, layer = 1, value = data.frame(id, transition))` | reference-semantics on `r_trans` only, not on `out`/`breaks`; `id` column first; integer ids equal `dft_rast_transition()`'s | yes | *test* (`breaks` not factor; `cats()` equal); R3 example: both `id` int, identical |
| 207, 217, 247 | `out[["transition"]]`, `out[[2:5]]` | subsets stay file-backed on `out_file`; no dependence on the unlinked intermediates | yes | *test* (`inMemory` FALSE); R3 strand probes |
| 156 | `on.exit(unlink(files), add = TRUE)` (not terra, but the contract the whole cleanup rests on) | `files` is read at exit time from the function frame, after the `setdiff()` | yes | R3 (see round-2 review table) |

Two non-terra contracts checked while in the closure: `max.col(chg,
ties.method = "first")` — NA on NA rows, 1 on all-FALSE rows, both masked by
`one` (R1); `rowSums()` NA on any NA (R1). Both are also pinned directly by
the new `break_class_scan()` test.

## Probed and clean

- **Round-2 fix, both questions**: no path strands after `app()`, no path
  deletes the caller's file (table above).
- **Roxygen example** runs end to end on the bundled 2017/2020/2023 tile with
  0 warnings: 27 summary rows, 93 change patches, 12 tagged columns,
  `$raster` values and `cats()` identical to `dft_rast_transition()`.
- **`.gitignore`** line inert for tracked files; **NAMESPACE** gains exactly
  one export; `.Rbuildignore` still carries `^planning$` so the three
  `review-round*.md` files do not ship.
- **Roxygen adjacency**: `break_class_scan()` sits *after* the exported
  function with its own `@noRd` block; nothing intervenes between the
  exported block and `dft_rast_break_class`.
- **Shell/R sweep** (partial `$` on parsed documents, `nzchar`, `vapply
  USE.NAMES`, `on.exit` at function level, `glue`, `system2`, `st_sf(...)`
  trailing args, `identical()` on reader results): nothing applicable in this
  diff.
- **Accepted design decisions** not re-flagged: no threshold, interior-NA
  semantics, IO LULC 0/10 as classes, in-memory `dft_rast_consensus()`,
  regenerated `dft_transition_artifact.Rd`, Memory section deferring to
  NEWS.md, performance pinned by the BULK benchmark.

# Code-check round 1 — `dft_rast_break_class()` (staged diff, 2026-09-05)

Reviewed against `code-check.md`, `code-check-shell.md`, `code-check-r.md`,
`code-check-spatial.md`. Every claim below was measured with terra 1.9.34 from
scratchpad scripts (`probe3.R`–`probe8.R`); nothing in the repo was edited.
The shipped test file is green as stated: 106 passed / 0 failed / 0 skipped
under `NOT_CRAN=true testthat::test_file()`.

## Findings

### 1. [bug] `R/dft_rast_break_class.R:195-218` — `terra::app()` runs `scan()` once per CELL, not once per chunk

The comment (lines 195-197), the task plan and `findings.md` ("Plan-agent
measurement") all state that terra "probes `fun` with a bare numeric vector,
then a small matrix, before the real chunks, and a one-row chunk arrives as a
vector". The `app()` source says the opposite (`selectMethod("app", "SpatRaster")`):

```r
r <- try(apply(v, 1, fun, ...), silent = TRUE)      # per-ROW first
if (inherits(r, "try-error")) {
    rr <- try(fun(v, ...), silent = TRUE)            # whole matrix only as a FALLBACK
    ... usefun <- TRUE
}
```

Because `scan()` accepts a length-`n` vector gracefully (`matrix(v, ncol = n)`),
the per-row `apply()` *succeeds*, `usefun` stays `FALSE`, and every real chunk is
processed with `apply(v, 1, fun)` — one R call per cell. And `readValues(mat = TRUE)`
always returns a matrix (measured `1x7` for a single cell, `600x7` for one row),
so the "one-row chunk drops to a vector" premise is false as well.

Measured on a 600x600 x 7-layer synthetic stack:

| `scan` as written | `scan` refusing a bare vector |
|---|---|
| **360,013** calls, first three shapes `integer 7` | **2** calls, shapes `13x7` then `360000x7` |
| 6.96 s | 0.12 s |

57x. Values are identical between the two paths (`all.equal` ignoring layer
names on a 40k-cell grid with 10% NA). Scaled to the BULK grid this is ~55 min
of pure R-call overhead for a pass that should take ~1 min; NA cells (97.7% of
BULK) go through `apply()` too.

**Fix** is one line at the top of `scan()`:

```r
if (!is.matrix(v)) stop("matrix chunks only")   # forces app() onto the vectorised path
```

`matrix(v, ncol = n)` can stay as a no-op. Correct the comment, and the
findings.md entry, since both now record a contract that is backwards.

Related: the roxygen `@section Memory` says *"Measured on a 169M-cell floodplain
grid (the BULK watershed group at 10 m, seven years)"* but no measurement
exists — `data-raw/logs/benchmark_break_class/` holds only `fetch.log` and
`extend.log` (08:34-08:37), no `timings.csv`. The sentence ships a measurement
claim with no number behind it. Run the BULK benchmark *after* this fix
(CLAUDE.md scale-test rule) and put the numbers in the PR body; the roxygen
should either carry a number or drop "Measured".

### 2. [bug] `R/dft_rast_break_class.R:217-218` — `INT2S` silently NAs every transition with a class code >= 33; ESA WorldCover is broken

`from * 1000 + to` overflows `INT2S` (max 32767) once `from >= 33`. terra does
not error — it writes `NA` and emits one warning
(`[writeValues] detected values outside of the limits of datatype INT2S`) that
the function neither catches nor converts. `source = "esa-worldcover"` is
documented as accepted and its codes are 10–100.

Measured, an 8-pixel ESA series (2017 = 2018, 2019 differs on 4 pixels):

```
break_class $raster : 10010 20020 NaN   NaN    10100 NaN   NaN   NaN
rast_transition     : 10010 20020 40010 100020 10100 50050 60060 95010
summary n_cells sum : 3  (transition: 8)
n_flips             : 0 0 1 1 1 0 0 1        <- evidence layers still populated
```

So: the documented invariant *"identical to `dft_rast_transition(...)$raster`"*
fails on 5 of 8 pixels; `summary` drops them and `pct` is renormalised over the
survivors (each row reads 33.3%); `$breaks` and `$raster` disagree (a dated
break with an NA transition); `dft_transition_vectors()` on `$raster` would then
silently omit those patches. The suite cannot see this — the fixture table is
`code = 1:4` (fixture that cannot reach the failure mode).

**Fix**: pick the datatype from the code range rather than hardcoding —

```r
max_code <- max(class_table$code)
dt <- if (max_code * 1000L + max_code > 32767L) "INT4S" else "INT2S"
```

(INT4S doubles the output file, 3.4 GB at 169M x 5; the four evidence layers
never need it, so the alternative is two `app()` outputs). Whatever the choice,
also turn terra's overflow warning into an abort with `withCallingHandlers()` so
an overflow from a code outside `class_table` can never be silent. Add a code
>= 33 case to the tests to pin it.

### 3. [fragile] `R/dft_rast_break_class.R:184-193` — a raster in a different CRS is scanned by cell position, with only a warning

`compareGeom()` returns FALSE for a CRS mismatch, the raster goes to
`resample()`, and `resample()` does **not** reproject (measured: output keeps
its own CRS, `same.crs(rs, ref)` FALSE). `terra::rast(codes)` then warns
`[rast] CRS do not match` and stacks anyway. Measured with the fixture and 2020
set to EPSG:32610: the function returned normally with a full evidence set.

The roxygen says "Rasters on a different grid from the first are resampled to
it", which a reader takes as "alignment is handled". Same pattern as
`dft_rast_consensus()` (`R/dft_rast_consensus.R:58-59`), so not new — but this
function is the one whose doc promises alignment. `if (!terra::same.crs(ref, r))
stop(...)` (or `terra::project()`) is one line. Low likelihood via
`dft_stac_fetch()`, which projects everything to one UTM zone.

### 4. [fragile] `R/dft_rast_break_class.R:149-150` — no single-layer check on the elements of `x`

A two-layer element (e.g. `dft_rast_consensus(confidence = TRUE)` output) makes
the stack `n + 1` layers; `matrix(v, ncol = n)` recycles with a stream of
`data length [8] is not a sub-multiple ...` warnings and the call dies with
`[names<-] incorrect number of names`. Loud, so not a data bug, but the error
points nowhere near the cause. `terra::nlyr(r) == 1L` in the element guard.

## Probed and clean

- `terra::crosstab(long = TRUE, useNA = TRUE)`: columns are plain `numeric`
  in layer order with the count last; `NA` is a real `NA`, not `"NA"` or a
  factor level; zero-count combinations are not emitted. The positional
  `names(ct) <-` and `as.integer(ct$status) + 1L` are correct.
- `max.col(chg, ties.method = "first")` on a logical matrix: `NA` on any row
  containing `NA`, `1` on an all-FALSE row — both masked by `one`, as the
  comment says. `rowSums()` is `NA` on those rows.
- `levels(r) <- NULL` on a `deepcopy()` dispatches with terra loaded but not
  attached (`levels<-` is primitive; measured in a clean process, original
  left factor).
- Output file lifetime: `out_file` is never appended to `files`, so the
  `on.exit(unlink(files))` removes only the resample and `status`
  intermediates; `ct` is computed before exit; returned rasters stay readable.
- `terra::datatype()` on `out[[2:5]]` reports `INT2S` (test passes).
- IO LULC code 0 round-trips through crosstab and the level labels
  (`No Data -> Trees` etc.).
- NAMESPACE gains exactly one export; `man/dft_transition_artifact.Rd` matches
  the roxygen already on `main` (genuine stale-Rd regeneration, as stated).
- `.gitignore` addition is inert for tracked files.
- Shell/R traps swept (partial `$` on lists — not used on parsed documents;
  `nzchar`; `USE.NAMES`; `on.exit` at function level; `.Rbuildignore` covers
  `planning`): nothing applicable.

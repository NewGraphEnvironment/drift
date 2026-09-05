# Code-check round 5 — `dft_rast_break_class()` stack-first strip + `wopt$steps` (staged diff, 2026-09-05)

Narrow scope: the restructured stacking step (`rast(aligned)` then `levels<-`/`coltab<-`
on the stack), the `wopt$steps` bound on `app()`, and the new caller-unmutated test.
Every claim below was measured with terra 1.9.34 / testthat 3.3.2 from scratchpad
scripts (`r5_share.R`, `r5_coltab.R`, `r5_steps.R`, `r5_restore.R`, `r5_mutate.R`,
`r5_mem.R`, `r5_peak.R`, `r5_aux.R`); nothing in the repo was edited. Shipped test
file under `NOT_CRAN=true testthat::test_file()`: **149 passed / 0 failed / 0 errors /
0 warnings**.

## Findings

### 1. [fragile] `R/dft_rast_break_class.R:179` — `terra::coltab(stack) <- NULL` strips the colour table from layer 1 only

`coltab<-`'s SpatRaster method is `.local(x, ..., layer = 1, value)`, and the
non-list branch does `layer <- layer[1] - 1; x@pntr$removeColors(layer)`. So on the
7-layer stack:

```
after levels(stack) <- NULL : is.factor 0000000   has.colors 1111111
after coltab(stack) <- NULL : is.factor 0000000   has.colors 0111111   <- layers 2..7 keep their palette
```

`levels<-` is different — `removeCategories(-1)` clears every layer, as the round-5
brief asked to confirm.

Why the shipped test still reads 0 warnings: terra's writer only *attempts* band 1's
colour table. Measured with `extend(filename =)` on the 4 x 5 classified stack:

| stack state | `extend()` warnings | palette re-read from the written TIFF |
|---|---|---|
| untouched (`1111111`) | 2 | — |
| `levels<-` only (`1111111` colours) | 2 | — |
| shipped: `levels<-` + `coltab<-` (`0111111`) | **0** | `0000000` |
| every layer stripped (`0000000`) | 0 | `0000000` |
| layer 1 plain, 2..7 classified (`0111111`) | 0 | — |

So the property the round-4 fix and the new test rely on — "the pad path writes a
stack with no palette" — is delivered by an unmeasured terra internal (band 1 is the
only band whose palette is offered to GDAL), which is the round-3 mechanism again. No
data consequence today: `res$raster` and every `res$breaks` layer report
`has.colors` FALSE, the resample path (single-band write) and the 12-column path are
0 warnings, and the mixed 5-column input (layer 1 plain, 2..7 classified) runs clean
through the full function.

Two honest fixes; pick one and make the comment at lines 159-164 say which:

- **Strip every layer.** `for (i in seq_len(terra::nlyr(stack))) terra::coltab(stack, layer = i) <- NULL`
  gives `0000000`; the test file stays 149/0 with it patched in. Each call runs
  `x@pntr <- x@pntr$deepcopy()` (see finding 2), free on file-backed input; an RSS
  snapshot on 7 x 16M in-memory cells showed no lasting cost, but I could not see
  the transient inside the call — the BULK sampler will. The list form
  `coltab(stack) <- list(NULL, NULL, ...)` is **not** available: it errors
  `[coltab<-] cannot process these color values` because the NULL branch falls
  through to the data.frame check.
- **Keep one call and state the premise**: "only band 1's palette reaches the
  writer, so layer 1 is the one that has to be stripped". That is a claim about
  terra's writer, so it belongs in the comment, not left implicit under "stripping
  them on the STACK".

### 2. [fragile] `tests/testthat/test-dft_rast_break_class.R:295-313` — the caller-unmutated assertions cannot go red, because terra's replacement functions copy before they strip

The brief asked for the dangerous alternative — `levels(r) <- NULL; coltab(r) <- NULL`
on the caller's own object inside the `lapply`, no `deepcopy()` — to turn the
`is.factor`/`cats()`/`coltab()` assertions red. It does not: **149 passed / 0
failed** with both bindings patched (deparse probe on `asNamespace("drift")` and
`package:drift` confirmed `levels(r) <- NULL` present and `deepcopy` absent in each).

The reason is in terra, not in the test. Both replacement methods begin with a copy:

```r
getMethod("levels<-", "SpatRaster")   # { x@pntr <- x@pntr$deepcopy(); if (is.null(value)) { x@pntr$removeCategories(-1); ... } }
getMethod("coltab<-", "SpatRaster")   # .local: x@pntr <- x@pntr$deepcopy(); ... removeColors(layer)
```

Measured: `f <- function(r) { levels(r) <- NULL; terra::coltab(r) <- NULL; r }; f(r)`
leaves the caller `factor=TRUE colors=TRUE`; the same inside `lapply` over the list
leaves both callers untouched. So no placement of `levels<-`/`coltab<-` — on the
caller's object, on a deepcopy, or on the stack — can mutate the caller, and the
"pinned by a test" claim at line 161 pins nothing about where the strip sits.

The only exported path that *does* mutate in place is `set.cats()`: measured,
`set.cats(r, layer = 1, value = NULL)` inside a function flips the caller to
`factor=FALSE` (colours stay). And `rast(list)` genuinely isolates the stack from it —
`set.cats(NULL)` on every layer of the stack left the callers `factor=TRUE` for
in-memory and file-backed inputs alike, pointer identity `x[[1]]@pntr` vs the stack
FALSE. That is the isolation the comment describes, and it is real; it just is not
what the shipped code exercises.

Consequences, in order of weight:

- The comment's cost accounting is off. The old path was `deepcopy()` + a second
  `deepcopy()` inside `levels<-` + `rast(list)`; the shipped path is `rast(list)` + a
  `deepcopy()` inside `levels<-` + another inside `coltab<-`. "One copy rather than
  two" is not the mechanism; the measured +2.5 vs +4.1 GB is accepted as a number and
  the BULK re-measure will settle the peak. If the strip is meant to be one copy,
  the in-place form is `for (i in seq_len(nlyr(stack))) terra::set.cats(stack, layer = i, value = NULL)`
  (measured: `0000000`, +0 MB, caller untouched) — and only with that form does the
  caller-unmutated test become a guard on something the code could get wrong.
- As written, the new test's live assertion is `expect_no_warning` on the 5-column
  case (finding 1 covers what that rests on); restoring `coltab(stack) <- NULL` to
  absent gives 1 failed + 3 test warnings, so that half fires. The
  `is.factor`/`cats`/`coltab` half is decoration under every variant tried.

## Review items, by measurement

### 1. `rast(list_of_SpatRasters)`: copy, not share — all four shapes

`snap()` = `is.factor`, `cats()[[1]]`, `coltab()[[1]]`, `has.colors`, compared with
`identical()` before vs after `rast(list)` + `levels<-` + `coltab<-` on the stack:

| input | caller unchanged | notes |
|---|---|---|
| (a) in-memory factor from `dft_rast_classify(rast(matrix))` | TRUE | stack `is.factor` FF, `has.colors` F **T** (finding 1) |
| (b) file-backed factor, cats/coltab set in session | TRUE | directory unchanged (`a.tif,b.tif`) |
| (c) same R object twice (`list("2017" = r, "2018" = r)`) | TRUE | `r` still factor + coloured; stack `nlyr` 2 |
| (d) layers subset from a multi-layer stack (`big[[1]]`, `big[[2]]`) | TRUE | parent stack still `is.factor` TT |
| (e) copies of `inst/extdata/example_{2017,2020,2023}.tif` through `dft_rast_classify(source = "io-lulc")`, then the full function | TRUE | see item 2 |

`levels(stack) <- NULL` strips every layer (`0000000`); `coltab(stack) <- NULL`
strips layer 1 only (`0111111`) — finding 1.

### 2. Disk side effects — none from the strip or the function

Directory listings (`all.files = TRUE`) of a scratch copy of `inst/extdata/` holding
`example_2017/2020/2023.tif`, taken after copy, after `dft_rast_classify()`, after
`rast(list)` + strip, after `dft_rast_break_class()`, and after `rm()` + `gc()`: all
five identical, no `.aux.xml`. File-backed session-classified inputs (b): same. The
sidecars that appeared in one probe (`r5_peak.R`) were attributed in `r5_aux.R`:
`terra::writeRaster()` of a small in-memory raster writes `<file>.tif.aux.xml`
(both plain and factor); `dft_rast_classify()` on a file-backed raster, the strip,
and the full function add nothing. The `.gitignore` line `inst/extdata/*.aux.xml`
is therefore about some other reader/writer, not this function.

### 3. `wopt$steps` in `app()` — honoured as a floor, values unchanged

4000 x 4000 x 7 in-memory stack (16M cells), `fun` wrapped to count matrix calls
and record chunk rows:

| `wopt` | calls | chunk rows | elapsed | datatype |
|---|---|---|---|---|
| no `steps` | 3 | 13, 8,000,000, 8,000,000 | 5.8 s | INT4S |
| `steps = 2` (the function's `ceiling(ncell / 1e7)`) | 3 | 13, 8e6, 8e6 | 5.6 s | INT4S |
| `steps = 50` | 51 | 13, 320,000 x 50 | 5.0 s | INT4S |
| `steps = 1` explicit | 3 | 13, 8e6, 8e6 | — | — |

So terra takes `max(its own estimate, steps)`: `steps` can only make chunks smaller,
never larger, which is the direction the comment at 199-201 wants. On this machine the
heuristic already chose 8M-cell chunks for 16M cells, so `steps = 2` was a no-op here
and the 1e7 bound only bites where terra's memory estimate would take more cells per
chunk (the 64 GB / 192M-cell case in the comment). `steps = 50` shows it is honoured
when it does bite. Output values: `global(o1 != o2, "sum")` and `o1 != o3` are
`0,0,0,0,0` per layer, NA masks identical, `NAflag` identical. Pad path: a 4000 x 5
crop, `extend(filename =)` then `app(steps = 3)` gave 5 calls (6, 7998, 7998, 7998,
6 rows), `ncol` 6, and after `crop()` the values equal `break_class_scan()` on the
unpadded matrix exactly. No interaction with `datatype` observed.

### 4. Restore-the-bug on the new test — `testthat::test_file()`, both bindings patched

| variant | PASS | FAIL | WARN | verdict |
|---|---|---|---|---|
| shipped | 149 | 0 | 0 | baseline |
| `terra::coltab(stack) <- NULL` removed | 148 | **1** (caller test, `expect_no_warning`) | 3 (2 in the 5-column test, 1 in the caller test) | fix pinned |
| old per-layer `deepcopy()` + `levels(r) <- NULL` + `coltab(r) <- NULL`, no stack strip | 149 | 0 | 0 | accepted alternative passes, as expected |
| dangerous: `levels(r) <- NULL; coltab(r) <- NULL` on the caller's object, no deepcopy | 149 | **0** | 0 | **assertions do not go red** — finding 2 |
| strip every layer's coltab (finding 1 option A) | 149 | 0 | 0 | — |
| restored original | 149 | 0 | 0 | — |

### 5. Anything else — nothing

- `steps` is computed from the padded `stack` (after the `extend()` reassignment), so
  the bound applies to what `app()` actually reads.
- The overflow test (plain code rasters, no factor, no colours) still passes through
  `levels(stack) <- NULL` / `coltab(stack) <- NULL` on a stack with nothing to
  remove.
- `expect_no_warning(res <- dft_rast_break_class(...))` assigns into the test frame
  as intended (`res` is used four lines later).
- Shell/R sweep on the added lines: nothing applicable.

## Accepted, not re-flagged

Everything in round 4's accepted list; the memory numbers in `findings.md` pending
the BULK re-measure.

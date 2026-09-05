# Code-check round 7 — `strip_copy()`, `.aux.xml` cleanup, `steps` 2.5e6, three new pins (staged diff, 2026-09-05)

Narrow scope, as briefed: (A) `strip_copy()` on both the resample and spill branches, (B) the
`.aux.xml` cleanup, (C) `steps` at 2.5e6 cells, (D) the three new test pins. Every claim below
was measured with terra 1.9.34 / testthat 3.3.2 from scratchpad scripts (`r7_src.R`,
`r7_q123.R`, `r7_q4.R`, `r7_q4b.R`, `r7_restore.R` + one `.out` per variant); nothing in the
repo was edited except this file. Shipped test file under `NOT_CRAN=true testthat::test_file()`:
**158 passed / 0 failed / 0 errors / 0 warnings**.

## Findings

### 1. [bug] `R/dft_rast_break_class.R:184` — when `files` is empty at exit, the cleanup runs `unlink(".aux.xml")` against the caller's working directory

`paste0(character(0), ".aux.xml")` is `".aux.xml"` (length 1, not 0 — the zero-length
`paste0()` row under "Zero-length, empty, and unset are three different things" in
`code-check.md`). So `unlink(c(files, paste0(files, ".aux.xml")))` with `files == character(0)`
is `unlink(".aux.xml")`, a relative path resolved in `getwd()`, and it deletes a file the
function does not own.

There is exactly one exit with the handler armed and `files` empty: `on.exit()` is registered
after the input guards (so those error paths never fire it), and every other path calls
`tmpf()` at least once — except the `same.crs` abort inside the `aligned` lapply when no
earlier element spilled, i.e. **the first raster is file-backed and a later raster is in a
different CRS**. Measured through the full function (`r7_q123.R`, Q3 block) with a file named
`.aux.xml` planted in a fresh working directory:

```
first raster file-backed, second in EPSG:32610 -> error "share the CRS" ... cwd/.aux.xml survived: FALSE
control: first raster in memory (spill calls tmpf first)                  cwd/.aux.xml survived: TRUE
```

`unlink()` on a missing path is silent and returns 0 (measured), so on any other cwd this is
invisible; a bare `.aux.xml` in cwd is an unlikely file, which is why the severity is not
higher — but it is a delete outside `tempdir()` on an error path, and the fix is one guard:

```r
on.exit(if (length(files)) unlink(c(files, paste0(files, ".aux.xml"))), add = TRUE)
```

Pin it the way Q3 was measured: plant `.aux.xml` in a `withr::local_dir()`, drive the
file-backed-first + CRS-mismatch error, assert the file survives. It goes red on the shipped
line.

### 2. [fragile] `R/dft_rast_break_class.R:355-369` — the `set.cats(NULL)` half of `strip_copy()` is not pinned, and its roxygen gives a reason (B) has since made redundant

Briefing item 5(ii) expected the spill tempdir pin (`test:2071` block) to go red with
`set.cats` dropped from `strip_copy`. It does not — **158 passed / 0 failed** (`v2_strip_no_setcats`).
The reason is change (B): the spill files are on `files`, so their `.aux.xml` sidecars are now
unlinked by the cleanup whether or not the RAT was stripped before the write. The same holds
on the resample branch. Full matrix, both `load_all()` bindings patched and each mutation
asserted to have taken (`r7_restore.R`):

| variant | PASS | FAIL | what went red |
|---|---|---|---|
| shipped | 158 | 0 | — |
| `set.cats` dropped from `strip_copy` (5ii) | 158 | **0** | nothing — the cleanup removes the 7 spill sidecars |
| resample via `deepcopy()`, aux unlink kept | 158 | **0** | nothing — the cleanup removes the resample sidecar |
| aux unlink dropped, strips kept | 158 | **0** | nothing — the strips prevent every sidecar |
| resample via `deepcopy()` **and** aux unlink dropped (5i) | 156 | 2 | resample pin: 2 new entries, one `.tif.aux.xml` |
| `set.cats` dropped **and** aux unlink dropped | 155 | 3 | resample pin (8 new entries) + spill pin (8 new entries) |
| stack `set.cats` loop dropped (5iii) | 157 | 1 | file-backed no-warning pin: `[app] factors are coerced` |
| `strip_copy` order reversed, `set.cats` first (Q1) | 156 | 2 | 5-column caller pin: `is.factor` FALSE, `cats` NULL on the caller |

So the two tempdir pins pin the **property** (no orphaned sidecar) through two independent
guards, and no single guard is load-bearing for the suite. That is the right thing to pin —
but `strip_copy`'s roxygen (line 360-363, "a RAT becomes a `.aux.xml` sidecar beside the
file") and the resample-branch comment (line 200-201, "a RAT sidecar the cleanup would miss")
both give the sidecar as the reason for the cats strip, and the cleanup no longer misses it.
What the cats strip still buys, measured: nothing the suite or a caller can observe — the
spilled/resampled layer would come back `is.factor TRUE`, which the line-215 stack strip then
removes (5iii pins that). Not a runtime defect; the claim in the briefing that (D) pins the
spill's `set.cats` is what is wrong. Either accept the redundancy and say so in both comments
(one line each), or drop the cats strip and let the cleanup own sidecars. The `coltab<-` half
stays load-bearing (round 6: `SetColorTable() only supported for Byte or UInt16` on every spill).

## Review items, by measurement

### 1. (A) `coltab<-` copies with no colour table present; `strip_copy` order

`selectMethod("coltab<-", "SpatRaster")` deep-copies on its **first line**
(`x@pntr <- x@pntr$deepcopy()`) before any branch, so the copy does not depend on a palette
existing. Measured (`r7_q123.R`, Q1): on a plain code raster, an in-memory factor with
`set.cats` only, and a file-backed factor with `set.cats` only, `strip_copy()` returns an
object whose `@pntr$.pointer` differs from the caller's, the caller keeps `factor=TRUE /
ncats=4`, the copy reads `factor=FALSE / ncats=0`, and the file-backed caller's directory
listing (`all.files = TRUE`) is unchanged. The bad order (`set.cats` first) strips the caller
in place on all three factor shapes and on a classified raster (levels gone, palette kept —
because `coltab<-` then copies). The suite sees it: 2 failures in the 5-column caller test
(table above). No shape hides it — a file-backed factor on a different grid would be stripped
by the identical mechanism, and the suite has no such input, but the mechanism is pinned once.

### 2. (A) Resample branch: sidecar and the caller's file

`resample(strip_copy(caller), ref, method = "near", filename = out)` on a **file-backed**
classified caller whose `.tif.aux.xml` (RAT + palette, Byte) already sits beside it: 0
warnings, tempdir gains `rs_probe.tif` only, values correct, caller still `factor/colors
TRUE/TRUE`, caller `.tif` and `.aux.xml` md5 unchanged. Positive control (unstripped caller):
`rs_ctrl.tif` **and** `rs_ctrl.tif.aux.xml`. Through the full function with that file-backed
finer caller as `x[[4]]`: one new tempdir entry (the output), both caller md5s unchanged,
`x[[4]]` still `factor/colors TRUE/TRUE`.

### 3. (B) Can `paste0(files, ".aux.xml")` name a file that is not ours?

Non-empty `files`: every entry is `tempfile(pattern = "dft_break_class_", fileext = ".tif")`
under `tempdir()` (measured), fresh at creation, so `<entry>.aux.xml` can only have been
written by terra beside `<entry>` — and a prior call's surviving output carries no sidecar
(measured in item 2: output `.tif` only), so no name is reused while it exists. Empty `files`:
finding 1. `unlink()` on a missing path: silent, returns 0.

### 4. (C) `steps` at 2.5e6

4000 x 4000 x 7 file-backed INT1U stack, `scan` wrapped to record chunk rows (`r7_q4.R`):

```
target 2.5e6  steps=7  calls=10  rows: -1 13 2284000 x7 12000   5.0 s
target 1e7    steps=2  calls=4   rows: -1 13 8000000 x2         4.6 s
max |a-b| per layer: 0 0 0 0 0   NA-mask mismatches: 0 0 0 0 0
```

The `-1` is `app()`'s per-row `apply()` probe that the closure refuses, `13` its shape test
chunk, then the real chunks (7 x 2,284,000 + 12,000 = 16,000,000). Pad path on a 4000 x 5
classified series through the real function (`r7_q4b.R`): padded `ncell` 24,000, `steps=1`,
3 calls (`-1 6 24000`), transition identical to `dft_rast_transition()`, output back to 5
columns with `compareGeom` TRUE. 2000 x 2000 x 3 through the function: `steps=2`, chunks
2,000,000 + 2,000,000.

### 5. (D) Restore-the-bug on the three pins

Table in finding 2: (i) red (2), (ii) **green** (finding 2), (iii) red (1). Every variant
confirmed patched in both `asNamespace("drift")` and `package:drift` by deparse before the run,
and each text substitution asserted to have matched exactly once.

### 6. Anything else since round 6

Re-read the whole function against the round-6 text. `on.exit(..., add = TRUE)` evaluates
`files` at exit, so the pad path's `out_file` reassignment leaves the padded `app()` output
on the list and drops only the cropped one — correct. `tmpf()` is still evaluated as the
`filename` argument in both branches. `steps` is computed from the stack `app()` reads.
Nothing else changed.

## Accepted, not re-flagged

Everything in round 6's accepted list; the extra spill pass; BULK numbers pending in
`findings.md`; the `coltab<-`-copies premise (documented in `strip_copy`'s roxygen, pinned by
the caller test, and now also read directly from terra's source: the deepcopy is unconditional).

# Code-check round 6 — `dft_rast_break_class()` spill + in-place strip + double encoding (staged diff, 2026-09-05)

Narrow scope: change (A) the in-place `set.cats(stack, layer = i, value = NULL)` strip and
the pad-only `coltab<-` strip; change (B) the spill of in-memory inputs inside the `aligned`
lapply; change (C) the double-typed encoding in `break_class_scan()`. Every claim below was
measured with terra 1.9.34 / testthat 3.3.2 from scratchpad scripts (`r6_a_spill.R`,
`r6_b_inmem.R`, `r6_b2.R`, `r6_c_rss.R`, `r6_c2a.R`, `r6_c2b.R`, `r6_c3.R`, `r6_d_intdbl.R`,
`r6_e_setcats.R`, `r6_f.R`, `r6_g.R`, `r6_h.R`, `r6_restore.R`); nothing in the repo was
edited. Shipped test file under `NOT_CRAN=true testthat::test_file()`: **151 passed / 0 failed /
0 errors / 0 warnings**.

## Findings

### 1. [bug] `R/dft_rast_break_class.R:172` — the resample intermediate leaves an orphaned `.tif.aux.xml` in `tempdir()` on every call that resamples a classified input

`terra::resample()` of a **factor** raster writes the RAT as a GDAL sidecar beside its
`filename =`, and `unlink(files)` (line 156) removes the `.tif` only. Measured through the
full function with the shipped resample fixture (`x[[4]] <- terra::disagg(x[[4]], 2)`):

```
in-memory (spill)    new tempdir files: dft_break_class_c102288818d9.tif                                          <- the output, correct
resample path        new tempdir files: dft_break_class_c10213011b4f.tif, dft_break_class_c1022545cb85.tif.aux.xml <- orphan
pad path (5 col)     new tempdir files: dft_break_class_c102121ba8c7.tif
file-backed Byte     new tempdir files: dft_break_class_c10220e079fe.tif
```

The orphan's stem is not the surviving output's — it belongs to the resample intermediate
whose `.tif` was unlinked. Attributed directly (`r6_h.R`): `resample(fine, ref, filename = f)`
on the factor input writes `f` + `f.aux.xml`; `unlink(f)` leaves the sidecar; the same for a
**file-backed** factor input on a different grid, which is what `dft_stac_fetch()` returns
once `mask()` spills to disk. `set.cats(NULL)` on a deepcopy *before* the resample removes
it (`stripped_first.tif` alone; caller still factor), and stripping cats alone suffices —
the colour table does not produce a sidecar or a warning on a single-band `resample()` write.

Small files, but it is the documented "different grid" path (roxygen line 15-16 promises
it), it violates the function's own cleanup contract (line 154-155), and it accumulates one
sidecar per resampled layer per call for the life of the session. The stranded-file test
(`test:258`) cannot see it: it drives the overflow path with **plain** rasters, and the
resample test (`test:209`) asserts values only. Two fixes, either is enough:

- Route the resample branch through the same strip the spill branch uses — deepcopy,
  `set.cats(NULL)`, `coltab<- NULL`, *then* `resample(filename = tmpf())`. This also stops
  terra writing a RAT beside a full-grid resample intermediate on BULK.
- Or make the cleanup match what terra writes: `on.exit(unlink(c(files, paste0(files, ".aux.xml"))))`.

Then pin it: the resample test should assert that `tempdir()` gained exactly one
`^dft_break_class_` entry (the output). Same shape as round 3's stranded-file finding —
`code-check-spatial.md`'s "no `.aux.xml` sidecar beside a file-backed CALLER raster" was
measured in round 5 and holds (see item 5 below); the intermediate's sidecar is the one
nobody listed.

### 2. [fragile] `R/dft_rast_break_class.R:180` — the spill-path `set.cats(r, layer = 1, value = NULL)` prevents the same sidecar and is pinned by nothing

Restore-the-bug (both bindings patched, `test_file()`): removing line 180 reads
**151 passed / 0 failed / 0 warnings** — identical to shipped. What it actually guards
(`r6_f.R`): `writeRaster(datatype = "INT4S")` of a raster with cats kept and coltab stripped
emits 0 warnings, returns a factor, and writes `<spill>.tif.aux.xml` — so without line 180
every spilled layer would orphan a sidecar exactly as finding 1 does, and the stack would
still carry `is.factor TRUE` on that layer (the line-187 strip then hides `app()`'s "factors
are coerced" warning). Nothing in the suite would go red or warn. The comment at 176-178
names only the palette warning as the reason for the strip; the sidecar is the second
reason and the one that is silent. If finding 1 is fixed with a tempdir assertion on
classified inputs, this becomes pinned for free — the 5-column caller test at `test:300` is
the natural place (its inputs are in-memory, so they take the spill path).

For contrast, the other three restored defects are pinned:

| variant | PASS | FAIL | WARN | verdict |
|---|---|---|---|---|
| shipped | 151 | 0 | 0 | baseline |
| `deepcopy` dropped (spill mutates the caller) | 149 | **2** (`test:300`, `is.factor` / `has.colors`) | 0 | **pinned** — the deepcopy is load-bearing |
| spill `coltab<- NULL` dropped | 149 | **2** | **146** (`SetColorTable() only supported for Byte or UInt16` on every spill) | pinned |
| spill `set.cats(NULL)` dropped | 151 | 0 | 0 | **not pinned** — this finding |
| `as.double()` encoding → `v[, 1L] * 1000L + v[, n]` | 147 | **4** (closure test + stranded-file test) | 2 (`NAs produced by integer overflow`) | pinned |
| stack strip (line 187) dropped | 151 | 0 | 1 (`[app] factors are coerced` in the resample test) | see item 5 |
| restored original | 151 | 0 | 0 | — |

### 3. [fragile] `R/dft_rast_break_class.R:176-177` — "the copy is a transient of one layer" is two copies of one layer plus a write chunk

`coltab<-` deepcopies unconditionally (round 5, finding 2), so at the moment line 181 runs
the caller's raster, the explicit deepcopy (line 179) and `coltab<-`'s own copy are all
alive; the line-179 copy is only released at the next GC. Then `writeRaster()` streams from
the copy with a chunk buffer rather than a second full copy. Measured in a clean process on
one 8000 x 8000 in-memory double raster (512 MB), RSS at each mark:

```
readAll -> in-memory      865 MB   (baseline 255)
classified                1842     (coltab<- copy + freed intermediates, retained by the allocator)
after deepcopy            1842     (+0: reused a freed block)
after set.cats NULL       1842     (+0: in place)
after coltab<- NULL       2331     (+489: the second copy)
after writeRaster         2579     (+248: one write chunk of 4000 rows; no second full copy)
after rm(copy) + gc       2579     (allocator retention; reused by the next layer)
```

A bare `writeRaster(datatype = "INT4S", COMPRESS=LZW)` of a fresh 512 MB in-memory raster in
its own process: 1952 → 1959 MB (+7), so the write itself is a stream. Across the 7-layer
loop the freed blocks are reused, so the *process* peak is ~caller + 2 copies + chunk of one
layer, not cumulative; on BULK (192M cells, 1.5 GB per copy) that is ~3.3 GB transient over
the inputs rather than the ~1.5 GB the comment implies. Not a defect; the comment and the
`findings.md` accounting should say two copies. The one-copy form is to let `coltab<-` do
the copying — `terra::coltab(r, layer = 1) <- NULL` first (returns a copy, caller untouched),
then `set.cats(r, layer = 1, value = NULL)` in place on it, no explicit deepcopy: measured
+0 / +0 / +0 at the three marks with the caller still factor + coloured. That rests on
`coltab<-` copying (a terra internal, the round-3 mechanism), but the `test:300` caller
assertions would go red the day it stopped, since `set.cats` would then hit the caller.

## Review items, by measurement

### 1. (B) Spill round-trip: values, NA, code 0, negatives, warnings, deepcopy

In-memory double raster with `c(NA, 0, -5, 1, 2, 3e6, 2147483647, -2147483647, 0, NA, 7, 0)`
through the exact spill sequence (deepcopy → `set.cats(NULL)` → `coltab<- NULL` →
`writeRaster(INT4S, LZW)`): read-back is `integer`, `datatype INT4S`, NA mask identical,
every non-NA value identical — 0 stays 0, negatives stay, INT4S max and -max survive.
`-2147483648` (INT4S min) becomes `NA` on read-back (it is GDAL's Int32 nodata); not a class
code anyone has. Classified input carrying IO-LULC-style code 0 (`No Data`) as a real class:
0 warnings, 0 survives as 0 (NA mask identical, the zeros are zeros), spilled raster
`is.factor FALSE / has.colors FALSE`, **caller** still `is.factor TRUE / has.colors TRUE` with
its 5 cats rows. Plain input: 0 warnings. Positive controls: writing the classified raster
with nothing stripped, or with cats stripped and coltab kept, both emit 2 warnings
(`SetColorTable() only supported for Byte or UInt16 bands` + `[writeRaster] change datatype
to INT1U`) and write an `.aux.xml` — so the coltab strip is load-bearing for the spill, not
only for the pad path, and the shipped path writes no sidecar (tempdir gained only the
output file after the function on the 12-pixel in-memory fixture, before and after
`rm()` + `gc()`). Deepcopy restore-the-bug: finding 2's table, row 2 — 2 failures in
`test:300`, both bindings confirmed patched by deparse.

### 2. (B) What `dft_stac_fetch()` returns; `inMemory()` shape

`terra::mask(terra::rast(file), terra::vect(aoi))` on this machine (`memfrac 0.5`,
`memmax 16`, `memmin 1`):

| cells | `inMemory()` | `sources()` |
|---|---|---|
| 0.36M (600²) | TRUE | `""` |
| 16M (4000²) | TRUE | `""` |
| 100M (10000²) | TRUE | `""` |
| 16M with `memmin = 0.001, memmax = 0.02` | **FALSE** | `spat_…tif` in terra's tempdir |

So the spill branch is the common case up to at least 100M cells here (and BULK's 192M, as
the findings.md probe recorded), and the file-backed case exists: three forced-to-disk
`mask()` outputs, classified, ran through the full function in 5.4 s with 0 warnings, one
new `dft_break_class_` file (the output), callers still factor. `inMemory()` is
**per source**: `c(mem, file)` returns `TRUE, FALSE` (length 2) and `if()` on it errors
`the condition has length > 1` — but a single-layer raster always has one source
(`c(mem, file)[[1]]` → length 1; band 2 of a 3-band file → length 1; `@pntr$inMemory` on a
subset of a two-source stack → 1), and the `nlyr == 1` guard at line 125 precedes the
lapply, so the branch never sees a length-2 logical. A values-less raster reads
`inMemory TRUE / hasValues FALSE`; not a shape `dft_stac_fetch()` can return.

### 3. (B) Memory around the spill

Finding 3. Direct answer: `writeRaster()` from an in-memory raster streams (chunk buffer
~1/2 of the raster here, +7 MB lasting in isolation); the transient is set by the
`deepcopy` + `coltab<-`'s internal deepcopy, both alive at once. Lasting RSS after the spill
in one process is allocator retention that the next layer reuses.

### 4. (C) Integer vs double path

`fun` sees `double` from an in-memory stack and from a FLT4S file stack; **`integer`** from
INT4S, INT2S and INT1U file stacks. The 12-pixel `break_series_cases()` fixture run in memory
and after writing each year to INT4S / INT2S / INT1U / FLT4S and reading back through
`dft_rast_classify()`: `$raster` values, `$breaks` values, `cats()` and `$summary` are
`identical()` across all five storages. The closure on a 6-row integer matrix versus the same
matrix as double (interior NA, all-NA, all-zero, 0/1 flicker, a clean switch, code 3e6):
outputs `identical()`, 0 warnings on the integer path. `chg` is a logical matrix from `!=`
either way, so `rowSums()` and `max.col()` see the same NA pattern; `NA_integer_` and
`NA_real_` do not reach them. The `* 1000L` restore reads 4 failures + 2 overflow warnings
(finding 2 table).

### 5. (A) In-place strip on every layer; no `app()` warning; no sidecar beside file-backed callers

Seven file-backed, session-classified callers (`y2017..2023.tif`, INT2S, cats + coltab set on
the file-backed objects): stack before strip `is.factor 1111111`; positive control `app()` on
it → 1 warning `[app] factors are coerced to numeric`; after `set.cats(stack, layer = i,
NULL)` for `i in 1:7` → `0000000` (colours `1111111`, untouched, as designed), `app()` 0
warnings, callers still `1111111 / 1111111`, source directory listing (`all.files = TRUE`)
identical before and after the strip, after the full function, and after `rm()` + `gc()`.
Pad path on file-backed 5-column callers: 0 warnings, directory unchanged, callers intact.
Callers whose **files** already carry a RAT + palette (`.tif.aux.xml` on disk, written as Byte):
0 warnings, callers intact, source directory unchanged.

One note on pinning (finding 2 table, row 6): with the in-memory inputs now pre-stripped by
the spill, the line-187 stack strip is exercised by the suite only through the resample
branch, and removing it reads 0 failures / 1 warning. A file-backed classified input is the
case it exists for and the suite has none; the assertion that would pin it is
`expect_no_warning()` on a classified file-backed series. Low weight — the strip is
measured correct above — recorded so the next round does not read 151 green as evidence.

### 6. Anything else

- Finding 1 is the only defect. The rest of the diff since round 5 re-swept: `tmpf()` is
  evaluated as the `filename` argument in both branches, so an aborted `writeRaster()` /
  `resample()` still has its `.tif` on the cleanup list; the spilled stack is file-backed, so
  the pad path's per-layer `coltab<-` deepcopies cost nothing; `steps` is computed from the
  stack `app()` reads; the overflow test's plain in-memory rasters take the spill branch
  (INT4S holds 3e6), overflow in the scan, and strand nothing (measured in the shipped run).
- `.gitignore`, `NAMESPACE`, the two `.Rd` regenerations and the `dft_rast_consensus.R`
  cross-reference are as described in rounds 1-5.

## Accepted, not re-flagged

Everything in round 5's accepted list; the extra spill pass on in-memory inputs; the BULK
numbers pending in `findings.md`.

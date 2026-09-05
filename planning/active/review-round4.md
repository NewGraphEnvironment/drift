# Code-check round 4 — `dft_rast_break_class()` pad fix (staged diff, 2026-09-05)

Narrow scope: the round-3 fix (pad a 5-column stack by one `NA` column before
`terra::app()`, crop back, re-point `out_file`), its cleanup bookkeeping, and
the two new tests. Every claim below was measured with terra 1.9.34 from
scratchpad scripts (`r4_ntest.R`, `r4_widths.R`, `r4_geom.R`, `r4_restore.R`,
`r4_warn.R`, `r4_one.R`, `r4_misc.R`, `r4_probe_artifact.R`); nothing in the
repo was edited. Shipped test file under `NOT_CRAN=true testthat::test_file()`:
**141 passed / 0 failed / 0 errors / 2 warnings** (the warnings are finding 1).

## Findings

### 1. [fragile] `R/dft_rast_break_class.R:168,185` — `extend()` writes the surviving colour table and GDAL warns twice on every 5-column call

`levels(r) <- NULL` strips the categories but not the colour table (round 3
recorded `has.colors` TRUE and called it harmless because `app()` only reads
values). The pad branch now **writes** that stack to a multi-band GeoTIFF, and
GDAL refuses the palette:

```
/tmp/.../dft_break_class_xxx.tif, band 1: SetColorTable() not supported for multi-sample TIFF files. (GDAL error 6)
[extend] change datatype to INT1U to write the color-table
could not write the color table
```

Measured on a 4 x 5 series built from `dft_rast_classify()` output: 2 warnings;
plain code rasters: 0; classified with `terra::coltab(r) <- NULL`: 0. The
12-column resample path does not warn (single-band file). So every legal
5-column input that came through `dft_rast_classify()` — the documented
producer — emits two GDAL warnings, and the test file that round 3 recorded as
0 warnings now carries 2 (`a raster exactly 5 columns wide ...`). The output is
correct (the padded file is discarded after `crop()`); this is noise, not data
loss, but it sits outside the `withCallingHandlers()` around `app()`, and under
`options(warn = 2)` it is an error on a legal input.

One line beside the existing `levels(r) <- NULL`:

```r
terra::coltab(r) <- NULL
```

Also worth knowing for the record: the padded intermediate is written `INT4U`
(`is.int()` TRUE on every layer; `NoData 4294967295`, `ColorInterp=Palette`),
not `FLT4S`. Fine for non-negative class codes, which is every shipped table;
the cropped output is `INT4S`/LZW as before.

## Review items, by measurement

### 1. Is the 5-column condition complete? — Yes

From `selectMethod("app", "SpatRaster")` lines 33-37, 66-75: `teststart =
max(1, 0.5*nc - 6)`, `ntest = 1 + min(teststart + 12, nc) - teststart`, test
chunk = **one row**, `ncol(r) == ntest` checked before `nrow(r) == ntest`.
Computed for widths 1-20, 25, 50, 100, 101, 314, 600, 11552, 14651:

| width | 1-13 | 14+ |
|---|---|---|
| `ntest` | `== width` | 13 (never fractional; `teststart` is 1.5 at 15 but `ntest` stays integer) |

`ntest == 5` only at width 5. The `nrow(r) == ntest` branch is *always* true
for a cells x 5 return (rows are the test cells) and is reached only when the
first test is false — so widths != 5 always land in the correct branch, and no
width can hit the error arm. `nrow` is inert (one-row test chunk): measured
`nrow = 5` with `ncol` 4, 5, 6, 13, 20 — all identical to the closure.

Full function on widths **1..16 x nrow {1, 4}**, random 4-class series with
10 % `NA` (`r4_widths.R`): `$raster` equals `dft_rast_transition()` on `NA`
mask and values, `cats()` identical, `compareGeom` TRUE, 4 evidence layers
named as documented, `INT4S`, file-backed, summary counts reconcile — 32/32.
Evidence layers identical to `break_class_scan()` on the same matrix. (One
`FALSE` in my sweep's `n_flips` column at 1 x 1 was the probe: `identical()`
on a named scalar from a 1-row `values()` matrix vs an unnamed one; values
equal, and 1 x 1 re-run on five hand sequences incl. interior/endpoint `NA`
matches the closure exactly — `r4_one.R`, `r4_probe_artifact.R`.)

`dft_rast_transition()` is arithmetic (`ifel`/`subst`), not `app()`-based, so
it is an independent reference for the 5-column assertion.

### 2. `extend()` / `crop()` geometry — Correct; no snap hazard

Eight extents (`r4_geom.R`): origin 0; UTM-like `613245.37 / 6034567.89` at
10 m; `0.3 / 0.7` at 0.1 m; `1234567.89 / 987654.321` at 30 m; `500000.123456`
at `9.999999` m; anisotropic `10 x 7`; `res = 1/3`; `7e6 / 3e6` at 2.5 m. On
every one: padded `ncol == 6`, `nrow` 4, 7 layers, `same.crs` TRUE, `res`
equal, `xmin`/`ymax` identical, last column all `NA`, inner cells equal to the
stack; after the function: `compareGeom(res$raster, ref)` TRUE, `ncol` 5, 5
layers with names preserved after `names(out) <-`, `INT4S`, `COMPRESSION=LZW`,
`NoData -2147483648`, `$raster` equal to `dft_rast_transition()`.

Snap: `extend()` with a SpatExtent rounds `(xmax_pad - xmax) / res` to a
column count, and adding exactly one `res` lands on 1 for every geometry
including `1/3`. The one wrinkle: at `res = 1/3` the cropped extent is
`all.equal` but not `identical` to `ref` — `ymin` off by **-5.55e-17**,
introduced by `extend()` itself (only `ymin` moves, and the pad only touched
`xmax`). Inside terra's 0.1-cell tolerance: `rast(list(res$raster, ref))`
stacks, `dft_transition_vectors()` (4 patches), `dft_transition_artifact()`,
`rasterize` + `zonal` all run on it. Not a defect.

### 3. Cleanup-list bookkeeping in the pad branch — Correct

After `out_file <- tmpf()` at 205, `files` holds: resample intermediates (if
any), the extended stack (185), the padded `app()` output (193), the cropped
file (205), then `status` (213). Both `setdiff()` calls (232, 262) remove the
**cropped** path, so the padded output and the extended stack are unlinked at
exit. `out_file` is already the cropped path at the empty-summary return (the
pad block at 204-207 precedes it). Measured: 32 successful runs across the
width sweep leave exactly 32 `dft_break_class_*` files (one output each; the
two 5-column runs stranded nothing extra); a single 5-column call leaves
exactly 1 new file, source exists, values readable.

Restore-the-bug, both bindings patched and proven by a `deparse()` probe on
`asNamespace("drift")` and `package:drift`, `testthat::test_file()`:

| restored | result |
|---|---|
| `out <- crop(..., filename = tmpf())` with no `out_file` re-point | 5-column test **errors**; direct call: `file.exists(sources(r$raster))` **FALSE**, `values()` unreadable — the caller's raster was unlinked |
| literally drop the `out_file <- tmpf()` line | `[crop] source and target filename cannot be the same` — loud, 5-column test errors |

### 4. Do the two new tests reach their failure modes? — Yes

| restored | shipped | restored |
|---|---|---|
| `pad <- FALSE` (round 3's bug) | 141 / 0 | **5 failed** in `a raster exactly 5 columns wide ...` (136 passed) |
| `files <- setdiff(files, out_file)` right after the first `out_file <- tmpf()` (round 2's bug) | 141 / 0 | **1 failed** in `an abort inside the scan (a real overflow) strands no output file` (140 passed) |

### 5. Anything else in the diff — only finding 1

- Test-side: `` `[<-`(m, , , 3L) `` builds the year-4+ matrices correctly; the
  flickering cell (`mats[[5]][1, 1] <- 2L`, sequence 2,2,2,3,2,3,3) is 3 flips,
  so `4 * nc - 1` one-flip cells and 1 three-flip cell are the right expectations;
  the local `ev` shadows the file-level `ev` only inside that block.
- The overflow test is 4 columns wide, so it exercises the non-pad path; the
  5-column + overflow combination would put the padded output on `files` and
  unlink it (same mechanism as the measured 4-column case) — not separately
  measured.
- `e$xmin` on a `SpatExtent` and `terra::ext(xmin, xmax, ymin, ymax)` are the
  documented forms; `terra::ncol()` returns double, `== 5L` is fine.
- Shell/R sweep on the added lines: nothing applicable.

## Accepted, not re-flagged

Everything in round 3's accepted list; the extra pass on 5-column rasters.

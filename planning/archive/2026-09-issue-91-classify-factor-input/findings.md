# Findings — dft_rast_classify() returns empty levels when its input is already a factor (#91)

## Issue context

## Problem

`dft_rast_classify()` returns a raster with **zero levels and no colour table** when its input is already a factor. It raises no error and no warning.

```r
r  <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
cl <- dft_rast_classify(r * 1L, source = "io-lulc")
again <- dft_rast_classify(cl, source = "io-lulc")
nrow(terra::cats(again)[[1]]); terra::has.colors(again)   # 0  FALSE
```

The cause is `present_codes <- terra::unique(x)[, 1]` (`R/dft_rast_classify.R:44`). On a factor, `terra::unique()` returns the **labels** (`"Water"`, `"Trees"`, ...), not the codes. `class_table$code %in% present_codes` then matches nothing, so `ct` is empty and both setters are given empty tables.

This is the ordinary case, not a contrived one. The published floodplain rasters are factors: `stac-floodplains-bc/bulk_co_ff04/classified_2017.tif` carries a RAT with a `class_name` column and a palette. Classifying one of those, for example to apply a `remap =`, returns a factor raster with no categories. Found in #89's BULK scale check, where the output had neither levels nor colours on `main` and on the branch alike.

## Fix

Take the present codes from the raw values, not from `unique()` on the factor: for example `terra::unique(x, as.raster = FALSE)` on a level-stripped copy, or `terra::freq(x, bylayer = FALSE)` with `value` as codes. Add a test that re-classifies a classified raster and a test on a raster that carries its own RAT. Check whether the `remap =` path (`terra::classify()` on a factor) has the same shape.

Related: #19, which concerns factor input to `dft_rast_transition()`.

## Probes (terra 1.9.50, 2026-09-29)

- `terra::unique()` on a SpatRaster calls `x@pntr$unique()` (raw codes) then `get_labels()` — labels for a factor.
- `activeCat(y) <- 0` or `levels(y) <- NULL` on a copy recovers the codes; `strip_copy()` (dft_rast_break_class.R) already does it with one copy.
- remap with a matching group: `terra::classify()` drops the factor, so levels come back fine (6). No matching group: classify skipped, bug reproduces.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Scale check — BULK `classified_2017.tif` (2026-09-29, `/usr/bin/time -l`, terra 1.9.50)

Input: the published file, a factor with a RAT (`value`, `class_name`, rgba) and a palette, 14651 x 11552.
`main` = `git archive main`, branch = working tree, both via `pkgload::load_all()`; script in session scratchpad (`scale91.R`).

| input | src | classify() elapsed | peak RSS | levels out | colours |
|---|---|---|---|---|---|
| file-backed factor | main | 0.8 s | 1.05 GiB | 0 | FALSE |
| file-backed factor | branch | 0.8 s | 1.05 GiB | 9 | TRUE |
| in-memory factor | main | 1.1 s | 4.08 GiB | 0 | FALSE |
| in-memory factor | branch | 2.0 s | 5.46 GiB | 9 | TRUE |
| in-memory setup only | — | — | 2.94 GiB | — | — |

- File-backed: `strip_copy()` and `coltab<-` copy metadata only; peak unchanged.
- In memory: the strip is one extra full copy of the values, +1.39 GiB peak (5.46 vs 4.08). Paid only by
  in-memory factor input, i.e. re-classifying a raster already classified in this session.
- No R-level way to read a factor's raw codes without a copy was found: `activeCat<-` and `levels<-` both
  `deepcopy()`; `unique()`/`freq()` return labels; mapping labels back through `cats()` breaks on duplicate
  labels and on values absent from the RAT (plan review probe).

### Re-run after moving the strip after remap (same script, 2026-09-29)

| input | main peak | branch peak | branch levels / colours |
|---|---|---|---|
| file-backed factor | 1.05 GiB | 1.05 GiB | 9 / TRUE (main 0 / FALSE) |
| in-memory factor | 4.20 GiB | 5.47 GiB | 9 / TRUE (main 0 / FALSE) |
| in-memory factor + matching remap | 5.47 GiB | 5.47 GiB | 8 / TRUE (main 8 / TRUE) |

The matching-remap path no longer pays for the strip. Only an unremapped in-memory factor does
(+1.27 GiB in this run, +1.39 GiB in the first; run-to-run spread of ~0.1 GiB on the main baseline).

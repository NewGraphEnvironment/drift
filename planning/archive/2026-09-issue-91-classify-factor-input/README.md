## Outcome

`dft_rast_classify()` returned a factor with no levels and no colours when its input was already a
factor (a published floodplain raster with a RAT, or one re-classified), because `terra::unique()` on
a factor returns labels, not codes. Fixed by stripping the levels on a copy with the existing
`strip_copy()` after the remap step. `terra::classify()` already reads raw codes, so a matching remap
needs no strip. The guard is `is.factor(x)[1]`. The plan review and code-check round 1 both found, independently,
that a bare `is.factor(x)` errors on a multi-layer stack, which `main` had classified on layer 1 without
error. Four factor-input tests plus stack and active-category tests. Mutation checks: an in-place strip
reddens both caller-unmodified tests, and dropping `[1]` reddens the stack test. Code-check ran 3 rounds
(1 finding, then Clean, Clean).

## Measurement

BULK `classified_2017.tif` (169M cells, published RAT), `/usr/bin/time -l`, `main` vs branch:
file-backed factor 1.05 vs 1.05 GiB (levels 0 → 9); in-memory factor 4.20 vs 5.47 GiB (the strip is
one full extra copy, and no R-level terra call reads a factor's codes without one); in-memory factor with
a matching remap 5.47 vs 5.47 GiB. That last number is why the strip was moved after the remap: the first
placement, before the remap, would have charged a copy that `classify()` throws away. Tables in `findings.md`.

Closed by: commit 618e805 / PR (see branch `91-dft-rast-classify-returns-empty-levels-w`)

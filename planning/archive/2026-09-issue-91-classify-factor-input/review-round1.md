# Code review, round 1 (#91)

## Findings

- **[fragile]** R/dft_rast_classify.R:44 — `if (terra::is.factor(x))` fails on a multi-layer
  SpatRaster. `terra::is.factor()` returns one logical per layer, so for `c(r17, r20)` the
  condition has length 2, and R >= 4.2 stops with "the condition has length > 1". Measured in a
  scratch copy on terra 1.9.50. Before the diff, the same stack returned without error, but only
  layer 1 was classified (`is.factor` gave `TRUE FALSE`). The old behaviour was already silently
  wrong, so no correct output is lost. What changes is that a documented input type ("A
  SpatRaster") now fails with a message that names neither the function nor the cause. No caller
  in R/, vignettes/, data-raw/ or tests passes a stack; they all pass named lists. Possible fixes:
  guard `terra::nlyr(x) == 1` with a clear error, or use `if (any(terra::is.factor(x)))` and
  accept that only layer 1 is handled, as before. Low severity.

## Probed and clean

- A factor input with levels but no colour table, both in memory and file-backed from a tif with
  a RAT. `strip_copy()`'s `coltab<- NULL` still copies, so the caller keeps its levels, its lack
  of colours and its names, and the output gets class_table's levels.
- A factor input whose active category is not the first column (`activeCat = 2`). The output
  levels are correct, and the caller's `activeCat` and names are unchanged.
- The new test file passes 50/50 in a scratch copy (`NOT_CRAN=true`, `test_file`).
- The black-colour assertion in the RAT test depends on the fixture. io-lulc code 0 (No Data)
  is `#000000`, but example_2017 contains no code 0, so the assertion is valid for this fixture.
- The planning files make no factual claim that contradicts the code.

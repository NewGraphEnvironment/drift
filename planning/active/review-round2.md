# Review round 2 — #89 (`dft_rast_classify()` mutates the caller's raster)

## Clean

No issues found in the diff.

## What was verified (terra 1.9.50; probes in a scratchpad copy, repo untouched)

- **The fix holds at the DESCRIPTION floor, not just the installed terra.** `terra (>= 1.8-10)`.
  Pulled `R/colors.R` at tag `1.8-10` from the cran/terra mirror: `setMethod("coltab<-", "SpatRaster")`
  already opens with `x@pntr <- x@pntr$deepcopy()` before any branch. So no supported terra lets
  `set.cats()` reach the caller.
- **Restore-the-bug, per shape.** Copied the tree, put back `HEAD:R/dft_rast_classify.R` (the exact
  prior bytes), and checked the caller after each call. Under the old ordering the caller came back as
  `class_name`/factor for all three test shapes (file-backed, `* 1L` in-memory, list element). Under the
  new ordering all three stay `data`/non-factor/no colours. Each shape in the new test therefore
  contributes its own two red expectations (`names`, `is.factor`) under the defect: 3 x 2 = 6, which
  matches the author's and round 1's count. None of the three passes vacuously. `has.colors` is the one
  arm that cannot fire under the old code, because `coltab<-` always copied. It is the arm that fires
  if terra ever makes `coltab<-` in place, as the code comment says, so it is not decoration.
- **Shapes the test does not cover are also fixed.** Remap with no matching class (so `x` is still the
  caller's object when it reaches `coltab<-`), remap with a match, a two-layer stack, and an input with
  no code in the class table (empty `ct`). Under the old code the caller was mutated in every case
  except the matching remap, and under the new code in none.
- **Nothing relied on the mutation.**
  - `R/`: `dft_rast_classify` appears only in roxygen examples, and every one assigns the result.
  - Tests: every call site uses the return value. The only skip guards in files that call it are
    `skip_on_cran()`, which runs under `devtools::test()`, and an lwgeom skip, which is not about
    classify.
  - `data-raw/break_class_groups.R` reuses `rasters` after classifying (lines 942, 949, 1295, 1343):
    - `bare_int()` strips levels and colours either way.
    - The `app()` water-core pass compares raw codes, which a factor also yields.
    - The sliver crops (1343 -> `bulk_slivers.rds`) are the one place where the output shape changes
      on a re-run: they will be non-factor where the committed artifact is a factor. Its consumer, the
      `temporal-composition` article, reads `terra::values()` (raw codes), sets its own value-keyed
      `coltab<-` and plots, so it renders the same with either shape.
  - `data-raw/disturbance_compare.R` and `break_class_groups.R` alias `ref <- rasters[[1]]` before
    classifying, but read only its geometry (crs, res, dims, ncell).
  - The vignettes reassign or never reuse their input.
- **The removed comment's test still holds.** `test-dft_accuracy_sample.R:136` still builds fresh
  tiles, and the file-level `r17` is never passed to classify. So the test does not depend on the
  deleted premise, and the removal is housekeeping only.
- **Output unchanged.** `set.cats()` after `coltab<-` keeps the colour table, and the test asserts
  `has.colors`, `is.factor` and the `class_name` name on each result.

## Not findings

- factor input -> `terra::unique()` returns labels (drift#91): out of scope, as briefed.

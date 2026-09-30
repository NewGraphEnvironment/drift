# Task: dft_rast_classify() mutates the caller's raster in place (set.cats on the input) (#89)

`dft_rast_classify()` calls `terra::set.cats(x, ...)` on the raster it was given (`R/dft_rast_classify.R:49`). `set.cats()` works in place, so the caller's object turns into a factor named `class_name`. When `remap = NULL`, `x` is the caller's own SpatRaster, not a copy.

```r
r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
names(r); terra::is.factor(r)        # "data" FALSE
cl <- dft_rast_classify(list("2017" = r), source = "io-lulc")
names(r); terra::is.factor(r)        # "class_name" TRUE   <- the input changed
```

Found in #81. A test built `c(r17, r23)` from the raw tiles after an earlier test had classified `r17`, and the layer names were no longer the file's. Any caller that classifies a raster and then reuses the original for anything that reads names or levels is affected, for example stacking it or passing it back into a function that validates it.

CLAUDE.md's spatial conventions already name the trap: `set.cats()` "mutates whatever raster it is given, so use it on a copy you own".

## Phase 1: Test first

- [x] Add `test_that("the caller's raster is not modified", ...)` to
  `tests/testthat/test-dft_rast_classify.R`: file-backed single raster, an in-memory raster
  (`r * 1L`), and a named-list element — each keeps `names()` (`"data"` / its own), stays
  `!is.factor()`, `has.colors()` unchanged; the returned raster is still a factor with the colour
  table. Confirm it fails on current code.

## Phase 2: Fix

- [x] In `R/dft_rast_classify.R`, set `coltab<-` before `set.cats()`, with a comment naming why the
  order is load-bearing (the copy `coltab<-` makes is what `set.cats()` then mutates; see
  `strip_copy()`), and replace the stale "namespace issues" comment.
- [x] Restore-the-bug check: swap the order back, confirm the new test goes red, restore.
- [x] `devtools::test()` full suite, `lintr::lint_package()`, `devtools::document()` (no roxygen
  change expected).

## Phase 3: Scale check on BULK (CLAUDE.md convention)

- [ ] `bulk_co_ff04/classified_2017.tif` into the scratchpad; `dft_rast_classify()` on it both
  file-backed and in-memory (`r * 1L`, 169M cells), `origin/main` code vs branch code, RSS sampled
  every 2 s. Expect peak RSS unchanged (the copy count is the same) and caller unmutated at scale.
  Record numbers in `findings.md` and the PR body.

## Phase 4: Release

- [ ] `NEWS.md` 0.19.1 entry (fix, the probe table in one line, why reorder not deepcopy);
  `DESCRIPTION` 0.19.0 → 0.19.1 as the final commit ("Release v0.19.1 (#89)"), matching the
  on-branch release commits of #79–#81.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

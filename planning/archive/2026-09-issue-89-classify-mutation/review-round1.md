# Review round 1 — #89 (`dft_rast_classify()` mutates the caller's raster)

## Clean

No issues found in the diff.

## What was verified (terra 1.9.50, probes run from the scratchpad, repo untouched)

- **`coltab<-` copies unconditionally.** Printed the `coltab<-` SpatRaster method: its first
  statement is `x@pntr <- x@pntr$deepcopy()`, before any branch on `value` or `layer`, so it copies
  for a data.frame value (this call) as well as for `NULL` (the `strip_copy()` call). `set.cats()`
  therefore only ever reaches the copy.
- **New ordering matches the old one.** Ran the new function against a copy of the old
  set.cats-then-coltab body over nine inputs: file-backed; in-memory (`* 1L`); all-NA (empty
  `ct`); no code in the class table (`* 0L + 99L`, empty `ct`); a single code; a caller already a
  factor; a caller already carrying a coltab; an already-classified raster; and a two-layer stack.
  In all nine `cats()`, `coltab()`, `names()`, `is.factor()`, `has.colors()` and the values were
  `identical()` between the two orderings. `set.cats()` after `coltab<-` keeps the colour table.
  The empty-`ct` case neither errors nor behaves differently in either order.
- **The caller is untouched in all nine cases**, including the multi-layer stack. `names`,
  `is.factor`, `has.colors`, `cats` and `coltab` were `identical()` before and after the call. The
  remap path is also unaffected: `terra::classify()` already returns a new raster, and the remapped
  output still carries both levels and colours.
- **Restore the bug:** evaluated the new `test_that()` block against the old ordering and it fails
  with 6 failures, 13 successes, which matches the author's number. The guard fires. Unlike a
  `levels<-`/`coltab<-` strip (checklist, "copy before they strip"), this test *can* fail, because
  the old code reached the caller through the in-place `set.cats()`.
- Every in-package call site uses the return value. Nothing depended on the in-place mutation.

## Observations outside this diff (not findings)

- `tests/testthat/test-dft_accuracy_sample.R:137`: the comment "fresh tiles:
  dft_rast_classify() mutates its input in place (#89)" is stale once this merges. The test still
  passes, so this is housekeeping only.
- A pre-existing issue, the same in both orderings: when the input is **already a factor**,
  `terra::unique(x)[, 1]` returns the labels, not the codes. `ct` then comes back empty, and the
  output has no colours and no usable levels. This happens when an already-classified raster is
  re-classified, or when the caller's raster is a factor with other labels. The diff does not
  cause it; it may be worth its own issue.

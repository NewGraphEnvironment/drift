# Code review, round 2 (#91)

## Clean

No code defects found. The round-1 fixes (`is.factor(x)[1]`, strip moved after remap,
rewritten #89 comment) introduce none.

## Probed (scratch copy, terra 1.9.50, `pkgload::load_all()`)

- **Caller unmodified in every remap branch.** A factor input's `cats()`, `coltab()`, values,
  `activeCat` and names are unchanged after each of: `remap = NULL`, a matching remap, a
  non-matching remap (warning, `rcl` NULL, so `x` stays the caller's raster until
  `strip_copy()`), and `remap = list()` (same path as non-matching, no warning). The same
  holds for a file-backed factor read from a tif, and for plain input with a non-matching remap.
- **`terra::classify()` on a factor** reads raw codes and returns a plain raster
  (`is.factor` FALSE, `has.colors` FALSE, `unique()` gives codes). So the matched-remap
  branch needs no strip, as the comment says, and its output gets the remapped levels
  (6 levels, `Vegetation` at code 2).
- **Stacks.** `c(factor, factor)`, `c(factor, plain)` and `c(plain, factor)`, each with all
  three remap cases: no error, the caller's stack is unmodified in all 9 runs, and layer 1 gets
  the expected levels. `strip_copy()` strips layer 1 only, which the layer-1-only
  `unique(x)[, 1]` needs.
- **Named list** with one factor element and one plain element: both callers are unmodified
  and both outputs have identical levels.
- **Test file:** all expectations pass (`NOT_CRAN=true`, `test_file`).
- **Comment accuracy.** "Unless it was stripped or remapped above, `x` is the caller's own
  raster" holds in every branch, and non-matching remap does return the caller's raster.
  "A stripped factor has already paid one more" also holds: `strip_copy()`'s `coltab<-` makes
  one deep copy and the main `coltab<-` makes another, so the factor path makes two copies
  and the plain path one.

## Planning-file note (not a code issue)

- `planning/active/task_plan.md` Phase 2 still reads "[x] Strip factor input with
  `strip_copy()` before remap". The code now strips *after* remap. `progress.md` records the
  move, but the task line is stale.

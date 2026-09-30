# Code review, round 3 (#91)

## Clean

No code defects found, and every NEWS.md `# drift 0.19.2` claim matches the code and the
measurements.

## The mechanism behind round 1, and where it could reach in this diff

The mechanism is a per-layer terra predicate (`is.factor`, `has.colors`, `activeCat`, `nlyr`,
the columns of `unique()`) used as a scalar. On a multi-layer raster it returns a vector, and
`if ()` on that vector errors in R >= 4.2. I checked every place in the diff that it could reach:

- `R/dft_rast_classify.R:52`, `if (terra::is.factor(x)[1])`. This is the fix. Round 2 probed
  it on stacks (9 combinations).
- `strip_copy()` (reached from line 53). Both setters pass `layer = 1` explicitly.
- `R/dft_rast_classify.R:57`, `terra::unique(x)[, 1]`. It takes layer 1's column. Layer 1 has
  been stripped whenever it was a factor, so that column holds codes whatever the other layers
  are.
- `R/dft_rast_classify.R:68`, `coltab<-` with no `layer` argument. The default is layer 1, so
  the result is a scalar. This line predates the diff.
- Tests: `expect_true(is.factor(twice))`, `expect_true(is.factor(rat))`,
  `expect_true(has.colors(miss))`, `expect_true(has.colors(out))` and
  `expect_identical(activeCat(r), 2L)` all run on single-layer inputs. If one of them got a
  longer vector, `expect_true` would fail loudly rather than pass. In the stack test,
  `expect_identical(terra::nlyr(out), 2)` is correct because `nlyr()` returns a double
  (measured).

None of them is affected.

## NEWS claims checked (scratch copies of the branch and of `git archive main`, terra 1.9.50)

- **"returned zero levels and no colour table, with no error or warning"**: on main, re-classifying
  a classified raster gives `is.factor` TRUE, `cats()` NULL and `has.colors` FALSE. No
  condition is raised; I caught all warnings and messages and there were none.
- **"the same as 0.19.1"**: `main` was 18153ba. The only commit after the v0.19.1 release is the
  CITATION.cff update, and DESCRIPTION reads 0.19.1. Both measurement runs give 1.05 GiB for
  main and for the branch on the file-backed input.
- **"5.47 GiB against 4.20 GiB"**: this is the re-run table in findings.md, main 4.20 against
  branch 5.47. The first run (4.08 against 5.46) is within the spread that findings.md records.
- **"costs something only for an in-memory factor with no matching remap"**: in the re-run, the
  matching remap peaks at 5.47 GiB on both main and the branch. There, the `classify()` copy
  plays the part the strip copy plays otherwise.
- **"A remap = that matched a class already worked"**: on main, a factor with a matching remap
  returns levels. A partial remap (one group matching, one not) also returns 6 levels on main.
- **"A remap = that matched nothing had the bug"**: on main, `apply_remap()` returns `x`
  unchanged when `rcl` is NULL. The output then has 0 levels, and so does `remap = list()`.
  On the branch, both return 7 levels.
- **"activeCat<- and levels<- both copy"**: both method bodies call `deepcopy()` in terra
  1.9.50. The claim is hedged ("No terra call found"), and I found nothing that contradicts
  it. `values()` does return raw codes, but it loads every cell into R, which is itself a full
  copy. `unique()` and `freq()` return labels.
- **"A multi-layer SpatRaster still classifies layer 1 only, as before"**: the setters and
  `unique()[, 1]` work on layer 1 only, and the stack test pins this.

## Test file

58/58 pass (`NOT_CRAN=true`, `testthat::test_file`, scratch copy).

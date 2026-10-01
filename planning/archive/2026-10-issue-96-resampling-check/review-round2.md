# Code-check round 2 — #96 (staged diff)

## Clean

No issues found.

## What was checked, and how

Worked in a copy (`rsync` of the tree to the scratchpad); nothing in the repo was edited except this file.

- **The round-1 fix holds and is not vacuous.** `expect_error(resampling_check("bilinaer"), "does not know as \"near\"")`.
  Mutated the copy's `resampling_check()` to `fallback = "nearX"` and ran `test_file()`. The #96 block went red
  (an error, because testthat 3e re-raises an error that does not match the regexp; it is still red). The closing quote in
  the pattern is what makes it discriminate, so `"near"` inside the allowed list cannot satisfy it.
- **Same class swept across every new assertion.** Each message was rendered through the real code path under
  `local_reproducible_output()`:
  - `"cubicspline"` appears only in the headline's allowed list. That is the claim it pins.
  - `"bilinaer"` appears only in the `Got` bullet.
  - `reads as "average"` and `use "med"` cannot be matched by `"average"` or `"med"` in the allowed list, because their
    prefixes are not there.
  - `expect_no_match(..., "does not know")` on `"mean"` is a real negative. The alias bullet replaces the fallback bullet.
  - `aggregation_check("bilinear")` with `"none"`: "none" appears nowhere else in that message. The allowed list is
    min, max, mean, median, first and last, and "one of" is not "none".
- **The cli fold before `{.val {fallback}}` renders.** The output was "...does not know as "near" without an error" and
  "...as "none"...". The interpolation was not swallowed.
- **Call-site tests are non-vacuous by construction.** `stac_cube_assemble()` and `fetch_extent_to()` get placeholder
  args such as `cfg = list()` and `target_crs = NULL`. Without the check, each would fail later with an unclassed
  error, and `expect_error(class = ...)` would go red. The `aggregation = "count"` case in `fetch_extent_to()` exercises
  the newly added `aggregation_check()`.
- **The composite count case** refuses at the top-level `resampling_check()`. That happens before the cache, before
  `stac_cube_items()` (mocked to `stop()`) and before the `"first"` substitution. The comment gives the reason refusing
  matters, not the mechanism, so it is not false.
- **The count path through the new `fetch_extent_to()` / `stac_cube_assemble()` checks.** The composite passes
  `"first"` downstream for a count. `dft_stac_fetch()` defaults to `"first"` / `"near"`, and no source config injects
  an aggregation or resampling. So the added last-line checks cannot refuse a value the entry points accepted.
- **Case.** gdalcubes 0.7.5 lower-cases both arguments, measured on Bilinear, Q1, MED, CubicSpline, LANCZOS, Mode,
  AVERAGE, Median, FIRST and Mean. So the case-insensitive acceptance matches what gdalcubes honours. Returning the
  value as given keeps cache keys stable, which is the accepted tradeoff.
- **The alias lookup.** `aliases[tolower(x)]` on a named atomic vector matches exactly and returns `NA` for a miss,
  including with `character(0)` and `""`. It is reached only when `is_string`, so `NA`, `NULL`, `character(0)`,
  length-2 and numeric inputs cannot index it.
- **`call = rlang::caller_env()`** is evaluated in `cube_view_choice_check()`'s frame, so it names
  `resampling_check()` / `aggregation_check()`. That is the same frame the pre-refactor `aggregation_check()` reported.
  There is no regression.
- **Test results.** Every #96 block passed: cube 37/13/11/3 expectations and composite 7, with 0 failed and 0 errors.
  They do not skip on CRAN. The one `skip_if_not_installed("gdalcubes")` sits in the blocks that need it.

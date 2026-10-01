# Review round 1 — #96 resampling_check (staged diff)

## Findings

- **[fragile]** tests/testthat/test-dft_stac_cube.R, in "resampling_check refuses anything outside the set..." — `expect_error(drift:::resampling_check("bilinaer"), "near")` cannot fail. The comment says it pins "the fallback", but the headline already interpolates the allowed set, and the set's first member is `"near"`: `` `resampling` must be one of "near", "bilinear", ... ``. If the `x` bullet were deleted, or its `{.val {fallback}}` rendered empty or named the wrong fallback (for example `"none"`, a copy-paste from the aggregation branch), the assertion would still match. This is the code-check rule "An assertion that matches an interpolated value cannot see the claim around it". To pin the claim, match the rendered sentence instead, e.g. `"does not know as \"near\""`, which only the bullet contains. The aggregation counterpart (`expect_error(aggregation_check("bilinear"), "none")`) is fine: `"none"` does not appear in the aggregation set.

## Checked and found sound

- Every `gdalcubes::cube_view()` call site in `R/` (two: `stac_cube_assemble()` and `fetch_extent_to()`) now has `resampling_check()`, and so do all three exported entry points. Each entry point calls it before any network access or cache-key use.
- The value is returned as given. Cache keys are unchanged for callers that already pass valid values, and no shipped caller (R/, vignettes/, data-raw/, tests/) passes a now-refused value: the defaults are `"near"` and `"bilinear"`.
- Alias lookup `unname(aliases[tolower(x)])` behaves correctly for `""`, for unmatched names and for the empty `aliases = character(0)` on the aggregation path: single-bracket indexing does not partial-match and returns NA. Non-string inputs skip the lookup.
- The cli messages render correctly at `cli.condition_width = Inf` for a typo, for each alias (including mixed case), for a numeric value, for NA, and for the aggregation path. The `{.val {fallback}}` placed after a line-fold renders; it is not swallowed.
- The error `call` is the internal helper's frame (`resampling_check()` / `aggregation_check()`), which is the same as before the refactor for aggregation, so this is no regression.
- Restore-the-bug reasoning: removing any one call-site check makes a test go red. The entry-point tests would hit the `stop("reached the network")` mocks, and the internal call-site test would hit an unclassed gdalcubes or argument error.
- I ran the tests in a copy (`NOT_CRAN=true`, `load_all`). test-dft_stac_cube.R, test-dft_stac_composite.R and test-dft_stac_fetch.R all pass, with 0 failures; only the network and missing-package tests were skipped. gdalcubes is 0.7.5.

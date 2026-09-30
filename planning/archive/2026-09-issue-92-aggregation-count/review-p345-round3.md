# Review p345 round 3: #92 key/filename flows, the case-preserving fix, anything missed

Snapshot: scratchpad/p345snap (staged index). Read-only review; mutations run in copies
(scratchpad/mut, scratchpad/mut2), nothing under the repo edited except this file.

## Findings

- **[fragile] tests/testthat/test-dft_stac_composite.R:568-571 — the `"Median"` pin cannot see the defect its comment says it guards, and nothing pins the flow at any of the three callers.**
  The comment reads "neither may the aggregation check, which keeps the caller's case", but
  `ckey()` calls `stac_composite_cache_key()` directly and never passes through
  `aggregation_check()` or `dft_stac_composite()`. Measured by mutation (tabulated with
  `reporter = "silent"`, since the summary reporter's failure lines do not match a
  `Failure|Error` grep):
  - `aggregation_check()` reverted to `tolower(aggregation)` (the round-2 bug itself):
    test-dft_stac_composite.R **0 failed / 103 passed**, so the pin stays green. Only the unit
    test in test-dft_stac_cube.R ("aggregation_check refuses anything...", 2 expectations)
    goes red.
  - `aggregation <- tolower(aggregation)` inserted right after the check in
    `dft_stac_composite()`, `dft_stac_cube()` and `dft_stac_fetch()` (the same key move,
    one line later): composite **0 failed / 103**, cube **0 / 141**, fetch **0 / 154**.
    All green.

  So the round-2 mechanism, a normalisation that leaks into the cache key, is guarded only
  by the helper's return value. It is not guarded at any of the six flows the findings.md
  row enumerates, and the row's "Pinned the `"Median"` key; 3 mutations turn red" overstates
  what the pin covers. The shipped code is correct (see below). This is about the guard.
  **Fix:** drive the exported function with a mixed-case value and assert the key it produces.
  For example, mock `stac_composite_cache_key` (and `stac_cube_cache_key` /
  `stac_cache_key`) with a wrapper that records `aggregation` and then stops. Assert that
  `"Median"` arrives as given, or assert the key against the v0.19.2 value. The probe below
  already does this and could be lifted into the tests. Also correct the comment.

## The mechanism check: every existing key, v0.19.2 vs now (all computed)

Computed with `scratchpad/keyprobe.R`, run under `pkgload::load_all()` of each tree
(`git archive v0.19.2`, and the snapshot). The probe calls the **exported** functions on the
packaged AOI. It wraps the real key function, records the key, then stops before the network.
Fetch additionally mocks `stac_items_paged` and `gdalcubes::stac_image_collection`.

| call | v0.19.2 | now | |
|---|---|---|---|
| composite default | 48e93230456245ee | 48e93230456245ee | same |
| composite `"Median"` | 15e150a8c375b3a3 | 15e150a8c375b3a3 | same |
| composite `"MEAN"` / `first` / `last` | b26b.. / 7e6c.. / 169e.. | identical | same |
| composite months `c(7,6)` / `7L` / `c(6,7,8)` | 4893.. / 0d20.. / d99f.. | identical | same |
| composite mask `c(11,3)` / `c(3L,8L)` | 8ae3.. / c88b.. | identical | same |
| composite tile 5000 / 5003 (snapped) | 77fb.. / 77fb.. | identical | same |
| composite clip `TRUE` / `"TRUE"` | d59d.. / d59d.. | identical | same |
| composite bands nir,red,green / `"red"`; res 20; resampling near; cc 100 | 72c7.. / 71a8.. / fda1.. / c102.. / 8fc3.. | identical | same |
| cube default / `"Median"` / `"LAST"` / mean | ccae.. / 0ea4.. / 6fc5.. / 6ccd.. | identical | same |
| cube dt P1Y / months 6:9 / mask / tile 5003 / clip 1 / ndvi | d5aa.. / 1cab.. / c07b.. / a61e.. / ccae.. / cc47.. | identical | same |
| fetch default / `"First"` / median / `"MEDIAN"` / tile / dt P1M | 3115.. / 0e86.. / 3631.. / 888b.. / a243.. / cc49.. | identical | same |
| composite `"count"` | 5dacaac91ec8ecad (`composite_`) | 4ed9b46904b621ef (`count_`) | intended |
| composite `"Count"` | cdcb020e1afcbf67 (`composite_`) | 4ed9b46904b621ef (`count_`) | intended (case-folded, new family) |
| cube `"count"`, fetch `"none"` | keyed | refused | intended, in NEWS |

- **No existing non-count key moved**, for `aggregation` in any case, `bands`, `months`,
  `mask_values`, `dt`, `tile_size`, `clip`, `res`, `resampling` or `cloud_cover_max`.
- **Branch changes by parameter.** The branch changes no normalisation other than
  `aggregation` (`git diff --stat v0.19.2 HEAD -- R/` plus the staged diff touch only the three
  `stac` files). `clip`, `tile_size`, `months` and `mask_values` normalise exactly as in
  v0.19.2.
- **The `"COUNT"` to `"count"` fold.** It reaches only the new `count_` family. `family`,
  `dt_read = "P1D"` and the `count_` filename prefix all derive from `is_count`.
- **gdalcubes sees the same values as in v0.19.2.** A non-count value goes to `cube_view()` as
  given, the same as before; gdalcubes lower-cases on its own side. A count sends `"first"`.
- **`stac_cube_assemble()`'s new `aggregation_check()`** is a pure check. Its return value is
  discarded, so it moves nothing.

## The code fix itself: correct

- `is_count <- identical(tolower(aggregation), "count")` is safe:
  `aggregation_check()` guarantees a length-1, non-NA character.
- Only the count family is rewritten.
- The new "matched without case" test turns red if either the `tolower` or the
  `aggregation <- "count"` line is dropped: two builds, two files, and `seen` of length 2 or
  `"COUNT"`.
- Offline suites on the snapshot:
  - composite: 0 failed / 3 skipped / 103 passed
  - cube: 0 / 3 / 141
  - fetch: 0 / 4 / 154
- `devtools::document()` in a copy reproduces `man/` and `NAMESPACE` byte for byte.

## Also checked, no finding

- NEWS "no existing cache key moves": true, per the table above.
- NEWS "the check runs before any network call": fetch and cube check first. Composite
  checks right after `dft_stac_config()`, which is local.
- NEWS "0.46 GiB peak": 489,013,248 B = 0.455 GiB. "9.6 min": 577.48 s.
- `planning/` and `data-raw/` are both in `.Rbuildignore`, so the review files and the
  benchmark logs do not ship.

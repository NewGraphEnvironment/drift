# Review: #92 Phase 1 (aggregation validation), round 2

## Clean

No bugs, security issues or fragile paths found in the round-1 fix.

## Checked and fine

- **Lower-casing and cache keys.** `aggregation_check()` returns `tolower(aggregation)`, which
  is the value `stac_cache_key()` (R/dft_stac_fetch.R:183), `stac_cube_cache_key()`
  (R/dft_stac_cube.R:221) and `stac_composite_cache_key()` (R/dft_stac_composite.R:189) hash.
  For every lower-case input, including all three defaults (`"first"`, `"median"`), it does
  nothing, so no existing cache entry is invalidated. The only keys that move are ones a
  caller built with a mixed-case value such as `"Median"`. Those now map to the `"median"`
  key, and gdalcubes lower-cased the value itself, so both produced identical content. The
  old entries are orphaned but never read as wrong data. The existing key tests
  (test-dft_stac_fetch.R:88, test-dft_stac_cube.R:80, test-dft_stac_composite.R:60) all use
  lower-case values and call the key functions directly, so the change does not reach them.
  `aggregation` is not written into metadata or returned attributes anywhere else, so
  lower-casing changes nothing downstream.
- **No bypass.** All three `gdalcubes::cube_view()` calls in `R/` are internal:
  `fetch_extent_to()` (dft_stac_fetch.R:608) and `stac_cube_assemble()` (dft_stac_cube.R:593).
  Their only callers are `dft_stac_fetch()` (lines 215/221), `dft_stac_cube()` (line 258)
  and `dft_stac_composite()` (line 211), and each of those reassigns `aggregation` from the
  check before building the key or calling the helper. The remaining `cube_view()` calls are
  in `data-raw/` scripts with hard-coded lower-case values, outside the package API.
- **Order.** In all three functions the check runs before any cache-directory creation,
  STAC query or cache lookup. In the composite, only `check_gdalcubes()` and the offline
  `dft_stac_config(source)` run before it.
- **Messages.** Probed: `NA` gives "Got `NA`." and `"Count"` gives "Got \"Count\", which
  gdalcubes would not honour.", with the valid set listed.
- **Tests.** Both changed test files pass when run in a copy with `NOT_CRAN=true`:
  test-dft_stac_cube.R gives 141 pass / 0 fail / 3 network skips, and
  test-dft_stac_composite.R gives 61 pass / 0 fail / 2 network skips. The round-trip test
  runs offline and pins the constant to what gdalcubes does, not to its Rd.

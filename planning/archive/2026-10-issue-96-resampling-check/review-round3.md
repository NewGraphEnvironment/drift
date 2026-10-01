# Code-check round 3: #96 (staged diff)

## Clean

No issues found.

## The mechanism behind the round-1 defect

**One token, two sources in one rendered artifact.** A check reads a string, and that string occurs in the
output for more than one reason. In round 1, `"near"` was both the fallback named in the `x` bullet and the
first member of the allowed set interpolated into the headline. So a regex that was meant to pin the bullet's
claim was satisfied by the headline instead. This is code-check.md's "An assertion that matches an interpolated
value cannot see the claim around it". The general form is a check and its target reading the same value from
different places, or reading it differently.

## Where that mechanism reaches in this diff, checked one by one

Messages were rendered through the real code under `local_reproducible_output()` in a scratch copy, and each
assertion pattern was matched against them with `gregexpr`:

| assertion | occurrences in the rendered message | where it matches |
|---|---|---|
| `"cubicspline"` (typo) | 1 | headline only, and the set is the claim it pins |
| `"bilinaer"` | 1 | the `Got` bullet only |
| `does not know as "near"` | 1 | the bullet only; the closing quote excludes the headline |
| `reads as "average"` (mean) | 1 | the alias bullet |
| `use "med"` (Median) | 1 | the alias bullet |
| `does not know` (mean, negative) | 0 | the alias bullet replaces the fallback bullet |
| `"none"` (aggregation) | 1 | the bullet; the aggregation set does not contain it |

The test-dft_stac_composite.R and call-site tests assert only `class =`, which this mechanism cannot reach.

**Non-test side: two lists that must agree, and a check and its consumer reading one value.**

- **The allowed set and what gdalcubes honours.** These are pinned by the round-trip test. On gdalcubes 0.7.5
  all 12 values come back unchanged and `bilinaer` comes back as `near`. The test hard-codes its own copy of the
  set (`expect_setequal`), so it does not read the set it is checking.
- **The aliases and the set.** The alias values (`average`, `med`) are members of the set, and the alias names
  are not. The second half matters: if `mean` or `median` were in the set, the alias bullet could never be
  reached.
- **The aliases and gdalcubes.** Probed: `mean` maps to `average` and `median` to `med`, so the bullet's claim
  is true today. No test pins this. If gdalcubes stopped honouring either alias, the hint "gdalcubes reads as
  ..." would become false. The value would still be refused, so this cannot produce a wrong cube. That makes
  it a message-accuracy gap, not a defect, and it is not reported as a finding.
- **Case.** The validator uses `tolower(x) %in% allowed` and gdalcubes lower-cases the value itself, so the two
  agree. The cache keys (`stac_cache_key`, `stac_cube_cache_key`, `stac_composite_cache_key`) hash the value as
  given, which is the accepted tradeoff and unchanged from before. The composite's `is_count` uses `tolower`
  too, so it agrees with the validator.
- **NA, length, type and whitespace.** `NA`, `NA_character_`, length 0, length 2, numeric, `NULL` and factor
  inputs are all refused before the alias lookup is reached. `" near"` is refused. That is the safe direction,
  even though gdalcubes would read it as near.
- **The alias lookup on the aggregation path.** `character(0)[name]` returns `NA`, so the fallback bullet is
  used.
- **Every `gdalcubes::cube_view()` in `R/`.** There are two: `stac_cube_assemble()` and `fetch_extent_to()`.
  Both now carry both checks, and all three exported entry points check before the cache or network. The
  composite count path passes `"first"` downstream, so the new `aggregation_check()` inside `fetch_extent_to()`
  and `stac_cube_assemble()` cannot refuse a value the entry point accepted. No source config injects a
  resampling or aggregation. No shipped caller in R/, tests/, vignettes/ or inst/ passes a value that is now
  refused; data-raw calls gdalcubes directly with `near`/`bilinear`.
- **A pre-existing wording point, not introduced here.** In the composite's aggregation message, the allowed
  list includes `"count"` and the bullet says "drift passes only these". drift does not pass `count` to
  gdalcubes; it substitutes `first`. This is cosmetic and dates from #92.

## Test run (scratch copy, NOT_CRAN=true, load_all, gdalcubes 0.7.5)

| file | failed | error | skipped | passed |
|---|---|---|---|---|
| test-dft_stac_cube.R | 0 | 0 | 3 | 209 |
| test-dft_stac_composite.R | 0 | 0 | 3 | 110 |
| test-dft_stac_fetch.R | 0 | 0 | 4 | 154 |

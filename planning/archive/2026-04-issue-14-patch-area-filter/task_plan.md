# Task: Add min_patch_area filter to dft_rast_transition()

**Issue:** drift#14
**Branch:** 14-patch-area-filter
**SRED:** Relates to NewGraphEnvironment/sred-2025-2026#16

## Goal

Add optional `min_patch_area` parameter to `dft_rast_transition()` that removes connected patches of changed pixels smaller than a threshold (in m²) before computing the summary. Filters classification noise at field-forest edges.

## Key Decisions

- Parameter name: `min_patch_area` (matches issue wording)
- Units: m² (resolution-independent)
- Default: NULL (no filtering, backward compatible)
- Position: after class filters, before summary computation
- terra::patches() for connected component labeling
- The issue also mentions `transition_class_exclude` — out of scope for this PR, note in issue comment

## Test Data

- inst/extdata/ has example_2017.tif, example_2020.tif, example_2023.tif (10m res, 314x326, UTM9)
- 2974 changed pixels between 2017-2020, cell area = 100 m²
- Will need to check patch size distribution in test data to set meaningful thresholds

## Phases

### Phase 1: Explore test data patch sizes `status: pending`
- Run terra::patches() on transition raster from test data
- Understand patch size distribution to design meaningful tests
- Document findings

### Phase 2: Implement min_patch_area in dft_rast_transition() `status: pending`
- Add parameter to function signature
- Add roxygen docs
- Insert patch filtering logic after class filtering, before summary
- Validate: negative values, non-numeric

### Phase 3: Write comprehensive tests `status: pending`
- NULL default = current behavior unchanged (existing tests still pass)
- With min_patch_area: small patches removed, large patches preserved
- Summary area totals lower with filtering than without
- Edge cases: min_patch_area = 0 (no filtering), very large (all removed)
- Interaction with from_class/to_class filters
- Validation errors for bad input

### Phase 4: /code-check + lint + devtools::check() `status: pending`
- Run /code-check on staged diff
- lintr::lint_package()
- devtools::test()
- devtools::document()

### Phase 5: Commit, push, PR `status: pending`
- Commit with Fixes #14
- PR body with SRED tag
- Tag sred-2025-2026#16

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| (none yet) | | |

# Review: #92 Phase 1 (aggregation validation), round 1

## Findings

- **[bug]** R/dft_stac_cube.R:299-303 (`.cube_view_aggregations`) — the set is the one gdalcubes
  *documents*, not the one it *honours*, and the comment says "honours". gdalcubes 0.7.5's
  C++ parser (`src/gdalcubes/src/view.cpp`, `aggregation::from_string`, unchanged since
  2024-03, and master is 0.7.5) accepts `none`, `min`, `max`, `mean`, `median`, `first`,
  **`last`**, **`count_images`**, **`count_values`**, lower-casing the input first. Anything
  else falls through to `AGG_NONE`, which is why `"count"` returned reflectance. Measured
  offline by passing each string through `gdalcubes::cube_view()` and reading back
  `$aggregation`, which comes from the C++ side:

  ```
  median -> median   Median -> median   last -> last
  count_values -> count_values   count_images -> count_images
  count -> none      sum -> none        none -> none
  ```

  This has three effects.
  1. **Regression.** `aggregation = "last"`, a real mode, worked before this commit and is
     now refused in all three functions. It is also the one most useful to
     `dft_stac_fetch()`'s categorical path, as the counterpart of its default `"first"`. The
     same goes for `"Median"` and the other case variants. That one hardly matters, but the
     test asserts the refusal as intended behaviour.
  2. **The pin test checks the proxy.** The test "the cube_view aggregation set is the one
     gdalcubes documents" (tests/testthat/test-dft_stac_cube.R, new block) parses
     `?cube_view`, so it agrees with the constant and can never see the gap above. A test of
     what gdalcubes actually does is the round-trip above. Do the check with
     `cube_view(..., aggregation = a)$aggregation != "none"`, which is offline and costs
     milliseconds.
  3. **Bearing on Phase 2.** gdalcubes already has a native per-pixel count in the view,
     `aggregation = "count_values"`, and a per-window image count, `"count_images"`. Phase 2's
     plan of `dt = "P1D"` + `reduce_time("count(...)")` may be the right design anyway,
     because `count_values` counts items, so it double-counts where MGRS tiles overlap (the
     issue's ask 4). Still, decide that on purpose rather than because the option was never
     seen. Also: if `count_*` or `last` is added to the allowed set, `count_*` must bypass
     the scale/offset in the cube and composite, or the #92 class of bug comes back as
     "scaled counts".

  Suggested fix, for the parent to decide: list the set gdalcubes honours, add `"last"` at
  least, and hold back the `count_*` pair (and `"none"`) until Phase 2 handles scale. Either
  way, correct the comment and replace or add to the Rd-parse test with the round-trip
  assertion, so the constant is pinned to behaviour.

## Checked and fine

- The guard runs in all three callers of `cube_view()` before any network, cache or
  directory side effect. In the composite it follows only `dft_stac_config(source)`, which
  is offline. `dft_stac_fetch()` has no path that avoids `cube_view()`, so the check applies
  to all of it.
- The guard's short-circuit order is safe for `NULL`, `character(0)`, `NA` and length > 1.
  The cli message interpolates in the validator's own frame. `{.obj_type_friendly}` is
  already used in the package.
- The mocked bindings `stac_cube_items` and `stac_items_paged` exist, and testthat is
  pinned >= 3.2.0. The Rd-parse regex fails loudly, not toward pass, when it does not match
  (`[[1]]` on an empty result errors). It gives the same result under the C and UTF-8
  locales.

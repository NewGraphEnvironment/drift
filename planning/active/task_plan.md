# Task: dft_stac_composite(aggregation = "count") silently returns reflectance, not a clear-observation count (#92)

## Problem

`dft_stac_composite(aggregation = "count")` returns **reflectance, not a count**. It raises no error and no warning.

`aggregation` goes straight into `gdalcubes::cube_view(aggregation = )` (`R/dft_stac_cube.R`, `stac_cube_assemble`), which supports only `"min"`, `"max"`, `"mean"`, `"median"` and `"first"` (gdalcubes 0.7.5, `?cube_view`). An unsupported value is not refused. What comes back looks like surface reflectance.

This was found by floodplains#93 phase 2. That phase measures the clear-observation windows for reference imagery exactly as drift's docs describe: `aggregation = "count"`, `bands = "red"`, with the SCL mask applied before aggregation.


Decisions taken at the gate:

- **The count is `aggregation = "count"` inside `dft_stac_composite()`**, with no new
  export. The count path hashes under **its own tag** and writes `count_<key>.tif`, so
  the 0.19.x reflectance-as-count files are orphaned rather than served, and every genuine
  composite cache stays valid.

## Phase 1: Refuse an aggregation gdalcubes does not honour
- [x] Add `aggregation_check(aggregation, allowed)`, a shared validator in
      `R/dft_stac_cube.R`. It requires a single non-NA string in `allowed` and aborts
      with a classed error that names the valid set.
- [x] `.cube_view_aggregations <- c("min", "max", "mean", "median", "first")`, one
      constant, commented with its gdalcubes `?cube_view` source.
- [x] Call the validator in `dft_stac_cube()` and `dft_stac_fetch()` (allowed = the gdalcubes
      set) and in `dft_stac_composite()` (allowed = the gdalcubes set plus `"count"`).
      Each check runs before any network call or cache lookup.
      `dft_stac_fetch()` is the third caller that shares the harness, so it gets the check too.
- [x] Tests, offline: the check fires in all three functions for `"count"` (except the
      composite), `"sum"`, `NA`, `c("median", "mean")` and a non-character value. Confirm
      the guard runs before any network call by mocking `stac_cube_items` / the STAC
      search to `stop()`. Restore the defect (skip the check) and confirm the tests go red.

## Phase 2: Clear-observation count path in `dft_stac_composite()`

Revised after the plan review (see findings.md, "Plan review" and "Count semantics").

- [x] The count path calls `stac_cube_assemble()` with `dt = "P1D"` and a day
      aggregation of `"first"`, never `"count"`. `"count"` must never reach `cube_view`,
      because it maps to `AGG_NONE` (the #92 bug). As a last guard,
      `aggregation_check()` also runs inside `stac_cube_assemble()`.
- [x] Add a helper, `composite_count_cube(cube, band_assets, bands)`, that returns
      `reduce_time(cube, paste0("count(", band_assets, ")"), names = bands)`. It
      applies no scale or offset, and `names = bands` satisfies `composite_layers_order()`.
- [x] **A pixel with zero clear days is NA, always** (`count_zero_na()`, `0 -> NA`).
      gdalcubes returns 0 or NaN for it depending on chunk layout, and chunk size
      follows `parallel`. This rule is therefore what keeps `parallel` a cost-only
      knob. It fails toward NA because a failed chunk read cannot be told apart from
      "all cloudy". An all-NA result is caught by `cube_check_nonempty()` and the year
      is dropped (`drift_empty_cube`).
- [x] **No offset split for count.** Set `is_pre` to all FALSE and skip
      `composite_offset_check()`, because `terra::cover(pre, post)` would drop the post
      side. A window that straddles 2022-01-25 is valid for a count.
- [x] Give the count its own cache family: the `"count"` tag in
      `stac_composite_cache_key()` (a family argument whose default is `"composite"`,
      so the median key is byte-identical, pinned to `03ee8ecc66b832a8`), the key
      hashing `dt = "P1D"`, and the file prefix `count_`. The count key must not
      equal the stale 0.19 key `08e0c5510e8ae297`. Write the file as INT2U with
      `OVERVIEW_RESAMPLING=NEAREST`, and use `"count"` as the label in the
      cache-read and hit messages.
- [x] Offline tests:
  - [x] Test `composite_count_cube()` on a local `create_image_collection()`
        fixture of separate B04/SCL files. Cover: a clear same-day item not blanked
        by a masked one, a count of distinct days rather than items, integer output
        with no scale, and names equal to the roles.
  - [x] Test that the result is chunking-invariant after `count_zero_na()`
        (`chunking = c(16, 64, 64)` against `c(16, 256, 256)`).
  - [x] Build `dft_stac_composite(aggregation = "count")` offline with a mocked
        `stac_cube_assemble` that captures its arguments. Assert `"first"` and `"P1D"`,
        that `is_pre` is all FALSE with no refusal for a straddling window, the
        `count_<key>.tif` name, INT2U, and that zeros become NA.
  - [x] Restore each defect and confirm the matching test goes red.
- [x] Add the `AGG_NONE` root cause and the chunk-dependent 0/NaN behaviour to
      `inst/notes/gdalcubes-pc-gotchas.md`.

## Phase 3: Docs
- [ ] Description, `@return` and the Caching section carry the count exception
      (integer counts, not reflectance; `count_<key>.tif`).
- [ ] `@param aggregation` in `dft_stac_composite()` lists the valid values and describes
      `"count"`: distinct clear days per pixel, per band, integer, no scale; the
      `cloud_cover_max` pre-filter applies, so the count is of scenes that pass it.
      `dft_stac_cube()` and `dft_stac_fetch()` list their valid values.
- [ ] `@param mask_values`: the default SCL classes include **snow**, so a spring or autumn
      "clear" count excludes snow as well as cloud (ask 4).
- [ ] Add a count example to `@examples` (inside the existing `\dontrun{}`, since it needs
      the network). Run `devtools::document()` and `pkgdown::check_pkgdown()`.

## Phase 4: Live verification and scale
- [ ] Network test (`DRIFT_TEST_NETWORK`): on the packaged AOI, the count is an integer,
      ≥ 0, and ≤ the number of distinct item dates in the window. It must not look like
      reflectance, so its maximum must be ≥ 1 and must be a whole number.
- [ ] Reproduce the issue's check on a small square: the old call gave continuous values
      around 0.03, and the new max must be ≤ the distinct dates (6 in the issue's July 2021
      square).
- [ ] Scale: count chips on BULK (about 20 points, 300 m buffers, one month) under
      `/usr/bin/time -l`, recording peak RSS and wall clock, beside #79's 100-chip median
      run (0.48 GiB, 84.1 min). The floodplain-wide read is out of scope while #88 is open.
      Numbers go in the PR body and the archive README.

## Phase 5: Release notes
- [ ] NEWS entry covering:
  - the silent reflectance, and which callers now refuse what
  - the new count and its semantics
  - the orphaned 0.19.x `composite_*.tif` files written under `"count"`, which are never
    read. They sit in the current `v2` scheme and cannot be told apart from real
    composites, so `scheme = "superseded"` does not reclaim them. State this plainly.
  - snow in the default mask

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()` clean
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push` (PR body: `Relates to NewGraphEnvironment/sred-2025-2026#16`)

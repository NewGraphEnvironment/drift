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
- [ ] Add `aggregation_check(aggregation, allowed)`, a shared validator in
      `R/dft_stac_cube.R`. It requires a single non-NA string in `allowed` and aborts
      with a classed error that names the valid set.
- [ ] `.cube_view_aggregations <- c("min", "max", "mean", "median", "first")`, one
      constant, commented with its gdalcubes `?cube_view` source.
- [ ] Call the validator in `dft_stac_cube()` and `dft_stac_fetch()` (allowed = the gdalcubes
      set) and in `dft_stac_composite()` (allowed = the gdalcubes set plus `"count"`).
      Each check runs before any network call or cache lookup.
      `dft_stac_fetch()` is the third caller that shares the harness, so it gets the check too.
- [ ] Tests, offline: the check fires in all three functions for `"count"` (except the
      composite), `"sum"`, `NA`, `c("median", "mean")` and a non-character value. Confirm
      the guard runs before any network call by mocking `stac_cube_items` / the STAC
      search to `stop()`. Restore the defect (skip the check) and confirm the tests go red.

## Phase 2: Clear-observation count path in `dft_stac_composite()`
- [ ] A count window uses `dt = "P1D"` in the `cube_view`, with a NaN-ignoring day-level
      aggregation. Same-day items from overlapping MGRS tiles therefore collapse to one
      acquisition (ask 4). The pixel function is `gdalcubes::reduce_time(cube,
      "count(<asset>)")` per band, renamed to the band role. It uses the built-in string
      reducer, not an R callback, so the gotchas-note closure trap does not apply. No scale
      or offset is applied.
- [ ] **No offset split for count.** Hand `stac_cube_assemble()` a `fetched` with `is_pre`
      all FALSE, and skip `composite_offset_check()`. Otherwise `terra::cover(pre, post)`
      would take the pre-side count wherever it is non-NA, and a count of 0 is non-NA, so
      the post side would silently never be counted. A window straddling 2022-01-25 is
      valid for a count.
- [ ] Separate cache family: pass a `"count"` tag into `stac_composite_cache_key()` (or
      add a family argument) and use the file prefix `count_`. Write with
      `datatype = "INT2U"`, so the COG stores integers.
- [ ] Empty-read guard: a window whose count is 0 everywhere is the gdalcubes failed-read
      mode wearing the face of "all cloudy". Treat it the way a composite with no clear
      pixels is treated: warn and drop the year (`drift_empty_cube`).
      `cube_check_nonempty()` cannot see it, because 0 is not NA.
- [ ] Offline tests. Cover the key: count ≠ median over the same inputs, count stays
      stable, and composite keys are unchanged, pinned against a literal pre-change key.
      Cover the file prefix. Cover the count pixel function on a local
      `create_image_collection()` fixture of dated GeoTIFFs: two same-day items count
      once, a masked day is not counted, and the result is an integer with no scale.
      Cover the straddling-window count, which is not refused.
      Restore each defect and confirm its test goes red.

## Phase 3: Docs
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
    read and can be reclaimed via `dft_cache_info()` / `dft_cache_clear()` guidance
  - snow in the default mask

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()` clean
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push` (PR body: `Relates to NewGraphEnvironment/sred-2025-2026#16`)

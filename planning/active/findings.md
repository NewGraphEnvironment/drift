# Findings — dft_stac_composite(aggregation = "count") silently returns reflectance (#92)

## Issue context

## Problem

`dft_stac_composite(aggregation = "count")` returns **reflectance, not a count**. It raises no error and no warning.

`aggregation` goes straight into `gdalcubes::cube_view(aggregation = )` (`R/dft_stac_cube.R`, `stac_cube_assemble`), which supports only `"min"`, `"max"`, `"mean"`, `"median"` and `"first"` (gdalcubes 0.7.5, `?cube_view`). An unsupported value is not refused. What comes back looks like surface reflectance.

This was found by floodplains#93 phase 2. That phase measures the clear-observation windows for reference imagery exactly as drift's docs describe: `aggregation = "count"`, `bands = "red"`, with the SCL mask applied before aggregation.

## Repro (drift 0.19.0, gdalcubes 0.7.5)

A 2 km square in the NECR floodplain, July, `res = 20`:

```r
r <- dft_stac_composite(aoi, years = 2021, months = 7, bands = "red",
                        aggregation = "count", res = 20, crs = "EPSG:32610")[[1]]
summary(terra::values(r))
#> Min 0.0077  Median 0.0331  Max 0.1835          # 2021
#> Min 0.0078  Median 0.0411  Max 0.1802  NA 307  # same call, 2023
```

The values are continuous and sit at typical vegetation red reflectance. The per-pixel maximum for the month should be at most the 17 items the query returned (6 distinct dates). The values are not integers times the band scale (1e-4) either, and 2023 carries no −0.1 offset shift. So this is not a count that was then scaled. `"count"` is simply not being honoured.

## Asks

1. **Validate `aggregation`** against what `cube_view` supports, in `dft_stac_composite()` and `dft_stac_cube()`, and refuse anything else. A wrong value should never return plausible reflectance.
2. **Provide clear-observation counts per window.** The obvious way is `dt = "P1D"` in the view, then `gdalcubes::reduce_time(cube, "count(<band>)")` over the window, with **no** scale or offset applied to the result. Either a new `aggregation = "count"` path or a separate function. The count is what a caller needs to choose composite windows, and the composite docs already suggest it.

## Also affected

floodplains#93's issue body tells callers to use `aggregation = "count"`. That call has to wait for this issue.
3. **Invalidate cached "count" composites.** The cache key hashes `aggregation`, so every `composite_<key>.tif` written by 0.19.0 with `aggregation = "count"` holds reflectance under the key a fixed count would reuse. The fix has to change the key, for example by versioning it, or those stale files will be read back as counts.
4. **Count acquisitions, not items.** Where adjacent MGRS tiles overlap, one acquisition appears as two items. The validation square above spans 3 tiles (09UYV, 10UCE, 10UDE): 17 items but only 6 distinct dates. A count should de-duplicate same-day scenes (`dt = "P1D"` does this if the day is the time step). Also note that snow classes are in the default `mask_values`, so a spring or autumn "clear" count excludes snow as well as cloud. The docs should say so.


## Plan-mode exploration (2026-09-30)

- `gdalcubes::cube_view()` (0.7.5) validates `aggregation` only as `is.character` + length 1; `?cube_view` documents "min", "max", "mean", "median", "first".
- Three callers pass it through unvalidated: `stac_cube_assemble()` (composite + cube) and `fetch_extent_to()` (fetch).
- `stac_cube_assemble()` coalesces the offset split with `terra::cover(pre, post)`. For a count that would discard the post side wherever the pre count is 0, because 0 is not NA. So count must not split.
- `cube_check_nonempty()` tests for `notNA`. An all-zero count passes it, which means a failed read looks the same as "all cloudy".
- The `reduce_time()` closure gotcha (inst/notes/gdalcubes-pc-gotchas.md) applies to R callbacks. The string reducer `"count(B04)"` is built-in C++.
- The #79 BULK floodplain-wide composite: 3 h 16 min, then #88 (the mask of the merged mosaic fails), open. 100 chips: 84.1 min, 0.48 GiB peak.

## Count semantics, measured offline (2026-09-30, gdalcubes 0.7.5)

Probe: 6 local items on a 4x4 grid, EPSG:32609, July 2021. The inputs:

- 07-03: tiles A and B, both clear
- 07-08: tile A, cloud (SCL 9)
- 07-13: tile A, clear
- 07-18: tile A cloud (SCL 8), tile B clear

`cube_view(dt = "P1D")` + `image_mask("SCL", c(3, 8, 9, 10, 11))` + `reduce_time(select_bands(cube, "B04"), "count(B04)")`:

- The count is **3** under `aggregation = "first"`, `"max"` and `"median"` alike. Same-day items collapse to one day, and a masked item does not blank a clear same-day item, because the aggregators skip NaN.
- The output band is named `B04_count`. `rename_bands(rc, B04_count = "red")` renames it.
- **A pixel with zero clear days is NaN, not 0.** That holds both when every day is masked and when the window has no images. Consequences:
  - `cube_check_nonempty()` already catches an all-empty count, so the planned extra zero-guard is unnecessary. It is dropped.
  - The docs must say that NA means no clear observation (or no coverage), not that a 0 is stored.
  - The offset split is still wrong for a count. `terra::cover(pre, post)` keeps the pre-side count wherever it is non-NA, so a pixel with 2 pre days and 3 post days would read 2.

## Plan review (Plan agent, 2026-09-30) — what was acted on

- **Blocker: `"count"` must never reach `cube_view`.** The count path uses `"first"` and P1D, and `stac_cube_assemble()` also checks.
- **The "0 everywhere = failed read" premise was wrong.** Measured (probe3, 128x128 fixture): gdalcubes gives an all-NaN chunk empty (NA) and a zero-clear pixel inside a chunk that has clear pixels elsewhere a 0. The same data gave 12,544 zeros under 256 px chunks, and 4,352 zeros plus 8,192 NaN under 64 px chunks. Chunk size follows `parallel`, so the raw output depended on a knob documented as cost-only. **Rule: 0 -> NA**, after which both chunkings are identical. NA was chosen over 0 because a failed chunk read (NaN) cannot be told apart from "all cloudy", so it fails toward NA.
- The first probe's "all masked -> NaN" case used `t0 == t1`. reduce_time passes a single time step through unchanged (reduce_time.cpp:533), so that case proved nothing. Superseded by probe3.
- Accepted: key on `dt = "P1D"`; NEAREST overviews; "count" labels; docs beyond `@param`; NEWS reclaim wording; the note in the gotchas file.
- Not acted on: the misleading "offset split" message from `stac_cube_items()` under count (cosmetic).
- `create_image_collection(one_band_per_file = FALSE)` on 2-band files segfaulted a gdalcubes worker (0.7.5). Separate files per band plus a format JSON work, so the tests use those.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Round 1: `.cube_view_aggregations` pinned to `?cube_view`, which refuses `"last"` (honoured) and case variants | Probed `cube_view()$aggregation`: honours min/max/mean/median/first/last, count_values, count_images; lower-cases; else `"none"`. Set is now the six, case-insensitive; test pins behaviour via round trip, not the Rd |

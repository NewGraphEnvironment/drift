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

## Live check (2026-09-30, Phase 2 snapshot, `data`: scratchpad `count_live*.R`)

A 2 km square at the packaged AOI's centroid, July, `bands = "red"`, `res = 20`, EPSG:32609, 10,000 cells:

| run | items | distinct dates | count min / median / max | NA | wall | peak RSS |
|---|---|---|---|---|---|---|
| 2021, `cloud_cover_max = 20` | 4 | 4 | 4 / 4 / 4 | 0 | 9.6 s | 0.30 GiB (both years) |
| 2023, `cloud_cover_max = 20` | 6 | 4 | 4 / 4 / 4 | 0 | 10.9 s | |
| 2021, `cloud_cover_max = 100` | 12 | 12 | 4 / 6 / 9 | 0 | 19.7 s | 0.36 GiB (both years) |
| 2023, `cloud_cover_max = 100` | 20 | 12 | 5 / 8 / 9 | 0 | 31.9 s | |

What the runs show:

- **Overlapping MGRS tiles collapse to one day.** 2023 returned 6 items on 4 dates and counts 4 everywhere, not 6.
- **The mask is applied per pixel.** With cloudy scenes allowed, counts vary spatially and stay at or below the distinct-date count.
- **Every value is whole and every file is INT2U**, with the scale not applied.

The issue's own call (2021 July, NECR) returned continuous values from 0.0077 to 0.18.

## Scale: BULK count chips (2026-09-30)

`data-raw/benchmark_composite_bulk.R chips-count` covers the first 20 of #79's seed-79 chips: 300 m buffers, 2023 Jul-Aug, `bands = "red"`, `aggregation = "count"`, run under `/usr/bin/time -l`.

- **Wall clock:** 577.5 s real (575.1 s in the loop), per chip median 24.7 s, max 59.6 s.
- **Peak RSS:** 489,013,248 B (0.46 GiB).
- **Output:** 3,660 cells a chip, per-chip max count 5-9, 0 NA cells.
- **Against the median chips:** the same 20 chips as median true-colour composites (#79's `chips_per_chip.csv` rows 1-20) took 1,051.6 s, median 44.4 s. #79 recorded a 0.48 GiB peak over all 100 chips.
- **Why the count is faster:** it streams one band against three, so daily time steps did not cost more at chip scale.

The floodplain-wide read is out of scope while #88 is open.

## P2 code-check termination: enumeration of the count build's wiring

Round 3 named the mechanism: a mock that receives an argument and returns a fixed result hides how the call site wires that argument. Round 1's fix (capturing `pixel_fn`) was an instance of it. Below is every argument the count build passes to its collaborators, with whether a test now observes it.

**`stac_cube_items()`**

| argument | observed? |
|---|---|
| `datetime` (`w$query`) | ✓, and a mutation fails |
| `cloud_cover_max` | ✓, and a mutation fails |
| `months` | ✓, and a mutation fails |
| `cfg`, `aoi_wgs84`, `sign_fn` | not observed |

**`stac_cube_assemble()`**

| argument | observed? |
|---|---|
| `fetched$is_pre`, `t0`, `t1`, `dt`, `aggregation`, `band_assets`, `pixel_fn`, `resampling`, `mask_values` | ✓, and each mutation fails |
| `offset`, `offset_before` | ignored by the count's `pixel_fn` by design |
| `cfg`, `aoi_target`, `target_crs`, `res`, `tile_size` | not observed |

**Key call site**

| argument | observed? |
|---|---|
| `family`, `dt_read` | not observed at the call site |

- **The unobserved `stac_cube_items()` and `stac_cube_assemble()` arguments** are shared, unchanged lines of the median path, not introduced by #92. They are accepted as pre-existing.
- **The key call site's `family` and `dt_read`:** dropping either is not a defect. The asserted `count_` prefix already separates the families, so the tag and `P1D` in the hash are defence in depth.
- **The overview resampling was the one count-specific setting left unobserved** (round 3: a fixture smaller than one COG block builds no overviews). It is now tested with a 1100 px checkerboard read at `OVERVIEW_LEVEL=0`: NEAREST gives {1, 5} and AVERAGE gives {3}.

Six round-3 mutations each turn a test red: overview AVERAGE, `cfg$mask_values`, `months = NULL`, `w$datetime` for `w$query`, constant resampling, constant cloud cover.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| P2 round 3: count overviews untested (fixture below one 512 px block); `mask_values`/`months`/query/`resampling` reached the mocks unobserved | 1100 px checkerboard overview test; count test captures and asserts the four with non-default values; each of 6 mutations red. Enumeration above ends the loop |
| P2 round 1: no test drove `dft_stac_composite()`'s count `pixel_fn` (a reflectance closure there stayed green) | The mocked assemble now captures `pixel_fn` and runs it on a fixture cube, expecting 2 clear days named `red`. The mutation turns 2 tests red |
| Round 3: the error message claimed gdalcubes "would not honour" values it does honour (none, count_*) | Reworded to state the fallback and drift's policy. Enumerated all 8 gdalcubes claims in the Phase 1 diff, all measured or test-asserted. Sibling defect on `resampling` filed as #96 |
| Round 1: `.cube_view_aggregations` pinned to `?cube_view`, which refuses `"last"` (honoured) and case variants | Probed `cube_view()$aggregation`: honours min/max/mean/median/first/last, count_values, count_images; lower-cases; else `"none"`. Set is now the six, case-insensitive; test pins behaviour via round trip, not the Rd |

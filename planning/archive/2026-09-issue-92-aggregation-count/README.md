# #92: `dft_stac_composite(aggregation = "count")` returned reflectance

## Outcome

`aggregation` passed straight into `gdalcubes::cube_view()`. That function reads any value it does not know as `"none"` and raises no error. So `"count"` came back as plausible surface reflectance.

**What was fixed.**

- `dft_stac_fetch()`, `dft_stac_cube()` and `dft_stac_composite()` now refuse any aggregation outside six values: `min`, `max`, `mean`, `median`, `first` and `last`. Each of the six was measured to survive a `cube_view()` round trip.
- The check is case-insensitive, but it hashes the value exactly as given, so no existing cache key moves.
- `dft_stac_composite(aggregation = "count")` now returns distinct clear days per pixel. It reads with `dt = "P1D"` and `"first"`, then applies `reduce_time("count()")`. It applies no scale, offset or offset split, and turns 0 into NA.
- The count has its own cache family, written as `count_<key>.tif` in INT2U with NEAREST overviews.

**What was learned.**

- `?cube_view` omits `last`, and gdalcubes also honours `count_values` and `count_images`. drift refuses those two by policy, because they count items rather than days.
- A pixel with no clear day comes back as 0 or NaN depending on chunk layout, and chunk layout follows `parallel`.
- `resampling` has the same silent fallback, to `near`. That is filed as #96.
- **Mistakes along the way.** Two were mine. The first all-masked probe used `t0 == t1`, and `reduce_time` passes a single time step through unchanged, so that probe proved nothing and was superseded. And the Phase 1 fix lower-cased `aggregation`, which would have silently re-streamed cached cubes for mixed-case callers. A later review round caught that, and it was reverted before merge.

## Measurement

**Chunk dependence (128 x 128 fixture).** At 256 px chunks the fixture gave 12,544 zeros. At 64 px chunks it gave 4,352 zeros and 8,192 NaN. After mapping 0 to NA, both chunkings are identical. This is why a pixel with no clear day is NA, never 0.

**Live, on a 2 km square in July** (`res = 20`, 10,000 cells):

| year | `cloud_cover_max` | items | distinct dates | counts |
|---|---|---|---|---|
| 2023 | 20 | 6 | 4 | 4 everywhere |
| 2023 | 100 | 20 | 12 | 5-9 |
| 2021 | 100 | 12 | 12 | 4-9 |

- No NA cells in any run.
- Peak RSS 0.30-0.36 GiB.
- Overlapping MGRS tiles de-duplicate on real data: the 6 items above count as 4 days.

**BULK, 20 count chips** (300 m buffers, 2023 Jul-Aug, `bands = "red"`):

| run | total | median per chip | peak |
|---|---|---|---|
| count | 577.5 s | 24.7 s | 0.46 GiB (kernel peak) |
| same 20 chips as median composites (#79) | 1,051.6 s | 44.4 s | not measured for these 20 |

- Each count chip's maximum was 5-9, with no NA cells.
- The count reads one band where the median reads three. That is the likely reason it is cheaper, but the two runs were not controlled against each other.

**Review cost and yield.** One plan review and nine `/code-check` rounds. Every round that found something produced a mutation-verified fix. Rounds that found defects inside the previous fix were ended by enumeration, not by a reviewer calling the work finished:

- the count build's collaborator arguments;
- every key flow, checked against v0.19.2.

## Evidence

- `data-raw/logs/benchmark_composite_bulk/*count*`: the BULK count chips. `time_chips_count.txt` holds the `/usr/bin/time -l` block.
- `data-raw/benchmark_composite_bulk.R`, stage `chips-count`.
- `inst/notes/gdalcubes-pc-gotchas.md`, section "Silent fallbacks and counting clear observations (#92)".
- `review-*.md` in this directory: each round's findings.

Closed by: PR (link added on open)

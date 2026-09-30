# Code-check review: #92 Phase 2, round 3

Snapshot: `scratchpad/p2snap`, copied to `scratchpad/p2r3/base` and mutated only in `scratchpad/p2r3/mut_*`. Baseline for `test-dft_stac_composite.R`: `[ FAIL 0 | SKIP 2 | PASS 92 ]`. No other test file calls `dft_stac_composite()` or `stac_composite_cache_key()`, so this file is the whole guard. Harness: `scratchpad/p2r3/run_mut.sh`.

## Mechanism

Round 1's defect was not specific to `...`. **A mock that receives an argument and returns a fixed result makes the call site's wiring of that argument unobservable.** Passing the argument through `...` and naming it as a formal the mock never reads are the same hole. The only wiring a test asserts is what the mock copies into `seen`, so the assertions cover exactly the arguments the author already suspected. Round 1 was that selection missing `pixel_fn`.

The same mechanism shows up at a second seam. `stac_composite_cache_key()` is not mocked in the count tests, but its call-site output is checked only by the filename regex `^count_[0-9a-f]{16}\.tif$`. So every argument the call site feeds it is unobserved too, the same way.

A third, adjacent shape is a fixture that cannot reach the failure mode. The mocked stack is 63 x 65 px, and a COG with `BLOCKSIZE=512` builds no overviews at that size. So the overview-resampling argument is written but never exercised.

## Where it reaches in this diff's tests

| seam | args the mock ignores | wiring asserted elsewhere? |
|---|---|---|
| `stac_cube_items` (`function(...)` in every mock: l.169, 272, 302, 429, 490, 504) | cfg, aoi_wgs84, **w$query**, cloud_cover_max, **months**, sign_fn | no. The only check is `composite_window()$query` in isolation, and the network tests are skipped by default |
| `stac_cube_assemble`, count mock (l.432) | named but not read: cfg, aoi_target, target_crs, res, **resampling**, **mask_values**, offset_before. Through `...`: **tile_size** | no. The composite build mock (l.273) and the empty-count mock (l.505) are `function(...)` and read nothing |
| `stac_cube_assemble`, count mock | captured: is_pre, dt, aggregation, t0, t1, band_assets, pixel_fn, offset | yes. Every count-specific value is asserted (offset only feeds pixel_fn, which ignores it for a count) |
| `stac_composite_cache_key` call site (l.200-205) | all args, including **dt_read** and **family** | only the `count_` prefix and 16-hex shape. The `ckey()` tests call the function directly, not through the call site |
| COG write (l.258-263) | `OVERVIEW_RESAMPLING` | no. The fixture is too small for overviews |

## Mutations run (each on a fresh copy, each green = `[ FAIL 0 | SKIP 2 | PASS 92 ]`)

| mutation (R/dft_stac_composite.R) | result | real defect? |
|---|---|---|
| l.262 count overviews `NEAREST` -> `AVERAGE` | green | yes (Finding 1) |
| l.220 `w$query` -> `w$datetime` | green | yes, pre-existing (Finding 2) |
| l.221 `months` -> `NULL` | green | yes, pre-existing (Finding 2) |
| l.239 `mask_values = mask_values` -> `cfg$mask_values` | green | yes, pre-existing (Finding 2) |
| l.238 `resampling = resampling` -> `"near"` | green | yes, pre-existing (Finding 2) |
| l.241 drop `tile_size = tile_size` | green | cost only: an untiled read with identical values |
| l.204 drop `family = family` from the key call | green | no, see Note |
| l.201 `dt_read` -> `w$dt` in the key call | green | no, see Note |

## Findings

- **[fragile]** R/dft_stac_composite.R:262. The count's `OVERVIEW_RESAMPLING=NEAREST` is new in this diff and nothing asserts it. Reverting it to `AVERAGE` stays green, because the mocked 63 x 65 stack is below the 512 px block size and GDAL builds no overviews. This is a fixture that cannot reach the failure mode, not a mock swallowing an argument. Any AOI wider than 512 px at `res` would get averaged INT2U overviews: titiler and QGIS show a rounded mean at low zoom, which is not a count, and the code comment on l.254-255 says exactly that. For the guard to fire, the mocked stack has to exceed 512 px on one side, for example 1024 x 16 at `resolution = 10` over a matching extent. Then read an overview back (`gdalinfo` "Overviews:" plus a value check, or `terra::rast(f, lyrs=…)` of the overview). A cheaper option is to assert the `OVERVIEW_RESAMPLING` metadata that `gdalinfo` reports in the COG's IMAGE_STRUCTURE.

- **[fragile, pre-existing, not introduced by this diff]** R/dft_stac_composite.R:220-221 and 238-239. Four user-facing arguments reach the two stubbed seams and are never observed there. Each wiring defect below stays green, and each changes pixels, not just cost:
  - `w$query` -> `w$datetime` brings back #83 (a date-only end bound drops the last day's scenes). A count silently loses one clear day.
  - `months` -> `NULL` removes the month filter (`stac_cube_items()` filters only when `!is.null(months)`). `months = c(6, 8)` then counts or medians July scenes as well.
  - `mask_values` -> `cfg$mask_values` ignores the user's mask. For a count this argument is the definition of "clear". The cache key still hashes the user's value, so the file is labelled with a mask it was not built with.
  - `resampling` -> a constant has the same shape: it is keyed on the user's value and read with another.

  The count mock already names `mask_values` and `resampling` as formals and a `...` that holds `tile_size`. Copying them into `seen`, and giving `stac_cube_items` named formals that capture `datetime` and `months`, would make all four red. Before this diff the composite build test mock was `function(...)`, so this gap is older than #92. It is listed because the new count test repeats the same hole on the path whose meaning depends most on `mask_values`.

## Note (not a finding): correction to the accepted list

"Key without family" is red only when the mutation is inside `stac_composite_cache_key()`, where `ckey(family = "count") != ckey()` catches it. At the call site (l.204), dropping `family = family` stays green, and so does keying on `w$dt` instead of `dt_read` (l.201). Neither is a real defect. The asserted `count_` file prefix already separates the count files from every `composite_*.tif`, including the 0.19.x reflectance files written under `aggregation = "count"`. That separation holds even with both mutations applied together, which reproduces the stale hash `08e0c5510e8ae297` but under a `count_` name. The tag and `P1D` in the hash are defence in depth, not the separator. The docstring on l.490-494 ("the tag, and the `P1D` read step the caller passes, both change the hash") describes the function correctly, but nothing pins the caller to it.

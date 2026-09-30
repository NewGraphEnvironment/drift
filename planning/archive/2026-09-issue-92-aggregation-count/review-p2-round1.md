# Code-check review: #92 Phase 2, round 1

Snapshot: `scratchpad/p2snap`, gdalcubes 0.7.5. The composite test file passes (89 pass, 2 network skips).

## Findings

- **[fragile]** tests/testthat/test-dft_stac_composite.R, test "dft_stac_composite(aggregation = 'count') reads daily, unsplit, and caches integers" (the `stac_cube_assemble` mock). Nothing tests that `dft_stac_composite()` connects the count path to `composite_count_cube()`. The mock takes `pixel_fn` through `...` and never calls it. The two fixture tests call `drift:::composite_count_cube()` directly and do not go through `dft_stac_composite()`. **Mutation run on a copy (`scratchpad/p2mut`):** I changed the count branch of `pixel_fn` (R/dft_stac_composite.R:186) to the reflectance `apply_pixel(scale_token(...))` closure. The suite stayed green, `[ FAIL 0 | SKIP 2 | PASS 89 ]`. So if `pixel_fn` were inverted or dropped, the count path would return scaled reflectance read at P1D with no `reduce_time`, which is several layers. The tests would stay green for that part. The `composite_layers_order()` layer-count abort would still fire at run time, but only against a live STAC. This is the one wiring defect of the #92 class that the 7 accepted mutations do not cover. A fix that can fail: in the mock, capture `pixel_fn`, and assert that `seen$pixel_fn` applied to a `count_fixture()` cube returns the day counts. Or, more cheaply, assert that it returns a `reduce_time` cube. For example, `inherits(seen$pixel_fn(cube, 0), "reduce_time_cube")`.

## Probed and clean

- **NA round trip through INT2U COG:** a 600x600x3 stack of {0, NaN, NA, 1, 7, 40} went through `count_zero_na()`, then `writeRaster(COG, INT2U, NEAREST)`. The NoData value is 65535, and every 0, NaN and NA read back as NA. There was no 0 and no 65535, and the NA mask matched the pre-write mask exactly. `cache_invalid_reason()` gives NA, and `stac_cube_cache_read()` returns the raster and not NULL. `gdalinfo` shows UInt16 and NEAREST overviews.
- **Count across time chunks:** I made the clear days fall only in the later of the 16-day time chunks, with the whole grid cloudy in the first. At chunkings `c(16,256,256)`, `c(16,64,64)`, `c(1,64,64)`, `c(4,128,128)` and `c(31,64,64)`, the counts were identical and correct (1 for 12,544 pixels, 2 for 3,840).
- **Order within a day:** I swapped which same-day item is cloudy, so the cloudy one sorts first. `first`, `last`, `max` and `median` all still count the day. The test fixture's ordering is therefore not load-bearing.
- **Window edges:** items on 07-01 and 07-31 are both counted with `t1 = "2021-07-31"` and `dt = "P1D"`.
- **Multi-band naming:** `composite_count_cube(cube, c("B04","SCL"), c("red","blue"))`, written to NetCDF, is read by terra as `blue, red` (alphabetical). `composite_layers_order()` restores `red, blue` by name.
- **Can "count" reach cube_view:** no. `dft_stac_cube()` and `dft_stac_fetch()` keep the default allowed set. The composite passes `"first"`, and `stac_cube_assemble()` rejects `"count"` with the default set.
- **clip / tile_size ordering:** `count_zero_na()` runs after `mosaic_stacks()`, which receives the whole assembled stack, and before `stac_cube_clip()`. Tiles do not overlap, and both orderings give the same NA set. `tile_size` is in the count key.
- **Cache family:** no other code matches on the `composite_` or `cube_` prefix, so `count_` breaks no cache consumer. The default family keeps the literal `"composite"` first element.

## Note (not a finding)

`count_zero_na()` adds one full-grid `terra::classify()` intermediate, in memory, next to the existing in-memory `stac_cube_clip()`. The composite is sized for AOIs and chips, so this is only relevant if a count is run at BULK scale.

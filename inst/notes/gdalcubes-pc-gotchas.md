# gdalcubes + Planetary Computer Sentinel-2 gotchas

Non-obvious gdalcubes 0.7.3 + Microsoft Planetary Computer Sentinel-2 gotchas hit
building `dft_stac_cube()` / `dft_rast_break()` / `dft_rast_trend()` (#30). All
verified by running code on gdalcubes 0.7.3 / rstac 1.0.1 / terra 1.9.11 /
bfast 1.7.2.

- **`gdalcubes::filter_geom()` segfaults / returns an all-NA cube** on this build
  (crashes `gc_exec_worker`, `address 0x120`). Do NOT clip to an AOI polygon
  inside the cube pipeline. Use the AOI bbox in `cube_view(extent=)` and
  `terra::mask()` afterward, as `dft_stac_fetch()` does. **Resolved (#32):**
  `dft_stac_cube(clip = TRUE)` (the default) masks the assembled terra stack to
  the AOI polygon client-side (helper `stac_cube_clip()` = `terra::mask(stk,
  terra::vect(aoi))`), so the cube is polygon-tight and
  `dft_rast_break()`/`dft_rast_trend()` skip out-of-AOI pixels via their
  `rowSums(!is.na) >= min_obs` gate. **Residual:** this clips the *output* only —
  `cube_view(extent = bbox)` still streams the full bbox of COGs, so fetch time is
  unchanged; pushing the AOI into the read would need a working `filter_geom` or
  server-side windowing. `clip = FALSE` keeps the full bbox.
- **Download-side workaround without `filter_geom`: tile the `cube_view` (#36).**
  Since `filter_geom` can't push the AOI into the read, the categorical
  `dft_stac_fetch(tile_size = <metres>)` splits the AOI bbox into a `res`-aligned
  grid and streams only tiles that intersect the AOI polygon (skipping the empty
  bbox corners), then mosaics with `terra::merge()`. For a thin, diagonal
  floodplain corridor (measured ~10% of the bbox inside the polygon) this fetches
  near the AOI footprint instead of the full bbox. Tiles must be snapped to a
  multiple of `res` and anchored at the bbox lower-left so their pixel grids are
  co-lattice — otherwise the merge seams. The tiled mosaic is written with
  `terra::writeRaster()` to a **`.tif`** (terra's NetCDF *write* is fragile — see
  the round-trip bullet below), so tiled and untiled fetches cache under different
  extensions and keys. The same read residual on the continuous `dft_stac_cube()`
  path (its `cube_view` still streams the full bbox) is tracked as **#38**.
- **`reduce_time()` R-callback runs in spawned worker processes at EVERY parallel
  setting** (incl. `parallel = 1`). A closure over enclosing locals fails there
  (`object 'band' not found`). Options: build a self-contained callback (inline
  literals via `substitute()`, `load_pkgs = "bfast"`), OR — cleaner — skip the
  gdalcubes reduce entirely and reduce a terra stack with `parallel::mclapply`
  (fork inherits namespace + closures; 102k px in ~8 s). drift uses the terra
  route.
- **gdalcubes CANNOT read a terra-written NetCDF** ("Failed to identify x,y,t
  dimensions"). So you can't coalesce/modify cubes in terra and hand them back to
  gdalcubes. drift's fix: `dft_stac_cube()` returns a terra `SpatRaster` stack
  (materialized GeoTIFF, `terra::time` set), not a gdalcubes cube.
- **Planetary Computer `sentinel-2-l2a` +1000 DN reflectance offset flips at
  2022-01-25** (processing baseline 04.00). Pre-boundary scenes have offset 0,
  post have -0.1. PC ships NO per-item offset metadata and `apply_pixel` can't
  express a per-date offset. A uniform offset produces a FALSE whole-AOI index
  step at 2022 (kNDVI's `tanh` hides it as bounded 0-1, so the cube looks valid;
  ~99% of pixels "break" at the boundary). Fix: split the item list at the
  boundary, correct each side, coalesce with `terra::cover`. Element84
  `sentinel-2-c1-l2a` is uniformly harmonized but has a 2022 data hole for tile
  09UXA.
- **`rstac::get_request()` truncates at 250 items** on PC (page cap) and
  `items_matched()` is NULL, so you can't detect truncation —
  `post_request() |> items_fetch()` is mandatory for multi-year monthly queries.
  `ext_filter(`eo:cloud_cover` <= {{var}})` needs `{{ }}` for a runtime variable.
- **GDAL /vsicurl tuning** (`GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR`,
  `VSI_CACHE=TRUE`, HTTP multiplex) helps modestly (~38→28 s/month); the real
  speed/quality win is fetching fewer better months (growing-season `months`
  filter). A 100-ha reach, 4 yr monthly = ~25-30 min fetch (COG-stream bound);
  the bfast reduce is seconds.

See `planning/archive/2026-07-issue-30-index-trajectory/findings.md` and
`planning/archive/2026-07-issue-30-vignette-qa-map/findings.md` for the full
empirical journey.

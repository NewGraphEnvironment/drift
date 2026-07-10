# Changelog

## drift 0.6.0

- [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  gains `tile_size` (default `NULL`), an opt-in that bounds the STAC
  download to the AOI footprint
  ([\#36](https://github.com/NewGraphEnvironment/drift/issues/36)). By
  default a single cube is streamed over the whole AOI bounding box, so
  for a thin, diagonal floodplain corridor (measured ~10% of the bbox
  inside the polygon) roughly 10× more pixels are downloaded than the
  AOI needs. When `tile_size` (CRS units — metres for the default UTM
  CRS) is set, the bbox is split into a `res`-aligned grid and only
  tiles that intersect the AOI polygon are streamed, then mosaicked with
  [`terra::merge()`](https://rspatial.github.io/terra/reference/merge.html)
  — so a corridor fetches close to its footprint. Smaller tiles waste
  less bbox but cost more per-tile round trips (no auto-tuning). This is
  the `filter_geom`-independent path (the polygon-clip that would do
  this in the cube pipeline segfaults on the pinned gdalcubes build).
  Tiled fetches cache a terra GeoTIFF (`.tif`) rather than a gdalcubes
  NetCDF (`.nc`) and key distinctly, so existing untiled caches are
  untouched; `tile_size = NULL` is byte-for-byte the previous behavior.
  The same read residual on the continuous
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  path is tracked as
  [\#38](https://github.com/NewGraphEnvironment/drift/issues/38).

## drift 0.5.0

- [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  gains `clip` (default `TRUE`), restoring AOI-polygon-tight output
  ([\#32](https://github.com/NewGraphEnvironment/drift/issues/32)). The
  assembled index stack is masked to the AOI polygon with
  [`terra::mask()`](https://rspatial.github.io/terra/reference/mask.html)
  — client-side, because
  [`gdalcubes::filter_geom()`](https://rdrr.io/pkg/gdalcubes/man/filter_geom.html)
  segfaults / returns an all-NA cube on the pinned build — so cells
  outside the polygon are `NA` on every layer. The reduced raster from
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)/[`dft_rast_trend()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_trend.md)
  is now polygon-tight with no caller-side mask, and those reducers skip
  out-of-AOI pixels via their valid-observation gate. `clip = FALSE`
  keeps the full bounding box. This is an output change for callers that
  relied on the bounding-box extent, and the clip is folded into the
  cube cache key, so existing cached cubes rebuild once. Note the clip
  affects the *output* only — the full bbox of COGs is still streamed
  either way (the AOI cannot be pushed into the read on the pinned
  gdalcubes build).

## drift 0.4.0

- Categorical land-cover change detection no longer exhausts memory on
  large-floodplain AOIs
  ([\#34](https://github.com/NewGraphEnvironment/drift/issues/34),
  [\#28](https://github.com/NewGraphEnvironment/drift/issues/28)).
  [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  was rewritten to stream entirely through `terra` — transitions are
  encoded and filtered with raster arithmetic,
  [`terra::subst()`](https://rspatial.github.io/terra/reference/subst.html),
  [`patches()`](https://rspatial.github.io/terra/reference/patches.html),
  and a single
  [`terra::freq()`](https://rspatial.github.io/terra/reference/freq.html),
  with no
  [`terra::values()`](https://rspatial.github.io/terra/reference/values.html)
  pull and no full-grid R vectors — so peak memory scales with the
  number of distinct transitions and patches, not the grid size
  (producer-only peak at 16M cells dropped from 2.66 GB to 1.63 GB).
  Output is byte-identical to the previous version, verified by a golden
  snapshot across the full parameter matrix.
- [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  gains `changes_only` (default `FALSE`): when `TRUE`, stable
  (`from == to`) transitions are dropped at the raster level before
  polygonizing, so
  [`terra::as.polygons()`](https://rspatial.github.io/terra/reference/as.polygons.html)
  only builds geometry for actual change patches. On a fragmented
  floodplain — where the stable mosaic is most of the grid and
  polygonization dominates memory — this roughly halves peak use (a
  9M-cell, 415k-patch benchmark went from 3.83 GB to 1.71 GB). The
  result equals the default output filtered to change patches. When
  `patch_area_min` is set, small patches are also dropped before
  polygonizing, with identical output.
- `patch_id` in
  [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  is numbered over the surviving patches when filtering drops any, and
  an empty result now carries the zone column so per-zone results bind
  cleanly.

## drift 0.3.0

- Continuous index-trajectory change detection for floodplain reaches
  ([\#30](https://github.com/NewGraphEnvironment/drift/issues/30)). A
  new fetch-and-reduce pipeline complements the categorical
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  path.
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  builds a cloud-masked monthly spectral-index stack from Sentinel-2
  (via a new `"sentinel-2-l2a"` source);
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
  reduces it per pixel with
  [`bfast::bfastmonitor()`](https://rdrr.io/pkg/bfast/man/bfastmonitor.html)
  into a two-band raster of *abrupt* break date and magnitude; and
  [`dft_rast_trend()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_trend.md)
  reduces it to a per-pixel *gradual* trend — a robust Theil-Sen slope
  (index change per year) with Mann-Kendall significance — for
  degradation/recovery monitoring the annual labels cannot show.
  Together they let a continuous trajectory validate categorical
  land-cover transitions (confirming which mapped losses carry a real
  spectral decline) and detect gradual change. See the “Trajectories as
  a Check on Land-Cover Change” vignette.
- [`dft_index_expr()`](https://newgraphenvironment.github.io/drift/reference/dft_index_expr.md)
  and
  [`dft_index_table()`](https://newgraphenvironment.github.io/drift/reference/dft_index_table.md)
  add a table-driven spectral-index registry (NDVI, kNDVI, NDMI) whose
  formulas are written over band *roles*, so one index resolves against
  any reflectance source; the reflectance scale/offset is folded into
  each expression.
- Sentinel-2 handling is correctness-focused:
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  masks cloud/shadow/cirrus/snow, restricts to caller-chosen calendar
  `months` (e.g. the growing season) to sharpen the signal and cut
  scenes streamed, and — because the +1000 DN reflectance offset only
  applies from processing baseline 04.00 (2022-01-25) — splits items at
  that boundary and corrects each side, so a multi-year series carries
  no artificial index step at 2022.
- [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  gains a role-based schema for reflectance cube sources (band roles,
  mask classes, scale/offset, offset boundary), leaving the categorical
  `io-lulc`/`esa-worldcover` sources unchanged. `bfast` added to
  Suggests.
- Known limitation tracked as a follow-up: the cube spans the AOI
  bounding box rather than the polygon (a gdalcubes `filter_geom`
  limitation,
  [\#32](https://github.com/NewGraphEnvironment/drift/issues/32));
  labelling breaks with from/to land-cover classes is
  [\#31](https://github.com/NewGraphEnvironment/drift/issues/31).

## drift 0.2.4

- [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  no longer exhausts memory on large-extent rasters
  ([\#27](https://github.com/NewGraphEnvironment/drift/issues/27)). The
  per-class loop allocated full-grid vectors per class and per patch —
  ncell × n_patches churn that OOM-killed a 102.6M-cell, 56-class
  floodplain. Replaced by a single `terra::patches(values = TRUE)` pass
  plus a sparse patch-to-label map. Output is identical (verified
  patch-by-patch against the old implementation); only `patch_id`
  numbering / row order changes, to raster scan order. Benchmark at 24M
  cells: 1.9 s for a 4,799-patch raster; the old code took 122 s on a
  milder 1,232-patch raster of the same size.
- terra dependency floored at `>= 1.8-10`: earlier versions had an
  edge-wraparound bug in `patches(values = TRUE)` that silently merged
  patches touching opposite raster edges.

## drift 0.2.3

- Fix silent cross-AOI cache collision in
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  ([\#25](https://github.com/NewGraphEnvironment/drift/issues/25)).
  Cache files were keyed by source + year only, so fetching a second AOI
  with the same source/year silently returned the first AOI’s raster
  masked to the second AOI’s extent. Cache filenames now include a hash
  of the AOI geometry and all fetch-affecting parameters (`res`, `crs`,
  `dt`, `aggregation`, `resampling`, `stac_url`, `collection`, `asset`).
  Existing caches re-fetch on first use after upgrading;
  [`dft_cache_clear()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_clear.md)
  reclaims the orphaned old-format files.
- `force = TRUE` now overwrites the cached file instead of erroring with
  “File already exists”
  ([\#25](https://github.com/NewGraphEnvironment/drift/issues/25)).

## drift 0.2.2

- Startup quote pool expanded to 113. Adds 52 domain-expert quotes from
  11 voices across floodplain/river process (David Montgomery, Ellen
  Wohl), Indigenous stewardship (Robin Wall Kimmerer, Kyle Whyte, Nancy
  Turner, Jeannette Armstrong), ecosystem valuation (Kai Chan), Canadian
  public voices (David Suzuki, Wade Davis), and legacy conservation
  (Aldo Leopold, Wendell Berry).
- Tim Beechie was on the target list but yielded zero — no public
  interview / podcast / documentary footprint. Process-paper voice only.
- Same rigor as v0.2.1: parallel research agents, independent fact-check
  pass (3 dropped for misattribution or text drift, 2 fixed from
  fact-check flags).

## drift 0.2.1

- Startup quote ritual:
  [`library(drift)`](https://github.com/NewGraphEnvironment/drift)
  prints a random fact-checked quote from 15 hip-hop artists on attach.
  Italic quote, grey attribution, clickable blue `source` hyperlink to
  the primary-source interview. Suppress via
  `options(drift.quote_show_source = FALSE)`.
- Curated via the soul `/quotes-enable` skill using multi-agent
  research + independent primary-source fact-check. 61 entries. See
  `data-raw/quotes_build.R` for full provenance.
- `cli` added to Imports for OSC 8 hyperlinks and styling in `R/zzz.R`.

## drift 0.2.0

- [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  — add `patch_area_min` parameter to filter small connected patches of
  changed pixels; return `$removed` raster for visual QA of filtered
  patches; add `from_class`/`to_class` filters
- [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  — vectorize transition raster into sf polygons with per-patch area,
  transition labels, and optional zone attribution
- [`dft_rast_consensus()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_consensus.md)
  — per-pixel mode across classified rasters for temporal noise
  filtering; optional confidence layer
- [`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md)
  — new `transition` parameter overlays transition layers as checkboxes;
  Google Satellite and Esri Satellite basemaps; custom tile URL support
- `dft_check_crs()` — internal helper that errors on geographic CRS
  input; wired into
  [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  and
  [`dft_rast_summarize()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_summarize.md)
- Vignette: transition detection, tree loss filtering, patch area
  filtering with comparison table, interactive map with transition
  overlays

## drift 0.1.0

Initial public release.

- [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  — fetch classified rasters from STAC catalogs via gdalcubes
- [`dft_rast_classify()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_classify.md)
  — apply class labels, colors, and optional remap to SpatRasters
- [`dft_rast_summarize()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_summarize.md)
  — compute area by class and year with unit conversion
- [`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md)
  — interactive leaflet map with layer toggle, legend, fullscreen, and
  titiler COG support
- [`dft_class_table()`](https://newgraphenvironment.github.io/drift/reference/dft_class_table.md)
  — shipped class tables for IO LULC and ESA WorldCover
- [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  — STAC endpoint registry
- Cache management:
  [`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md),
  [`dft_cache_info()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_info.md),
  [`dft_cache_clear()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_clear.md)
- Vignette: Neexdzii Kwa floodplain land cover change 2017-2023

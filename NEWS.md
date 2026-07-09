# drift 0.3.0

- Continuous index-trajectory change detection for floodplain reaches (#30). A new fetch-and-reduce pipeline complements the categorical `dft_stac_fetch()` path. `dft_stac_cube()` builds a cloud-masked monthly spectral-index stack from Sentinel-2 (via a new `"sentinel-2-l2a"` source), and `dft_rast_break()` reduces it per pixel with `bfast::bfastmonitor()` into a two-band raster of break date (decimal year) and magnitude (negative = index drop, e.g. scour or vegetation loss). Where categorical differencing compares two land-cover labels, this detects *when* a pixel's spectral history breaks and by how much. See the "Continuous Index-Trajectory Change Detection" vignette.
- `dft_index_expr()` and `dft_index_table()` add a table-driven spectral-index registry (NDVI, kNDVI, NDMI) whose formulas are written over band *roles*, so one index resolves against any reflectance source; the reflectance scale/offset is folded into each expression.
- Sentinel-2 handling is correctness-focused: `dft_stac_cube()` masks cloud/shadow/cirrus/snow, restricts to caller-chosen calendar `months` (e.g. the growing season) to sharpen the signal and cut scenes streamed, and — because the +1000 DN reflectance offset only applies from processing baseline 04.00 (2022-01-25) — splits items at that boundary and corrects each side, so a multi-year series carries no artificial index step at 2022.
- `dft_stac_config()` gains a role-based schema for reflectance cube sources (band roles, mask classes, scale/offset, offset boundary), leaving the categorical `io-lulc`/`esa-worldcover` sources unchanged. `bfast` added to Suggests.
- Known limitation tracked as a follow-up: the cube spans the AOI bounding box rather than the polygon (a gdalcubes `filter_geom` limitation, #32); labelling breaks with from/to land-cover classes is #31.

# drift 0.2.4

- `dft_transition_vectors()` no longer exhausts memory on large-extent rasters (#27). The per-class loop allocated full-grid vectors per class and per patch — ncell × n_patches churn that OOM-killed a 102.6M-cell, 56-class floodplain. Replaced by a single `terra::patches(values = TRUE)` pass plus a sparse patch-to-label map. Output is identical (verified patch-by-patch against the old implementation); only `patch_id` numbering / row order changes, to raster scan order. Benchmark at 24M cells: 1.9 s for a 4,799-patch raster; the old code took 122 s on a milder 1,232-patch raster of the same size.
- terra dependency floored at `>= 1.8-10`: earlier versions had an edge-wraparound bug in `patches(values = TRUE)` that silently merged patches touching opposite raster edges.

# drift 0.2.3

- Fix silent cross-AOI cache collision in `dft_stac_fetch()` (#25). Cache files were keyed by source + year only, so fetching a second AOI with the same source/year silently returned the first AOI's raster masked to the second AOI's extent. Cache filenames now include a hash of the AOI geometry and all fetch-affecting parameters (`res`, `crs`, `dt`, `aggregation`, `resampling`, `stac_url`, `collection`, `asset`). Existing caches re-fetch on first use after upgrading; `dft_cache_clear()` reclaims the orphaned old-format files.
- `force = TRUE` now overwrites the cached file instead of erroring with "File already exists" (#25).

# drift 0.2.2

- Startup quote pool expanded to 113. Adds 52 domain-expert quotes from 11 voices across floodplain/river process (David Montgomery, Ellen Wohl), Indigenous stewardship (Robin Wall Kimmerer, Kyle Whyte, Nancy Turner, Jeannette Armstrong), ecosystem valuation (Kai Chan), Canadian public voices (David Suzuki, Wade Davis), and legacy conservation (Aldo Leopold, Wendell Berry).
- Tim Beechie was on the target list but yielded zero — no public interview / podcast / documentary footprint. Process-paper voice only.
- Same rigor as v0.2.1: parallel research agents, independent fact-check pass (3 dropped for misattribution or text drift, 2 fixed from fact-check flags).

# drift 0.2.1

- Startup quote ritual: `library(drift)` prints a random fact-checked quote from 15 hip-hop artists on attach. Italic quote, grey attribution, clickable blue `source` hyperlink to the primary-source interview. Suppress via `options(drift.quote_show_source = FALSE)`.
- Curated via the soul `/quotes-enable` skill using multi-agent research + independent primary-source fact-check. 61 entries. See `data-raw/quotes_build.R` for full provenance.
- `cli` added to Imports for OSC 8 hyperlinks and styling in `R/zzz.R`.

# drift 0.2.0

- `dft_rast_transition()` — add `patch_area_min` parameter to filter small connected patches of changed pixels; return `$removed` raster for visual QA of filtered patches; add `from_class`/`to_class` filters
- `dft_transition_vectors()` — vectorize transition raster into sf polygons with per-patch area, transition labels, and optional zone attribution
- `dft_rast_consensus()` — per-pixel mode across classified rasters for temporal noise filtering; optional confidence layer
- `dft_map_interactive()` — new `transition` parameter overlays transition layers as checkboxes; Google Satellite and Esri Satellite basemaps; custom tile URL support
- `dft_check_crs()` — internal helper that errors on geographic CRS input; wired into `dft_rast_transition()` and `dft_rast_summarize()`
- Vignette: transition detection, tree loss filtering, patch area filtering with comparison table, interactive map with transition overlays

# drift 0.1.0

Initial public release.

- `dft_stac_fetch()` — fetch classified rasters from STAC catalogs via gdalcubes
- `dft_rast_classify()` — apply class labels, colors, and optional remap to SpatRasters
- `dft_rast_summarize()` — compute area by class and year with unit conversion
- `dft_map_interactive()` — interactive leaflet map with layer toggle, legend, fullscreen, and titiler COG support
- `dft_class_table()` — shipped class tables for IO LULC and ESA WorldCover
- `dft_stac_config()` — STAC endpoint registry
- Cache management: `dft_cache_path()`, `dft_cache_info()`, `dft_cache_clear()`
- Vignette: Neexdzii Kwa floodplain land cover change 2017-2023

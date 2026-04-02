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

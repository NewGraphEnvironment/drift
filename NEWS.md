# drift (development)

- `dft_rast_transition()` — cell-by-cell land cover transition detection with from/to class filters
- `dft_map_interactive()` — new `transition` parameter overlays transition layers as checkboxes; add Google Satellite and Esri Satellite basemaps; support custom tile URLs
- `dft_rast_consensus()` — per-pixel mode across classified rasters for temporal noise filtering; optional confidence layer
- Vignette: transition detection, tree loss filtering, single combined interactive map

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

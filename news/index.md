# Changelog

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

# Review round 1: drift #79 (dft_stac_composite, rgb in dft_map_interactive, cube refactor)

## Findings

- **[severity: bug]** R/dft_stac_composite.R:220-227 (with R/dft_stac_fetch.R:685-686): every composite cache write leaves an orphaned `.aux.json` sidecar in the cache.
  `composite_finish()` stamps `terra::time()` on `stk` **before** it is written. When a raster has time set, terra's COG writer puts it in a `<file>.aux.json` sidecar. The plain GTiff path used by `dft_stac_cube()` does not do this, which is why the existing `cache_write_atomic()` comment says `.tif` produces no sidecar. `cache_write_atomic()` only handles `<tmp>.aux.xml`: it unlinks that file on exit and renames it with the raster. The `.aux.json` is therefore left under the dead temp name.
  Reproduced on this machine (terra 1.9.50) with the package's own `composite_finish()` and `cache_write_atomic()`, using the exact `writeRaster(filetype = "COG", ...)` call from the diff:
  ```
  list.files(cache_dir)
  #> "composite_abc.tif"  "composite_abc.tmp26686-683e3de428c5.tif.aux.json"
  ```
  The same write with no time set produces no sidecar, so the time stamp is the cause.
  Effects:
  - One orphan per cache miss, which for chips means one per point per year.
  - `dft_cache_info()` counts them. This is the same litter class that `cache_write_atomic()`'s own comment says the sidecar handling exists to prevent.
  - The published COG does not carry the time. This is harmless only because `composite_finish()` re-stamps it on read.

  Two possible fixes:
  - Write `stk` before stamping the time, i.e. call `composite_finish()` only on the re-read `terra::rast(cache_file)`, which the code already does.
  - Or have `cache_write_atomic()` treat `.aux.json` the same as `.aux.xml`: unlink it on exit and move it into place.

  The first also keeps the cached COG free of a sidecar that titiler/S3 publishing would not carry.

- **[severity: bug, minor]** R/dft_map_interactive.R:248-279: with `x = NULL`, the transition legend is dropped along with the land-cover legend.
  The new `!is.null(x)` gate wraps the whole legend block, and the transition legend (`# Legend — transitions`) is nested inside it. `x = NULL` is newly allowed, so `dft_map_interactive(transition = tr, rgb = tc)` is now reachable. That call draws every transition overlay in its to-class colour with no legend. Verified: the call list contains `addRasterImage` × N and no `addLegend`.
  Also on this path: with `aoi = NULL` and `rgb` given as COG URLs, `bbox` is `NULL` even though `transition$raster` has an extent, so no `setView` is issued.
  Only the land-cover half should depend on `x`.

## Checked and found sound (not findings)

- **`stac_cube_session()` restore ordering.** `cube_parallel_check()` runs before any mutation. Nothing can error between the return and the `on.exit()` registration in either caller (it is a single assignment).
- **`tryCatch(build(), drift_no_items=, drift_empty_cube=)`.** Neither class can come from the cache-read path, which sits outside `build()`. `drift_composite_offset_split` is deliberately not caught. `cli_abort(class = ..., c(...))` puts the named `class` into `...`, so the class is attached (confirmed by the passing skip test).
- **`rgb_stretch`.** A 3-layer SpatRaster minus or divided by a length-3 vector recycles per layer (measured: `(0.1-0)/1, (0.2-0)/0.5, (0.3-0.1)/0.1` gives `0.1, 0.4, 2.0`). `clamp(values = TRUE)` saturates to 0/1 and leaves NA as NA.
- **`leafem::addRasterRGB(quantiles = NULL, domain = c(0,1))`** (leafem 0.2.5 source read). The `quantiles` branch is skipped and `rscl(from = c(0,1))` is the identity, so the terra stretch is what is drawn.
- **Classified layers projected to 3857 with `method = "near"`.** Factor levels and coltab survive (checked on the packaged classified raster: same values 1,2,4,5,7,9,11, coltab intact). leaflet 2.2.3 `addRasterImage(project = FALSE)` computes bounds by projecting the extent from the raster's CRS through 3857, so 3857 input is correct.
- **Z-order after toggling.** Re-added GridLayers append to the DOM, but `L.Control.Layers(autoZIndex = TRUE)` assigns z-indices in `overlay_groups` order. `rgb` comes first there, so it stays beneath `x` after toggling.
- **Tiled composite.** `terra::merge(sprc(...))` keeps layer names (measured), so `composite_layers_order()`'s by-name select also works on the tiled path.
- **`composite_window`.** Month-end arithmetic (Feb and leap year, Dec) is correct. `dt = P{last-first+1}M` always gives one step, and `composite_layers_order()` refuses anything else.
- **Cache key.** Uses `cache_key_hash` type tags. The WKB list goes through the `is.list` branch. The key is distinct from the cube key via the leading `"composite"` tag.
- **cli pluralisation.** Every `{?s}` in the new messages renders correctly at n = 1 and n = 2 (probed).
- **Offline tests.** `test-dft_map_interactive.R` and `test-dft_stac_composite.R` run green from a copy (`NOT_CRAN=true`); only the two network tests skip.

/private/tmp/claude-501/-Users-airvine-Projects-repo-drift/15f0d12b-1b2b-4965-8f08-91fb4f6a71a8/scratchpad/review-79-round1.md

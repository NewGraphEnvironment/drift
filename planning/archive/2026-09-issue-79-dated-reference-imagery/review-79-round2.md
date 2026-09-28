# Review #79 — round 2 (fixes first)

## Findings

- **[severity: bug]** R/dft_stac_composite.R:220-231 — The round-1 sidecar fix does not fix it on the real path. The comment says "Names only, NOT time, before the write", but the stack never lacked a time to begin with: `stac_cube_assemble()` returns `terra::rast()` of the gdalcubes NetCDF, and terra reads that file's time dimension (measured: `has.time() = TRUE`, step `yearmonths`, value shown as `1970-01-00`). `composite_layers_order()` (`stk[[idx]]`), `stac_cube_clip()` (`mask`) and `names<-` all keep that time, so the COG write still emits `<tmp>.aux.json`, and `cache_write_atomic()` still strands it.

  Measured on terra 1.9.50 / GDAL 3.13.0 / gdalcubes 0.7.5. I built a real gdalcubes cube from three local synthetic scenes (B02/B03/B04/SCL), then `apply_pixel(names = c("red","green","blue"))` and `write_ncdf`. I mocked only `stac_cube_items` and `stac_cube_assemble` (to return `terra::rast(<that .nc>)`) and ran the current `dft_stac_composite()` from a copy of the tree:
  - clip = FALSE: cache dir held `composite_<key>.tif` and `composite_<key>.tmp<pid>-<tok>.tif.aux.json`, and `dft_cache_info()$n_files` was 2.
  - clip = TRUE: the same orphan.
  - The orphan was still there after a second (cache-hit) call. A new one appears on every build or `force = TRUE` rebuild.

  With `terra::time(stk) <- NULL` added after `names(stk) <- bands`, both arms leave only the `.tif` (measured). The returned object still gets its time from `composite_finish()` on the re-read.

  **Why the new test stays green:** its `stac_cube_assemble` stub builds the raster with `terra::rast(ext, nlyrs = 3, vals = 0.05)`, which has no time. It therefore cannot reach the failure mode, which is inherited from the NetCDF reader and not from the code's own stamp. The stub would catch the old explicit `composite_finish()` stamp, but not this. To reach it, the fixture must carry a time, for example `terra::time(r) <- rep(as.Date("2023-06-01"), 3)`, or be a real gdalcubes NetCDF.

  **Sidecar triggers under the COG driver** (single-variable probes on a 3-band FLT4S raster, same `gdal=` options): `time`, `units`, `varnames` (a non-default value), `longnames`, `metags` and `scoff` each produce `.aux.json`. Plain `names` does not. On the real gdalcubes stack only `time` is set. Its varnames equal the layer names, units and longnames are empty, scoff is 1/0 and NAflag is NaN, and with time stripped it wrote no sidecar. So `time` is the only live trigger today.

  A more robust option than stripping one property is for `cache_write_atomic()` to move or unlink `paste0(tmp, ".aux.json")` as it already does for `.aux.xml`. Then a later `units`/`metags` addition cannot bring the orphan back.

  **Cube path (question 1b): not affected.** `dft_stac_cube()` writes a plain GTiff (no `filetype`), and GTiff with a monthly time and repeated names wrote no `.aux.json` and no `.aux.xml` (measured). The raw gdalcubes stack written as GTiff also wrote no sidecar.

## Checked, sound

- **dft_map_interactive x = NULL paths:**
  - `cog_mode <- is.character(NULL)` is FALSE, and the else branch's `inherits(NULL, "SpatRaster")` is FALSE, so `x` stays NULL.
  - `intersect(names(rgb), NULL)` is empty.
  - The classified-layer loop is skipped by the explicit `is.null(x)` arm.
  - `overlay_groups` / `hidden`: `setdiff(NULL, NULL)` is empty. The first rgb layer is shown, and the transitions are visible.
  - `class_table` is loaded unconditionally and used only by `add_transition_layers()` when `x` is NULL, which is harmless.
  - The transition legend reads `trans_result` only when `length(trans_groups) > 0`, which implies it was assigned.
  - The bbox falls back to `transition$raster` through the empty-template projection.
  - `x = NULL`, `rgb = NULL` with only `transition` aborts with the "Supply x or rgb" message. That is consistent with the documented contract (`x` may be NULL "when rgb is supplied").
- **The new `green`/`blue` roles** do not change any existing cube cache key. The cube key hashes only the index's `roles_needed` assets. `index_resolve_expr()` substitutes longest-first with `\b` boundaries, so `green` and `red` cannot clobber each other.

## Evidence

Scratch copy and scripts are in `scratchpad/r2/`: `nc.R` builds the gdalcubes NetCDF, `w.R` holds the per-property sidecar probes, and `e2e.R` drives the current composite build with the real NetCDF stack. The worktree `/Users/airvine/Projects/repo/drift-79` was not modified.

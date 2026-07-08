# Findings — Continuous index-trajectory change detection (Sentinel-2 + BFAST) (#30)

## Design validation (session 2026-07-08, plan mode)

Verified directly against the installed toolchain (read-only): gdalcubes 0.7.3,
rstac 1.0.1, terra 1.9.11, zoo 1.8.15. `bfast` / `strucchangeRcpp` NOT installed.

### gdalcubes `reduce_time` R-callback contract (from `reduce_time.cube.Rd`)
- Signature: `reduce_time(x, expr, ..., FUN, names = NULL, load_pkgs = FALSE, load_env = FALSE)`.
- FUN receives a **2-D array: rows = bands, cols = time steps**. Row names ARE
  band names — the shipped example indexes `x["B04", ]`, so `x["kndvi", ]` works
  **iff the input cube's band is literally named `kndvi`**.
- FUN must return a numeric vector of length `length(names)` → those become the
  output bands.
- **FUN runs in spawned worker R processes** (`load_pkgs`/`load_env`). Therefore:
  - `bfast` must be loaded in workers → `reduce_time(..., load_pkgs = "bfast")`.
    The main-process `rlang::check_installed("bfast")` gate alone is insufficient.
  - `band`/`ts_start`/`frequency`/`start`/`level`/`min_obs` must be
    **closure-captured scalars**, never derived from `cube` inside FUN.
- gdalcubes ships `L8NY18` (228 local Landsat TIFs at
  `system.file("L8NY18", package="gdalcubes")`) → an **offline** cube fixture for
  reduce_time / apply_pixel shape tests (no network).
- `create_image_collection(files, date_time=, band_names=)` builds a collection
  from local GeoTIFFs deterministically → synthetic offline cube feasible.

### Corrections to the issue-#30 sketch (all confirmed)
1. `tanh(ndvi^2)` → gdalcubes `apply_pixel` uses the **tinyexpr C engine**; `^`
   is not R exponentiation. Use `tanh(pow((nir-red)/(nir+red), 2))`. tinyexpr
   provides `pow`, `tanh`, `sqrt`, `exp`, `log`, etc.
2. `cube_view(extent = col)` sizes the cube to the union bbox of all returned
   scenes (full S2 tile), then `filter_geom` masks most to NaN AFTER the work.
   Build `extent` explicitly from `bbox_target` + parsed `t0`/`t1`, as
   `dft_stac_fetch()` already does.
3. `ext_filter(\`eo:cloud_cover\` <= cloud_cover_max)` uses NSE — a runtime
   variable needs `{{cloud_cover_max}}` and the property back-ticked. spacehakr's
   example only ever used a literal `<= 10`, so it never hit this.
4. `start_of(cube)` and `terra_from_cube()` are pseudo-code. Real: ts start from
   `dimension_values(cube, "M")$t` (main process); cube→terra via
   `write_ncdf(overwrite=TRUE)` → `terra::rast()` → `terra::mask()` (repo idiom).
5. `stac_search` cannot take both `bbox` and `intersects` — cube mode uses
   `intersects` only.
6. Config restructure is **forced backward-compatible** by the existing
   `expect_named(cfg, c("stac_url","collection","asset","available_years"))`
   test (exact-set). Cube sources add `cube = TRUE`; categorical sources keep
   exactly 4 fields → marker is **absence = FALSE** (`isTRUE(cfg$cube)`).
7. Scale/offset must be applied **inside** the index expression as a per-band
   affine token `(asset*scale+offset)`. A non-zero offset does NOT cancel in a
   ratio index → NDVI-on-raw-DNs is wrong for Landsat (offset -0.2) and
   baseline-04.00 S2 (offset -0.1). Only a pure multiplicative scale cancels.

### API names verified present with the used signatures
`image_mask(band, min, max, values, bits, invert)`, `filter_geom(cube, geom, srs)`,
`apply_pixel(x, ...)` (generic; `expr`/`names`), `raster_cube(..., mask=)`,
`cube_view`, `stac_image_collection`, `write_ncdf`, `ncdf_cube`,
`stac_search(..., intersects=, bbox=, limit=)`, `ext_filter(q, expr)`,
`post_request`, `items_fetch`, `items_sign(items, sign_fn)`,
`sign_planetary_computer()`, `dimension_values`. `bands(cube)` → data.frame with
`name/type/scale/offset/unit`.

### bfast::bfastmonitor return / semantics (knowledge; bfast not installed)
- `$breakpoint` = **decimal year** (e.g. 2022.34) or `NA` when no break (NOT an
  error). `$magnitude` = median of monitoring-period residuals (observed −
  predicted) → **negative = index drop = scour / veg loss; positive =
  establishment**. Inherent to the method; must be documented for callers who
  threshold on it.
- `start = c(year, period)` = monitoring-period start; `history=`, `level=` pass
  through. Failure modes to `tryCatch`: too-few history obs for
  `response ~ trend + harmon`, singular fits, gappy series → return `c(NA, NA)`.

### Open correctness subtlety (documented, follow-up candidate)
- S2 baseline-04.00 (+1000 DN) offset is **not uniform** across a 2017→2024
  archive: scenes processed under baseline ≥ 04.00 (~≥ 2022-01-25) carry the
  offset; earlier scenes have offset 0. A single `offset=-0.1` is slightly wrong
  for the pre-2022 portion. kNDVI is fairly robust (scale cancels in the ratio;
  residual is a small additive bias near the 2022 boundary). Ship documented
  accepted-bias; per-scene harmonization from item metadata is a follow-up.

## Reuse map
- `stac_cache_key()` / `auto_utm_epsg()` / sf-coercion / `write_ncdf→terra→mask`
  idiom in `R/dft_stac_fetch.R` — reuse for `dft_stac_cube()`.
- `dft_class_table()` CSV-reader in `R/dft_stac_classes.R` — mirror for
  `dft_index_table()` (`inst/lulc_classes/` → `inst/indices/`).
- `spacehakr::spk_stac_calc()` — pagination/intersects/cloud-filter proof and QA
  chip reader; used ONLY in `data-raw/`, never a DESCRIPTION dependency.

## Issue context

Full body: `gh issue view 30 --repo NewGraphEnvironment/drift`.
Relates to #9 (deferred BFAST evaluation), #19 (arbitrary factor rasters —
the optional from-to labelling bolt-on depends on it).

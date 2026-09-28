# Task: Dated reference imagery: true-colour composites, NDWI/MNDWI, and RGB layers in dft_map_interactive (+ HLS source) (#79)

Checking a land-cover label or a detected change needs **dated reference imagery for windows we choose**: the same season in different years, or early vs late season within a year. The basemaps in `dft_map_interactive()` (Esri, Google, and Bing in #78) are high resolution but have no date, so they can say what a place is and not when it changed.

drift already fetches Sentinel-2 L2A cubes (`dft_stac_cube()`, with cloud masking, a `months` filter and median aggregation), but only as a **single-index stack** (`ndvi`, `kndvi`, `ndmi`). Three pieces are missing to use it as a reference-imagery source. floodplains#93 needs them for a stratified accuracy assessment of IO LULC in BC floodplains.

Plan-gate decisions (2026-09-28):

- #80 (gdalcubes archived on CRAN) lands first as its own PR. This branch rebases onto main once it merges.
- The work has to hold at floodplain scale, because floodplains#93 reviews sample points across whole floodplains. There are two paths: per-point chips (buffered points plus `tile_size`), and COG composites served through titiler.
- Composites stay float reflectance, so they can later serve as classifier covariates.
- `dft_stac_composite()` is a new export that shares its internals with `dft_stac_cube()`.
- HLS gets a spike and its own issue. Re-read #79 before that phase.

## Phase 1: NDWI and MNDWI (independent, lowest risk)

- [x] Add `green = "B03"` and `blue = "B02"` to the `sentinel-2-l2a` roles (`R/dft_stac_config.R`), and update its roxygen.
- [x] Add `ndwi` `(green - nir) / (green + nir)` (McFeeters) and `mndwi` `(green - swir16) / (green + swir16)` (Xu) to `inst/indices/indices.csv`.
- [x] Tests (`test-dft_index_expr.R`): both rows ship. Each resolved expression, evaluated in R over known band values, gives the hand value. Examples: green 0.1 / nir 0.3 → −0.5, including through S2 scale/offset tokens. `mndwi` resolves `swir16` → `B11`. Existing cube cache keys are unchanged, and the frozen-key test stays green.

## Phase 2: extract shared cube internals (refactor, no behaviour change)

- [x] Move out of `R/dft_stac_cube.R`:
  - GDAL/gdalcubes session setup and restore;
  - STAC query, `months` filter and offset split (`stac_cube_items()`);
  - extent → cube_view → pre/post `cover` → tiling/mosaic (`stac_cube_assemble()`), taking a pixel function.
- [x] `dft_stac_cube()` calls these helpers and passes a `dft_index_expr()` closure as its pixel function.
- [ ] Guard: the frozen legacy key and every offline cube test pass unchanged. Run the network e2e (untiled + tiled) before and after, and record both.

## Phase 3: `dft_stac_composite()`

- [ ] `R/dft_stac_composite.R` with this signature: `aoi, years, months = 6:7, bands = c("red","green","blue"), source = "sentinel-2-l2a", res = 10, crs = NULL, aggregation = "median", resampling = "bilinear", clip = TRUE, cloud_cover_max = 20, mask_values = NULL, tile_size = NULL, parallel = NULL, cache_dir = NULL, force = FALSE, sign_fn = rstac::sign_planetary_computer()`. `bands` takes any roles and any number of them. The map needs exactly 3.
- [ ] Each year gets one window: `t0` = 1st of `min(months)`, `t1` = end of `max(months)`, `dt = P{span}M`. Items are filtered to `months`. The result is one time step: a median, cloud-masked **reflectance** stack (scale/offset per band via `scale_token()`) with layers named by role.
- [ ] Return a named list labelled like `"2017 Jun–Jul"`. A single year returns a length-1 list.
- [ ] The cache is `<source>/composite_<key>.tif`, **written as a COG** (`filetype = "COG"`) so the cached file can go to S3 and titiler unchanged. It is written through `cache_write_atomic()`, and read back only after `cache_hit_ok()` and the non-empty check pass. `stac_composite_cache_key()` covers geometry, res, crs, bands (resolved assets, order-sensitive), months (sorted), year window, cloud_cover_max, mask_values, scale/offset, clip and tile_size.
- [ ] **Per-point chips.** A documented example and a test show the chip path: `aoi` = sample points buffered to polygons, `tile_size` set. Through `tile_grid()` only tiles that intersect the points stream. An offline test on the grid confirms scattered buffered points select a small share of tiles.
- [ ] Validation: an unknown band role errors with the available roles; empty `years`/`months` or months outside 1–12 abort; a non-cube source aborts.
- [ ] Tests (offline): key determinism and sensitivity; labels (range, single month, non-contiguous); window derivation, including February's end in a leap year; validation; the pixel expression. One network e2e on the packaged AOI: 3 bands, plausible reflectance, a valid COG (`gdalinfo` layout, not an exit code), cached on the second call.
- [ ] Roxygen with true-colour and false-colour (`c("nir","red","green")`) examples. Run `devtools::document()` and `pkgdown::check_pkgdown()`.

## Phase 4: RGB layers in `dft_map_interactive()`

- [ ] New `rgb = NULL` argument: a named list of 3-band SpatRasters **or** a named character vector of COG URLs. That mirrors `x`'s dual mode.
  - Local: `leafem::addRasterRGB()`. leafem is already in Suggests; call `check_installed()` only when it is used.
  - COG: a titiler URL with `bidx=1&bidx=2&bidx=3&rescale=…`, built by a sibling of `build_titiler_url()`.
- [ ] Every RGB layer gets **one shared stretch**, so a brightness difference between years is real:
  - local mode uses a pooled 2–98% `domain` across all composites;
  - COG mode uses an `rgb_rescale` argument, defaulting to a documented reflectance range.
- [ ] RGB groups are switchable overlays beneath the classified and transition layers. The first is visible when `x` is `NULL`, and they are hidden otherwise. `x` may be `NULL` when `rgb` is given. Centring and legends handle that case.
- [ ] Tests: synthetic 3-band rasters; groups in the layer control; `x = NULL`; no land-cover legend without `x`; a non-3-band layer errors by name; the shared domain is applied; the COG URL has 3 `bidx` and the shared rescale, is percent-encoded, and errors without `titiler_url`.
- [ ] Live check: 2017 Jun–Jul and 2023 Aug–Sep on the packaged AOI over Esri/Google. Save the widget, view it in the browser, and run the cartography self-review on the screenshot.

## Phase 5: HLS spike → own issue; reconcile #79

- [ ] Re-read #79, since scope may have been edited again.
- [ ] Probe live:
  - `earthdatalogin` netrc / GDAL config;
  - a CMR-STAC `LPCLOUD` `HLSS30.v2.0` / `HLSL30.v2.0` search via rstac;
  - one COG read through gdalcubes;
  - S30 vs L30 band names (NIR `B8A` vs `B05`, and so on);
  - the Fmask **bit** mask against SCL classes (`image_mask(bits=)`?).
  Record the results in `findings.md`.
- [ ] File the HLS issue with the worked auth path and source-config shape. Edit the #79 body: point item 4 at it, and add the scale pivot (chips and COG) and the #80 dependency.

## Phase 6: scale test, docs, release

- [ ] BULK scale test with the RSS sampler. Record wall time and peak RSS for the PR:
  - `dft_stac_composite()` on `bulk_co_ff04`, one year, `tile_size` set;
  - a chip run over ~100 scattered buffered points.
  Also note what `dft_map_interactive(rgb=)` does with a floodplain-size local raster (maxBytes), to confirm the doc points to the COG path.
- [ ] Update NEWS.md, the CLAUDE.md Core Pipeline (the composite call and the chip pattern), and the gotchas note if anything turns up.
- [ ] Bump the version (minor) as the final commit.

## Validation

- [ ] Tests pass (`devtools::test()`, plus `DRIFT_TEST_NETWORK=true` e2e for cube and composite)
- [ ] `lintr::lint_package()` clean; `pkgdown::check_pkgdown()` passes
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

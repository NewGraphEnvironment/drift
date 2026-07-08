# Task: Continuous index-trajectory change detection (Sentinel-2 + BFAST) for floodplain reaches (#30)

drift detects change today by differencing pre-classified annual land-cover maps
(`dft_stac_fetch` → `dft_rast_classify` → `dft_rast_transition`). Masked to a
floodplain polygon that is the *weakest* place for the Esri IO LULC 9-class
annual product: it collapses gravel bars / wet-dry channel / sparse seasonal
riparian into `bare`/`rangeland`, and annual compositing smears event timing.

Issue #30 adds the stronger signal: a **continuous index trajectory** per pixel —
detect *when* a pixel's spectral history breaks and by how much — instead of
comparing two categorical labels. The machinery is already a dependency
(`gdalcubes`, `rstac`, `terra`); this is a new fetch mode + a reducer, not a new
toolchain. Four new exports: `dft_stac_cube()`, `dft_index_expr()`
(+ `dft_index_table()`), `dft_rast_break()`. Plus a config restructure and a
network-decoupled vignette. **Whole pipeline on one branch, single 0.3.0 release.**

## Phase 1: Config — role-based schema + Sentinel-2 source
- [ ] `R/dft_stac_config.R`: expand `match.arg` to `c("io-lulc","esa-worldcover","sentinel-2-l2a","landsat-c2-l2")`; add `sentinel-2-l2a` entry (`cube=TRUE`, `roles=list(red="B04",nir="B08",swir16="B11",mask="SCL")`, `mask_values=c(3L,8L,9L,10L)`, `scale=1e-4`, `offset=-0.1`, `available_datetime`); keep `io-lulc`/`esa-worldcover` 4-field **verbatim**; add `landsat-c2-l2` as a commented drop-in template (`red`/`nir08`, `qa_pixel`, scale 2.75e-5 / offset -0.2)
- [ ] `R/dft_stac_fetch.R`: friendly guard in config-resolve block — if `isTRUE(cfg$cube)` and `asset` still `NULL`, `cli::cli_abort("Source '{source}' is a cube source; use dft_stac_cube().")`; categorical path untouched
- [ ] `tests/testthat/test-dft_stac_config.R`: keep the 3 existing tests byte-for-byte; add cube-source assertions (`isTRUE(cfg$cube)`, role names + `$red=="B04"`/`$nir=="B08"`/`$mask=="SCL"`, `mask_values`, `scale`, `offset`, `available_datetime`); backward-compat assertion that `io-lulc` has no `cube` field

## Phase 2: `dft_index_expr()` + table-driven index registry
- [ ] `inst/indices/indices.csv`: registry (`index,formula,roles,description`) — `ndvi`, `kndvi=tanh(pow((nir-red)/(nir+red),2))`, `ndmi`; formulas in tinyexpr C syntax over **roles**, self-contained (kNDVI inlines NDVI)
- [ ] `R/dft_index_expr.R`: `dft_index_table()` (reads the CSV, mirrors `dft_class_table()`); internal `index_resolve_expr(index, roles, scale, offset)` — pure string builder, per-role scaled token `(asset*scale+offset)` when scale≠1 or offset≠0 else bare asset, longest-role-first word-boundary substitution, unknown-index `cli_abort` listing available; internal `index_roles(index)`; exported `dft_index_expr(cube, index="kndvi", source="sentinel-2-l2a", roles=NULL, scale=NULL, offset=NULL)` → `gdalcubes::apply_pixel(cube, expr, names = index)`
- [ ] `tests/testthat/test-dft_index_expr.R` (pure local, no gdalcubes/network): kNDVI-over-S2 resolves to the exact scaled string; scale/offset on (Landsat) vs off (bare) tokens; `ndmi` resolves `swir16→B11`; unknown-index error

## Phase 3: `dft_stac_cube()`
- [ ] `R/dft_stac_cube.R`: signature `dft_stac_cube(aoi, source="sentinel-2-l2a", index="kndvi", datetime=NULL, res=10, crs=NULL, dt="P1M", aggregation="median", resampling="bilinear", cloud_cover_max=60, mask_values=NULL, cache_dir=NULL, force=FALSE, sign_fn=rstac::sign_planetary_computer())`; `check_installed("gdalcubes")`; `stopifnot(isTRUE(cfg$cube))`; reuse `auto_utm_epsg`/sf-coercion/`dft_cache_path`; derive assets from `index_roles(index)` ∩ `cfg$roles` + `cfg$roles$mask`; STAC query with **`intersects`** (not bbox) + `ext_filter({{cloud_cover_max}})` + `post_request() |> items_fetch() |> items_sign()`; **explicit** `cube_view` extent from `bbox_target` + parsed `t0`/`t1`; `raster_cube(col, v, mask=image_mask(mask_asset, values=mask_values)) |> filter_geom(...)`; `dft_index_expr(...)`; materialize to `<source>/cube_<key>.nc` via `write_ncdf(overwrite=TRUE)`, return `gdalcubes::ncdf_cube(f)`; `force` overwrites
- [ ] Internal `stac_cube_cache_key()` (leave `stac_cache_key()` byte-for-byte unchanged — pinned by fetch tests): hash AOI-WKB + `res`/`target_crs`/`dt`/`aggregation`/`resampling`/`stac_url`/`collection` + cube additions `band_assets`/`datetime`/`index`/`cloud_cover_max`/`sort(mask_values)`/`scale`/`offset`
- [ ] `tests/testthat/test-dft_stac_cube.R`: local gdalcubes-missing guard (mirror fetch test); `stac_cube_cache_key` unit tests (determinism/12-hex, per-param sensitivity incl. index/datetime/cloud_cover_max/mask_values/scale/offset, sf-attrs ignored, 10L≡10); network E2E `skip_on_cran()` + `skip_if_offline()` + `skip_if_not_installed("gdalcubes")` (short window on `example_aoi.gpkg`, assert single `kndvi` band + cache-hit on second call)

## Phase 4: `dft_rast_break()` — bfast reducer (empirical gate FIRST)
- [ ] **Smoke-test gate before writing the function**: install `bfast` (+ `strucchangeRcpp`); run the 4-leg smoke script (scratchpad/data-raw): (a) synthetic 24-pt monthly series w/ injected step drop → `bfastmonitor(start=c(2022,1))` gives finite `$breakpoint` ≈ injected date, `$magnitude<0` (pins ts/frequency/`c(year,period)` semantics); (b) synthetic local cube (`create_image_collection(date_time=, band_names="kndvi")`→`cube_view(dt="P1M")`→`raster_cube`) through `reduce_time(names=c("break_date","break_mag"), load_pkgs="bfast", FUN=…)`→`write_ncdf`→`terra::rast` gives `nlyr==2`, correct names, `x["kndvi",]` resolves in FUN, break pixel finite / all-NA pixel NA; (c) `dt="P1M"` + `frequency=1` yields garbage (motivates the guard); (d) tiny real-S2 leg via `dft_stac_cube()` returns a 2-band raster. Proceed only if all pass
- [ ] `R/dft_rast_break.R`: internal `.dft_break_pixel(v, start, frequency, ts_start, history, level, min_obs)` — degenerate all-NA / `<min_obs` early-return `c(NA,NA)` **before touching any `bfast::` symbol**, else `ts()` + `bfastmonitor()` + `tryCatch → c(NA,NA)`; exported `dft_rast_break(cube, band=NULL, history="all", start=c(2022,1), frequency=NULL, level=0.01, min_obs=6, cache_dir=NULL, force=FALSE)` — `check_installed("gdalcubes"/"bfast")`, `band %||% bands(cube)$name[1]`, derive `ts_start`/`frequency` in main process from `dimension_values`, **`stop()` if caller `frequency` disagrees with dt cadence**, `reduce_time(names=c("break_date","break_mag"), load_pkgs="bfast", FUN=closure)`, `write_ncdf(overwrite=TRUE)`→`terra::rast`→`mask`; roxygen documents decimal-year `break_date` and sign convention (neg `break_mag` = index drop = scour/veg loss)
- [ ] `DESCRIPTION`: add `bfast` to Suggests
- [ ] `tests/testthat/test-dft_rast_break.R`: gdalcubes-missing + bfast-missing guards (the latter runs now); `.dft_break_pixel` NA/short-input no-skip; cache-key extension; `skip_if_not_installed("bfast")` synthetic step-drop (finite date, mag<0) + stable-series (NA, non-error); `skip_if_not_installed(c("gdalcubes","bfast"))` synthetic-cube integration (`nlyr==2`, names, CRS/extent)

## Phase 5: Vignette + docs + release
- [ ] `data-raw/vignette_data_break.R` (network + bfast + `spacehakr` — **data-raw only, zero DESCRIPTION footprint**): `dft_stac_cube()` → `dft_rast_break()` on `example_aoi.gpkg`; optional QA chips via `spacehakr::spk_stac_calc()`; save `terra::wrap()`ed break raster (+ chips) to `inst/testdata/`; header notes network+bfast requirement
- [ ] `vignettes/trajectory-break-detection.Rmd` (`bookdown::html_document2`, matches existing): load committed artifact (`terra::unwrap`/`rast`) — no STAC/bfast at build; break_date + break_mag maps (diverging palette, neg=scour), AOI outline, sample pixel kNDVI trajectories with detected breakpoint marked
- [ ] `devtools::document()`; `lintr::lint_package()` clean; full `devtools::test()` passes (network/bfast-gated tests skip appropriately)
- [ ] File follow-up issue(s): optional bolt-on (label breaks → from-to via `dft_rast_transition()` + IO LULC sampling; #19-dependent, out of scope here); per-scene S2 baseline-04.00 offset harmonization (accepted-bias documented for now, kNDVI robust)
- [ ] NEWS.md `0.3.0` section; bump DESCRIPTION `0.2.4 → 0.3.0` as the **final** commit

## Validation
- [ ] Tests pass (`devtools::test()`), network/bfast tests skip cleanly
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

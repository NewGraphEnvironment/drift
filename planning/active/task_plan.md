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
- [x] `R/dft_stac_config.R`: expand `match.arg` to `c("io-lulc","esa-worldcover","sentinel-2-l2a")`; add `sentinel-2-l2a` entry (`cube=TRUE`, `roles=list(red="B04",nir="B08",swir16="B11",mask="SCL")`, `mask_values=c(3L,8L,9L,10L)`, `scale=1e-4`, `offset=-0.1`, `available_datetime`); keep `io-lulc`/`esa-worldcover` 4-field **verbatim**; add `landsat-c2-l2` as a commented drop-in template (`red`/`nir08`, `qa_pixel`, scale 2.75e-5 / offset -0.2). NOTE: `landsat-c2-l2` left OUT of `match.arg` (in match.arg but no switch case = silent NULL); it stays a commented template until implemented
- [x] `R/dft_stac_fetch.R`: friendly guard in config-resolve block — if `isTRUE(cfg$cube)`, `cli::cli_abort(... use dft_stac_cube())`; keyed on `cube` alone (not `&& is.null(asset)`) so a cube source never falls through to an opaque `stopifnot(years)`; categorical path untouched
- [x] `tests/testthat/test-dft_stac_config.R`: keep the 3 existing tests byte-for-byte; add cube-source assertions (`isTRUE(cfg$cube)`, role names + `$red=="B04"`/`$nir=="B08"`/`$mask=="SCL"`, `mask_values`, `scale`, `offset`, `available_datetime`); backward-compat assertion that `io-lulc`/`esa-worldcover` have no `cube` field

## Phase 2: `dft_index_expr()` + table-driven index registry
- [x] `inst/indices/indices.csv`: registry (`index,formula,roles,description`) — `ndvi`, `kndvi=tanh(pow((nir-red)/(nir+red),2))`, `ndmi`; formulas in tinyexpr C syntax over **roles**, self-contained (kNDVI inlines NDVI). Uses `pow()` not `^` (gdalcubes tinyexpr)
- [x] `R/dft_index_expr.R`: `dft_index_table()` (reads the CSV, mirrors `dft_class_table()`); internal `index_resolve_expr(index, roles, scale, offset)` — pure string builder, per-role scaled token `(asset*scale±|offset|)` when scale≠1 or offset≠0 else bare asset, longest-role-first word-boundary substitution, unknown-index/absent-role `cli_abort`; internals `index_row()`/`index_roles()`/`scale_token()`; exported `dft_index_expr(cube, index="kndvi", source="sentinel-2-l2a", roles=NULL, scale=NULL, offset=NULL)` → `gdalcubes::apply_pixel(cube, expr, names = index)`
- [x] `tests/testthat/test-dft_index_expr.R` (pure local, no gdalcubes/network): kNDVI-over-S2 resolves to the exact scaled string; scale/offset on (Landsat) vs off (bare) tokens; `ndmi` resolves `swir16→B11`; unknown-index + absent-role errors. 15 assertions green. **Code-check Clean.**

## Phase 3: `dft_stac_cube()`
- [x] `R/dft_stac_cube.R`: full signature per plan; `check_installed("gdalcubes")`; `!isTRUE(cfg$cube)` reject; reuse `auto_utm_epsg`/sf-coercion/`dft_cache_path`; derive assets from `index_roles(index)` + `cfg$roles$mask`; STAC query with **`intersects` (unioned AOI)** + `ext_filter(\`eo:cloud_cover\` <= {{cloud_cover_max}})` + `post_request() |> items_fetch() |> items_sign()`; **explicit** `cube_view` extent from `bbox_target` + parsed `t0`/`t1`; `raster_cube(col, v, mask=image_mask(mask_asset, values=mask_values)) |> filter_geom(...)`; `dft_index_expr(...)`; materialize to `<source>/cube_<key>.nc` via `write_ncdf(overwrite=TRUE)`, return `gdalcubes::ncdf_cube(f)`; `force` overwrites. **Code-check fixed a multi-feature-AOI bug: union AOI before `intersects` (else silent NoData holes — the #25 class).** `eo:cloud_cover` NSE declared in `utils::globalVariables()`
- [x] Internal `stac_cube_cache_key()` (leaves `stac_cache_key()` byte-for-byte unchanged): hash AOI-WKB + `res`/`target_crs`/`dt`/`aggregation`/`resampling`/`stac_url`/`collection` + cube additions `band_assets`/`datetime`/`index`/`cloud_cover_max`/`sort(mask_values)`/`scale`/`offset`
- [x] `tests/testthat/test-dft_stac_cube.R`: local gdalcubes-missing guard; categorical-source reject; `stac_cube_cache_key` unit tests (determinism/12-hex, per-param sensitivity, mask-order + res-type normalization, sf-attrs ignored); network E2E gated behind `DRIFT_TEST_NETWORK=true` env var (keeps `devtools::test()` network-free per repo convention). 20 assertions green

## Phase 4: `dft_rast_break()` — bfast reducer (empirical gate FIRST)
- [x] **Smoke-test gate** (bfast 1.7.2 installed): legs (a) `bfastmonitor` on a synthetic step-drop → `breakpoint=2022.417 magnitude=-0.30`; (b) synthetic local cube through `reduce_time` → 2-band raster, correct names, break/NA pixels correct; (c) `frequency=1` on a P1M cube yields different (garbage) → guard justified. **KEY FINDING: closure capture DOES NOT WORK in the reduce_time R-callback (worker process, any parallel setting) — `object 'band' not found`.** Design changed to a self-contained callback (embed helper object + inline literals), proven at parallel 1 and 2. See findings.md.
- [x] `R/dft_rast_break.R`: internal `.dft_break_pixel(v, ts_start, frequency, start, history, level, min_obs)` — degenerate all-NA / `<min_obs` early-return `c(NA,NA)` **before any `bfast::` symbol**, else `ts()` + `bfastmonitor()` + `tryCatch → c(NA,NA)`; `cadence_frequency()` (ISO→freq); `build_break_reducer()` (self-contained FUN, no free vars); `break_cache_key()` (as_json(cube) + params); exported `dft_rast_break(cube, band=NULL, history="all", start=c(2022,1), frequency=NULL, level=0.01, min_obs=6, cache_dir=NULL, force=FALSE)` — derives `ts_start`/`frequency` from `dimensions(cube)$t`, `stop()` on frequency mismatch, `reduce_time(load_pkgs="bfast")`, `write_ncdf`→`terra::rast`; roxygen documents decimal-year `break_date` + sign (neg = index drop = scour)
- [x] `DESCRIPTION`: add `bfast` to Suggests
- [x] `tests/testthat/test-dft_rast_break.R` + `helper-break.R`: gdalcubes/bfast-missing guards; `cadence_frequency` mapping; `.dft_break_pixel` NA/short-input no-skip; `build_break_reducer` no-free-vars (codetools); `break_cache_key` per-param; bfast-gated step-drop (finite date, mag<0) + stable-series (NA); gdalcubes+bfast synthetic-cube integration. 30 assertions green. **Code-check Clean** (serialization verified in a fresh process)

## Phase 5: Vignette + docs + release
- [x] `data-raw/vignette_data_break.R`: `dft_stac_cube()` (growing-season, offset-split) → `dft_rast_break()` on `example_aoi.gpkg`; clip to AOI polygon; save `terra::wrap()`ed break raster + a few pixel trajectories to `inst/testdata/neexdzii_break.rds` (132 KB). Header notes network+bfast requirement. (spacehakr QA chips deferred — not needed; the trajectory panels come from the cube itself)
- [x] `vignettes/trajectory-break-detection.Rmd` (`bookdown::html_document2`): loads the committed artifact — no STAC/bfast at build; break_mag map (diverging palette, neg=scour), break_date map, AOI outline, scour-vs-stable kNDVI trajectories with the detected break marked. **Renders clean.**
- [x] `devtools::document()`; `lintr::lint_package()` clean; full `devtools::test()` passes (286 pass, network/bfast-gated tests skip)
- [x] File follow-up issues: #31 (bolt-on labels), #32 (AOI-polygon clip). The S2 offset was NOT deferred — implemented via the baseline-conditional split (offset half of #32 closed)
- [x] NEWS.md `0.3.0` section
- [ ] Bump DESCRIPTION `0.2.4 → 0.3.0` as the **final** commit

## Validation
- [x] Tests pass (`devtools::test()`), network/bfast tests skip cleanly (286 pass)
- [x] `/code-check` clean on each commit (6 fresh-eyes reviews; all real issues fixed)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

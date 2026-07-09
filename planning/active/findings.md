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

## Phase 4 empirical gate result (2026-07-08) — DESIGN CHANGE

Ran the smoke test after installing bfast 1.7.2 / strucchangeRcpp 1.5.4. Findings:
- **Leg (a) passed exactly**: a 72-pt monthly series with a −0.3 step at 2022-06
  → `bfastmonitor(start=c(2022,1), level=0.01)` returns `breakpoint=2022.417`,
  `magnitude=-0.300`. Scalar `level` is accepted (default is length-2). Stable
  series → `breakpoint=NA` (no error). So `history="all"` + scalar `level` work.
- **CLOSURE CAPTURE DOES NOT WORK.** The reducer FUN runs in a spawned worker for
  the R-callback path **at every `parallel` setting, including `parallel=1`**.
  A closure (even a `force()`d factory frame) fails in the worker with
  `object 'band' not found` — gdalcubes does not restore the closure environment.
  Both the issue-#30 sketch and the original agent-B design assumed closures work;
  they don't. This is the gate's headline catch.
- **SELF-CONTAINED FUN WORKS** at `parallel` 1 and 2. Two variants proven:
  inline scalar literals via `substitute()`, or embed the per-pixel helper as a
  literal function OBJECT (env detached to `baseenv()`) + inline scalar params.
  Chosen: **embed-the-helper-object** — keeps a single logic source
  (`.dft_break_pixel()`, directly unit-testable) AND a worker-safe FUN.
  Result on the 2×2 synthetic cube: `nlyr=2`, names `break_date`/`break_mag`,
  drop pixel `date=2022.42 mag=-0.3`, stable pixels `NA/0`, all-NA pixel `NA/NA`.
- `load_pkgs = "bfast"` is required so the worker can resolve `bfast::bfastmonitor`.
- Degenerate paths (`all(is.na(v))` / `sum(!is.na(v)) < min_obs`) return `c(NA,NA)`
  **before any `bfast::` symbol** → unit-testable with no bfast dependency.

Design for `R/dft_rast_break.R` (proven):
```r
.dft_break_pixel <- function(v, ts_start, frequency, start, history, level, min_obs) {
  if (all(is.na(v)) || sum(!is.na(v)) < min_obs) return(c(NA_real_, NA_real_))
  ts_v <- stats::ts(v, start = ts_start, frequency = frequency)
  tryCatch({
    m <- bfast::bfastmonitor(ts_v, start = start, history = history, level = level)
    c(m$breakpoint, m$magnitude)
  }, error = function(e) c(NA_real_, NA_real_))
}
# reducer FUN: embed .dft_break_pixel as a literal object (env=baseenv) + inline
# band/ts_start/frequency/start/history/level/min_obs via substitute(); no free
# vars; reduce_time(..., load_pkgs = "bfast").
```
`bfastmonitor` return: `$breakpoint` = decimal year or NA; `$magnitude` = median
monitoring-period residual (neg = index drop = scour; ~0 = stable). `ts_start`
and `frequency` come from `gdalcubes::dimension_values(cube, "M")$t` in the main
process; `stop()` if a caller `frequency` disagrees with the dt cadence.

## Sentinel-2 baseline offset — the correctness catch (2026-07-08)

A peer validation session + my own growing-season E2E stats surfaced that PC's
`sentinel-2-l2a` +1000 DN reflectance offset only applies from processing
baseline 04.00 (2022-01-25 on); earlier scenes have offset 0. A **uniform**
`offset = -0.1` is therefore wrong pre-2022 and creates a false whole-AOI index
step at the boundary. kNDVI's `tanh` hid it (bounded 0-1) so the cube looked
valid, but my E2E had **90903/91467 (99%) negative breaks all at 2022.42** — the
boundary, not vegetation. User chose to fix it properly (baseline-conditional
split), not defer.

**terra re-architecture (validated):**
- gdalcubes CANNOT read a terra-written NetCDF (dim-name mismatch), so coalescing
  pre/post cubes at the gdalcubes level is impossible. Pivoted to terra.
- `dft_stac_cube()` returns a **terra SpatRaster stack** (materialized GeoTIFF,
  `terra::time` set). If the source has `offset_boundary` and items straddle it,
  it builds a pre cube (offset `offset_before`) and post cube (offset) over the
  SAME full `cube_view`, and coalesces with `terra::cover(pre, post)`.
- `dft_rast_break()` reduces the stack via `parallel::mclapply` (fork -> closures
  and package internals inherited, no gdalcubes-worker serialization). Validated:
  102400 px in 8.3 s. `.dft_break_pixel` unchanged. Dropped build_break_reducer,
  break_cache_key, gdalcubes reduce_time.
- `cadence_frequency()` now derives frequency from the median day-spacing of the
  layer times (26-32d -> 12, 85-95d -> 4, 360-370d -> 1).

**Split validation E2E (2018-2023, months=6:9):** split fired 75 pre / 85 post;
per-year growing-season mean kNDVI now ALIGNS across the boundary
(2021=0.524 -> 2022=0.529, all years 0.41-0.53, no jump); finite breaks dropped
from 99% to **25% of usable pixels**, spread across 2022-2024. Offset artifact
gone. Config: `sentinel-2-l2a` gains `offset_boundary="2022-01-25"`,
`offset_before=0`.

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

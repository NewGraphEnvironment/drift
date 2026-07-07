# Task: dft_stac_fetch cache key omits AOI -> second area silently gets first area's raster (#25)

`dft_stac_fetch()` caches fetched rasters at `file.path(cache_source_dir, paste0(yr, ".nc"))`
(`R/dft_stac_fetch.R:103`) — keyed only by **source** and **year**, with **no AOI component**. Any
two calls with the same `source`/`year` but different `aoi` collide: the second call finds the
first call's NetCDF, skips the fetch (when `force = FALSE`, the default), and returns the **first
AOI's raster masked to the second AOI**. No warning, no error — just wrong data.

## Phase 1: Cache key includes AOI + fetch parameters

- [x] Add internal `stac_cache_key()` helper in `R/dft_stac_fetch.R` — WKB geometry + `as.numeric(res)` + `target_crs` + `dt` + `aggregation` + `resampling` + post-resolution `stac_url`/`collection`/`asset`, `rlang::hash()`, 12-char prefix
- [x] Compute key once after AOI/CRS resolution; cache filename becomes `<year>_<key>.nc` (`R/dft_stac_fetch.R:103`)
- [x] Unit tests in `tests/testthat/test-dft_stac_fetch.R` (all local, no network): determinism; shifted geometry → different key; different `res`/`crs`/`collection`/`asset`/`stac_url` → different keys; `res = 10` vs `10L` → same key; sf-with-attributes vs bare sfc → same key; key matches `^[0-9a-f]{12}$`

## Phase 2: force = TRUE overwrites cleanly

- [x] `gdalcubes::write_ncdf(cube, cache_file, overwrite = TRUE)` (`R/dft_stac_fetch.R:126`)
- [x] Update `@param force` roxygen — overwrites the cached file; note that a SpatRaster returned earlier and backed by the same file may silently see new content on POSIX

## Phase 3: Docs + release

- [x] Roxygen note in `dft_stac_fetch` docs: cache entries keyed by AOI geometry + fetch parameters; `devtools::document()`
- [x] NEWS.md entry for 0.2.3: bug + fix, existing caches will refetch, `dft_cache_clear()` reclaims space
- [x] `lintr::lint_package()` clean + full `devtools::test()` pass (one pre-existing vignette lint, untouched by this branch)
- [x] Version bump to 0.2.3 in DESCRIPTION as final commit

## Validation

- [x] Tests pass
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

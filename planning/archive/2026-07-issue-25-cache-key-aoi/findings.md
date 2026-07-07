# Findings — dft_stac_fetch cache key omits AOI (#25)

## Issue context

**Repo:** NewGraphEnvironment/drift · **Severity:** high (silent wrong data, no error) · **Version seen:** 0.2.2

### Summary

`dft_stac_fetch()` caches fetched rasters at `file.path(cache_source_dir, paste0(yr, ".nc"))`
(`R/dft_stac_fetch.R:103`) — keyed only by **source** and **year**, with **no AOI component**. Any
two calls with the same `source`/`year` but different `aoi` collide: the second call finds the
first call's NetCDF, skips the fetch (when `force = FALSE`, the default), and returns the **first
AOI's raster masked to the second AOI**. No warning, no error — just wrong data.

### Evidence (real occurrence)

Running two BC watershed areas through a floodplain/LULC pipeline that calls
`dft_stac_fetch(source = "io-lulc", years = c(2017, 2020, 2023))`:

1. Area A (Neexdzii, a reach of the Bulkley) ran first → populated
   `~/Library/Caches/drift/io-lulc/{2017,2020,2023}.nc` with Neexdzii's extent. Correct output.
2. Area B (MORR / Morice, ~80 km west, larger) ran second → `dft_stac_fetch` found the cache files
   and returned **Neexdzii's** rasters, masked to the MORR floodplain.

Cache extent vs. AOIs (EPSG:32609, metres):

| | E min–max | N min–max |
|---|---|---|
| cache `io-lulc/*.nc` | 645443–696463 | 6000758–6056578 |
| **Neexdzii** fp bbox | 645444–696461 | 6000762–6056573 | ← cache == Area A |
| **MORR** fp bbox | 566715–651331 | 5948369–6035818 | ← what Area B should have gotten |

Result: MORR's land cover was classified over only the ~3% where the Neexdzii cached extent
overlaps the MORR floodplain (near the shared Bulkley/Morice confluence); "tree loss" came out
22 ha of Bulkley-valley agricultural transitions instead of the true MORR figure.

### Secondary bug: `force = TRUE` cannot overwrite

`force = TRUE` routes to the fetch branch and calls `gdalcubes::write_ncdf(cube, cache_file)`
without removing the existing file first. When the cache file exists, `write_ncdf` errors:

```
Error: File already exists, please change the output filename or set overwrite = TRUE
```

So `force = TRUE` cannot be used to bypass a stale/colliding cache — the user must manually delete
the file (or call `dft_cache_clear()`).

### Fix (from issue)

1. **Put the AOI in the cache key.** Hash the AOI (bbox + geometry) into the filename. Preserves
   caching for repeat runs of the *same* AOI while eliminating cross-AOI collisions. (Also fold
   `res`, `crs`, `aggregation` into the key, since they change the output too.)
2. **Fix `force = TRUE`** to overwrite instead of erroring.
3. **Defensive check (optional):** on a cache hit, verify the cached raster's extent covers the
   requested AOI bbox; if not, re-fetch.

### Minimal repro

```r
library(drift)
a <- sf::st_as_sf(sf::st_sfc(sf::st_buffer(sf::st_point(c(-126.75, 54.41)), 0.1), crs = 4326))
b <- sf::st_as_sf(sf::st_sfc(sf::st_buffer(sf::st_point(c(-127.75, 54.05)), 0.1), crs = 4326))  # ~65 km west
ra <- dft_stac_fetch(a, source = "io-lulc", years = 2020)  # fetches
rb <- dft_stac_fetch(b, source = "io-lulc", years = 2020)  # returns a's cached raster, masked to b -> mostly NA
# terra::ext(rb[["2020"]]) matches a, not b
```

## Plan-mode exploration (2026-07-06)

### Code facts

- Only place the `<year>.nc` filename is constructed: `R/dft_stac_fetch.R:103`. Written at :126,
  read at :107/:127. No other code, test, vignette, or data-raw script assumes the pattern.
- `dft_cache_clear()` / `dft_cache_info()` (`R/dft_cache.R`) are filename-agnostic
  (`list.files(recursive = TRUE)` / `unlink(recursive = TRUE)`) — unaffected by a filename change.
  `dft_cache_clear(source=)` assumes only the per-source subdirectory, which is kept.
- Fetch-affecting params NOT in the current key: `aoi`, `res`, `crs`, `dt`, `aggregation`,
  `resampling`, `stac_url`, `collection`, `asset`. All must enter the hash. `sign_fn` doesn't
  affect pixels; `source` remains the directory.
- `rlang` and `sf` are already in Imports; `digest` is not a dependency and isn't needed —
  `rlang::hash()` (XXH128) works. No hashing exists anywhere in the package yet.
- Existing tests never exercise the network fetch path (only `auto_utm_epsg` and the
  missing-gdalcubes error). Cache-key helper is unit-testable fully offline via `drift:::`.

### Design decisions (validated against installed sf 1.1.0 / rlang 1.2.0 / gdalcubes 0.7.3)

- **Hash WKB (`sf::st_as_binary(sf::st_geometry(x), endian = "little")`), not the sfc object.**
  sfc carries a PROJ-generated CRS WKT that drifts across PROJ versions → spurious cache misses.
  WKB is coordinates + geometry type only; CRS enters the key separately as `target_crs`.
  Also immune to sf attribute columns (verified: sf-with-attributes and bare sfc hash identically
  via WKB).
- **`as.numeric(res)`** — `10L` vs `10` serialize differently under `rlang::hash()`; identical
  fetches would get different keys without coercion.
- **Hash post-resolution `stac_url`/`collection`/`asset`** (after the `%||%` config resolution),
  never the raw possibly-NULL args — otherwise `dft_stac_fetch(aoi)` and an explicit-but-identical
  call hash differently. Bonus: also fixes a latent collision where a custom collection with
  default `source = "io-lulc"` landed in the io-lulc dir keyed only by year.
- **Year stays out of the hash** — key computed once before the per-year `lapply`; filename
  `<year>_<key>.nc` groups all years of one call under a shared readable suffix.
- **`write_ncdf(..., overwrite = TRUE)` over bare `unlink()`** — gdalcubes 0.7.3 signature is
  `write_ncdf(x, fname, overwrite = FALSE, ...)`. Bare `unlink()` fails *silently* on Windows when
  a prior SpatRaster holds a GDAL handle on the file, reproducing the original confusing error.
- **Extent check (issue's optional item 3) skipped** — user confirmed 2026-07-06. gdalcubes'
  `cube_view` only ever *enlarges* extents to fit the pixel grid, so a containment check with
  one-pixel tolerance would validate nothing; post-hash-fix, legacy `<year>.nc` files can never
  match the new pattern anyway.
- **Old-format cache files become dead weight** — correct behavior; do NOT auto-delete (can't
  attribute them to an AOI). NEWS notes existing caches refetch and `dft_cache_clear()` reclaims
  space.
- **POSIX silent-swap caveat** — with `force = TRUE`, a SpatRaster returned by an earlier call and
  backed by the same cache file may lazily reopen and see the new content. Newly reachable (the
  old behavior errored first), but benign under the hash key: the overwritten file corresponds to
  the identical parameter set. Documented in `@param force` rather than engineered around.

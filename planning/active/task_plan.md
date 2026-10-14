# Task: Promote Esri Wayback capture index + chip fetch to dft_wayback_* (#101)

**If we do it:** any floodplain AOI can get Esri Wayback imagery at the **capture** nearest a date, per point or per patch, from one package call. Today that code lives only as two driver scripts in floodplains.
**If we never do:** the next consumer (another area's accuracy review, a change-patch check, rtj) re-derives the release-vs-capture trap and the QGIS redirect workaround from scratch.

That has started to happen: a third script, which frames one site at a dated capture for a figure, already carries its own copy of the release lookup and the GDAL WMS block (2026-10-14).

## Context

floodplains#115 (closed 2026-10-09) proved a way to get Esri Wayback imagery at the **capture** nearest a date. It lives in two NECR driver scripts (`wayback_index-capture.R`, `wayback_build-chips.R`) and in two helpers in `fp_accuracy.R` (`fp_acc_wayback_pick`, `fp_acc_wayback_wms_xml`). A third script has already copied the release lookup and the GDAL WMS block. This issue promotes the reusable part to four exports, so any floodplain AOI gets it from one package call. The NECR-specific parts stay in floodplains: Voronoi cells, review_id naming, manifests and the VRT.

Decisions made at this gate:
- **`zoom` is a range and the deepest wins.** The default is `zoom = 17:19`. For each (feature, release), the deepest zoom whose metadata layer (`23 - zoom`) covers the feature is kept. This reproduces floodplains' `wayback.csv`, which is mostly zoom 18. A single zoom still works.
- **Polygons get every capture plus a `cover` column.** A polygon feature gets one row per distinct capture that intersects it, with `cover` = the share of its area under that capture. A point keeps floodplains' rule (the top DrawOrder wins, then the finer source) and gets `cover = 1`. The pick does not use `cover`, and the docs say to filter on it first.
- **The issue's precondition is not met yet.** Its "promote once the NECR review has used the chips" has not happened: no labels exist yet. You invoked the issue anyway, and the issue's own 2026-10-14 edit records the duplication that this work stops, so I'm treating the precondition as waived.

Measured during exploration (2026-10-14):
- `waybackconfig.json` holds 197 releases. `itemTitle` reads "World Imagery (Wayback YYYY-MM-DD)".
- Each metadata MapServer has layers 0-13: layer 0 is 1.9 cm (zoom 23) and layer 13 is 150 m (zoom ≤ 10). So valid zoom is 10:23.
- drift's Imports have no `jsonlite` or `curl`. Both are already installed through rstac/httr.

## API

```r
dft_wayback_releases()            # tibble: release_id (chr), release_date (Date), meta_url; sorted by date
dft_wayback_captures(aoi, zoom = 17:19, releases = NULL, cache_dir = NULL, force = FALSE)
  # tibble, one row per (feature, release, capture):
  # feature (row of aoi), release_id, release_date, capture_date (Date), res_m, source, zoom, cover
dft_wayback_pick(captures, date)  # per (feature, date): nearest capture_date to `date`, then finer res_m,
  # then the later release_date, then the larger release_id; adds date, days_from_date
dft_wayback_fetch(aoi, release, zoom, crs = NULL, res = NULL, clip = TRUE, empty_max = 0.05,
                  cache_dir = NULL, force = FALSE)   # SpatRaster RGB INT1U, nodata 0
```

## Phase 1: Release list + HTTP helper
- [x] `R/dft_wayback_releases.R` with internal `wayback_get()`: `curl::curl_fetch_memory`, with the status read from curl, 3 tries and a 120 s timeout. It raises a classed `drift_wayback_http` error with the URL and status.
- [x] `dft_wayback_releases()`: parse `waybackconfig.json`. Abort if any release lacks a parseable date or a metadata URL. Sort with radix on the date.
- [x] Add `curl` and `jsonlite` to Imports in DESCRIPTION.
- [x] Tests: parse a fixture JSON with `wayback_get` mocked, covering release ids out of date order, a malformed title (abort) and a missing metadata URL (abort). One network test gated on `DRIFT_TEST_NETWORK`.

## Phase 2: Capture index
- [x] `dft_wayback_captures()`: validate `zoom` (integer, within 10:23) and map each zoom to layer `23 - zoom` internally. Query the AOI's bbox in 4326, padded so a single point is not a degenerate envelope, with `geometryPrecision=1` and `outSR=3857`, paging on `exceededTransferLimit`.
- [x] Cache each response (rds) under `cache_scheme_dir(cache_dir, "esri-wayback")/meta`. The key is the release, the layer and the hashed bbox via `cache_key_hash()`, and writes go through `cache_write_atomic()`. A past release's metadata is immutable, so the cache only refreshes on `force`.
- [x] Join in 3857 with `st_intersects`, running `st_make_valid` on the copy used for the join only.
  - Points: the top DrawOrder wins, then the finer res.
  - Polygons: distinct captures with `cover` taken from the intersection area.
  - For both, keep the deepest zoom per (feature, release).
  - Rows with a null `SRC_DATE` are dropped, because they are base layers and not captures.
- [x] `releases =` accepts a filtered `dft_wayback_releases()` table, so a caller can query a subset of releases.
- [x] Tests:
  - Synthetic capture polygons, with `wayback_get` mocked to return ArcGIS JSON. Cover the layer↔zoom mapping, deepest wins, the DrawOrder tie, `cover` on polygons, null `SRC_DATE`, paging and a cache hit.
  - One network test.
- [x] Plan review (review-plan.md) folded in: polygon cover is the VISIBLE share (DrawOrder occlusion, B3); per (feature, release) the deepest zoom covering the feature whole, else the zoom of greatest cover (G1); OBJECTID-ordered paging with dedup and JSON-error retry (G6); salted metadata key (G8)
- [x] BULK scale run of the polygon cover path, moved here from Phase 5 (review O1)

## Phase 3: Pick
- [ ] `dft_wayback_pick(captures, date)`: `date` is a `Date` vector, and the result has one row per (feature, date) for every feature that has a capture. The ranking order is in the API block above, and it is a total order. Drop NA capture dates.
- [ ] Tests:
  - Each tiebreak level gets its own case, and restoring the defect must fail the case (bug-restore).
  - Several dates.
  - A feature with no capture returns no row, and this is documented.

## Phase 4: Fetch
- [ ] Internal `wayback_wms_xml(release, zoom, cache)`, ported from `fp_acc_wayback_wms_xml` with `ZeroBlockHttpCodes 204,404` and the tile cache under `cache_scheme_dir(cache_dir, "esri-wayback")/tiles`.
- [ ] `dft_wayback_fetch()`:
  - CRS: `crs = NULL` → `auto_utm_epsg()`.
  - Resolution: `res = NULL` → the tile ground resolution at the AOI's latitude, rounded to 0.05 m.
  - Warp: `gdal_utils("warp", -te, -tr, -tap, -r bilinear)` to a tempfile, with `GDAL_PAM_ENABLED=NO`.
  - Clip: with `clip = TRUE`, mask to the polygon by cell centre (`touches = FALSE`), so adjacent AOIs such as Voronoi cells share no cell.
  - Nodata: a real 0 is moved to 1 and 0 becomes nodata. This is lossless DEFLATE plus nodata, not a mask, because a VRT ignores masks.
  - Cache: a COG keyed on the AOI's WKB, release, zoom, crs, res and clip, written through `cache_write_atomic()`.
- [ ] Guards: abort with `drift_wayback_empty` when more than `empty_max` of the AOI came back empty (all three bands 0). A flat block is not a failure, because open water is flat. For GDAL warnings, first measure what a clean warp emits, then abort on any warning that is not on that list. Do not count them and continue, which is what floodplains does.
- [ ] Tests: the WMS XML content, the res rule and the empty guard, using a local GTiff source in place of the WMS. One network test that fetches the NECR point 1 chip.

## Phase 5: Docs, verification at scale, hand-off
- [ ] roxygen with `\dontrun` examples covering the per-point pattern (one call per buffered point), then `devtools::document()`, `lintr`, `pkgdown::check_pkgdown()` and `devtools::test()`.
- [ ] Equivalence on NECR: run drift's captures (`zoom = 17:19`) and pick (`date = as.Date("<endpoint>-07-01")`) on `reference/necr/sample.gpkg`, and diff against `wayback.csv`. Report the agreement count. Each disagreement must be explained by the dropped whole-year banding. Any other disagreement is a defect.
- [ ] Scale runs under `/usr/bin/time -l`, with the numbers going into the PR body:
  - captures over the NECR sample bbox;
  - fetch for about 20 chips;
  - (BULK polygon cover path: done in Phase 2)
- [ ] CLAUDE.md: a Wayback block in Core Pipeline, including the release-vs-capture trap. NEWS entry.
- [ ] File a floodplains issue to convert `wayback_index-capture.R` and `wayback_build-chips.R` into thin drivers over `dft_wayback_*`. Note that the whole-year banding now lives in the driver, as the date it passes.

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Critical files
- New: one file per export (`R/dft_wayback_releases.R`, `_captures`, `_pick`, `_fetch`), plus `tests/testthat/test-dft_wayback_*.R`
- Reuse: `cache_scheme_dir()`/`dft_cache_path()` (`R/dft_cache.R`), `cache_key_hash()`, `cache_write_atomic()` and `auto_utm_epsg()` (`R/dft_stac_fetch.R`)
- Edit: `DESCRIPTION`, `CLAUDE.md`, `NEWS.md`
- Source to port: `~/Projects/repo/floodplains/scripts/landcover_accuracy/{wayback_index-capture.R,wayback_build-chips.R,fp_accuracy.R}`

## Verification
`devtools::test()`; `DRIFT_TEST_NETWORK=true` for the live tests; the NECR equivalence diff against `wayback.csv`; and the `/usr/bin/time -l` peak RSS for the scale runs.

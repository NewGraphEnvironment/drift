# Plan review (Plan agent, 2026-10-14) — triage

Findings returned as reply text (Plan type has no Write). Summary + disposition:

| id | finding | disposition |
|---|---|---|
| B1 | cache_write_atomic validates as raster; rds would abort | already avoided: own rds temp+rename writer, read error = miss; NULL response cached (cache test) |
| B2 | null-date drop must follow DrawOrder + deepest dedups | order already matches source; add test: undated deepest layer hides dated shallower |
| B3 | polygon cover ignores DrawOrder occlusion | fix: cover = share under the VISIBLE part (footprint minus every footprint ranked above it) |
| G1 | "deepest zoom" undefined for polygons | fix: deepest zoom whose footprints cover the whole feature, else the zoom of greatest cover (points: deepest covered) |
| G2 | geometry types / CRS / fetch on points | captures: POINT/POLYGON/MULTIPOLYGON only, no-CRS abort (done); fetch: polygons only, "covers no pixel" guard |
| G3 | release_id compared as number | pick: numeric desc; test ids "9" vs "10" |
| G4 | pick not total for polygons | add keys: higher cover, earlier capture_date, source; days_from_date signed |
| G5 | empty results | zero-row typed tibble + warning (done); pick passes empty through |
| G6 | paging stability, JSON error retry | orderByFields=OBJECTID, dedup on OBJECTID if supported (probe); JSON error retried |
| G7 | multi-part footprints | make_valid on all parsed footprints (done) + two-outer-ring and hole tests (done) |
| G8 | fetch key gaps; metadata salt | key empty_max + salt (tile url, zero codes, resampling); meta salt names query params |
| G9 | per-AOI UTM/res breaks mosaics | document: mosaic callers pass crs and res; Phase 5 runs pass EPSG:3005 |
| G10 | 404 pixels become near-black | all-band-zero -> nodata; a lone zero band -> 1 |
| G11 | no test seam for the WMS | internal wayback_source() mockable |
| G12 | GDAL_PAM via Sys.setenv | gdal_utils(config_options =) |
| O1 | scale-test polygon cover in Phase 2 | moved: BULK patches x one release before Phase 3 |
| O2 | freeze releases for equivalence | filter release_date <= 2026-10-08; check point_ids; crs EPSG:3005 |
| A1 | older releases may lack layers | probe several releases |
| A2 | GDAL warning allowlist fragile | abort message prints the warning |
| A3 | bbox pad in degrees | kept: misses only, never wrong |
| S1 | no-capture rows dropped | floodplains hand-off issue says driver re-expands |
| S2 | per-patch fetch is a mosaic of captures | docs say so |
| S3 | version bump | /gh-pr-merge release bookkeeping does it |

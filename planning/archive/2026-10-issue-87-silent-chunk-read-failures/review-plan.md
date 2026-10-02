# Plan review (Plan agent, 2026-10-02) — summary

No blocker. Claims to verify before acting:

1. Assumption (high): chunk_status flags only open failures. Reads that fail after
   GDALOpen succeeds (throttling, a token expiring mid-extent) leave NaN with status OK
   (image_collection_cube.cpp:424-437, warp.cpp:256/650-654). Probe: truncate a TIFF.
2. Gap: a failed mask (SCL) open `continue`s the image loop with no set_status
   (image_collection_cube.cpp:569-579) — silent thinner composite. Probe: delete SCL only.
3. Gap: fill appears only with workers (claim) — integration tests should run at parallel 4.
4. Gap: master merge failure leaves fill + an Rcpp::warning("Chunk N could not be added").
5. Assumption: transient 5xx/429 at open now aborts a long run; add GDAL_HTTP_MAX_RETRY /
   RETRY_DELAY; a persistent 404 aborts every run, so "re-run" wording misleads.
6. Gap: composite year loop catches drift_no_items / drift_empty_cube — test that
   drift_incomplete_cube is not swallowed (two-year test).
7. Gap: dft_stac_cube offset-split path (two build_stack + cover) and count path untested.
8. Ordering: integration tests before wiring + un-wire to confirm red; tiled fetch tile
   files unlinked only after the vapply; build_stack tempfile never unlinked (pre-existing).
9. Scope: holed caches written before the fix stay served; untiled fetch caches are the
   .nc and could be checked in cache_hit_ok(); NEWS should advise force = TRUE.
10. Acceptance: live probe should name cube/composite and fetch, tiled and untiled, the
    parallel used, and include a live false-abort control (months = 6:9 at parallel 4).
11. ncdf4 in Suggests is fine (gdalcubes import(ncdf4)).

Triage: see findings.md "Plan review triage".

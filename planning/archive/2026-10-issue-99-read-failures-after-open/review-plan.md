# Plan review — #99 (Plan agent, 2026-10-14)

Read-only agent; findings returned as reply text and written here by the session.
Read against appelmar/gdalcubes@ed68331 via `gh api`.

## Blocker
- **B1** `.libPaths()` inside R never reaches gdalcubes workers (spawned `Rscript` inherits
  env, not the session lib path). Use `R_LIBS=<scratch>/lib` exported in the shell; run
  probes at parallel >= 2. — *Already the method used; the parallel-2 tinytest passed
  patched / failed unpatched, which shows workers loaded the right build.*
- **B2** Dropping items in `stac_cube_assemble()` breaks the #87 integration tests (features
  with no `assets`), `composite_offset_check()` runs on the undropped `is_pre`, the offset-split
  message would be stale, and an all-dropped year would abort a multi-year composite. Do it
  in `stac_cube_items()` after the month filter, as a pure helper, raising `drift_no_items`
  when all are dropped. — *Adopted.*
- **B3** The upstream tinytest cannot depend on terra/withr. — *Adopted: fixture built with
  `write_tif(COG = TRUE)` from dummy cubes, base `writeBin` for corruption.*

## Answers
- Q1: `warp()` dispatches to `warp_simple` (`:73`, every geotransformed image, `ChunkAndWarpImage`
  unchecked at `:256`) and `warp_complex` (`:436`, GCP/RPC only, DEBUG-logged at `:650`). All four
  callers already handle nullptr. Cleanup on failure must keep transformer/tmparg restore,
  `CPLFree(wkt_out)`, `GDALClose(in)` (warp owns `in`), then `GDALClose(out)`. Treat
  `Initialize()` failure as failure too. — *Adopted.*
- Q2: aggregation (`agg->update`, `:657`) follows the mask block, so mask-path `continue`s drop
  the scene (not unmasked); band-path `continue`s keep the image with NaN for that band.
- Q3: an INCOMPLETE all-NA chunk survives: the worker only skips `OK && all_nan()`, read_ncdf
  sets status before dimension checks, and derived cubes propagate status.
- Q4: `fetched` comes from `stac_cube_items()`; re-signing is not a constraint.
- Q5: tinytest is right; upstream tests use dummy cubes, so none exercises `warp()`.

## Gap
- **G1** Failed overview reopen (`warp.cpp:160-169`, `:553-562`) leaves `hSrcDS` on a closed
  dataset. — *Adopted: reopen at full resolution, else fail.*
- **G2** `nc_inq_dimlen` unchecked; empty-chunk return leaks the handle; uninitialised buffer on
  `nc_get_var_double` failure. — *Adopted.*
- **G3** Fork `master` is behind upstream; sync it and PR into `master`. — *Adopted.*
- **G4** Corruption recipe must be recorded (DEFLATE tile at a `TileOffsets` entry); assert
  `failed >= 1`. — *Adopted.*
- **G5** Abort text and roxygen must cover the read-back cause. — *Phase 4.*
- **G6** Capability probe lazy and memoised. — *Phase 4.*

## Ordering
- O1 open the fork PR after Phase 2. O2 mutation check by forcing the probe on against 0.7.5.
  O3 Phase 3 can go first. — *All adopted.*

## Assumption
- A1 a failed warp may not always be a failed read (source-window failures in exotic
  reprojections). — *Clean controls added (other CRS, partial footprint, overviews).*
- A2 partial warps are now discarded — intended; say so in the PR.
- A3 the supervision loop does not explain the hang; sample the hung process. — *Done: the
  cause is the log-printing loop (`!wlogf.eof()` on a missing file).*
- A4 a capability gate turns a future regression into SKIPs — accepted at the gate.

## Scope
- S1 worker-side write failures (`nc_create`/`nc_put_vara`/`nc_close` unchecked) — left out,
  named in the upstream draft.
- S2 pre-existing leaks on `continue` paths — out, mention in the PR.
- S3 items missing a band asset (not the mask) — out of scope.
- S4 the fix reaches the user's runs only once installed — note in the report.

## Acceptance
- AC1 clean controls; AC2 cloud value visible in the output; AC3 strict branch — *all added to
  the tinytest.* AC4 read_ncdf has no test — *say so in the PR.*

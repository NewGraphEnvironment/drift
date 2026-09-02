# Task: dft_stac_fetch: interrupted fetch leaves a corrupt .nc cache that is trusted as a hit on resume (#41)

An interrupted `dft_stac_fetch()` leaves a **truncated `.nc` cache file at the canonical cache
path**, and the next run treats it as a valid cache hit (`"<year>: cached"`) rather than
re-fetching. The partial file then fails downstream — it is not a readable raster.

Two gaps: the write is **non-atomic** (killed mid-write leaves a partial file at the canonical
name; the cache-hit check is presence-only), and the read is **unvalidated** (presence implies
trust).

Scoped by the user to cover `dft_stac_cube()` as well — it carries the identical defect
(`R/dft_stac_cube.R:429` writes straight to `cache_file`; `:264` is presence-only), and its cache
is the costlier one to lose (multi-hour Sentinel-2 stream vs small annual rasters).

Design revised after a Plan review whose empirical premises were probed — see `findings.md`. Two
were refuted; the surviving changes are the temp-validated-before-rename seam and the cube's
zero-cost whole-file probe.

## Phase 1: Failing tests for atomic write (fetch)

- [x] Test: a writer that throws partway leaves **nothing** at the canonical cache path
- [x] Test: a writer that throws partway does **not destroy an existing good cache** under `force = TRUE`
- [x] Test: `file.rename()` returning `FALSE` aborts rather than silently leaving no cache
- [x] Test: no `*.tmp*` temp file survives a successful write
- [x] Confirm all fail against current `main`

## Phase 2: `cache_write_atomic()` and wire into fetch

- [x] Add `cache_write_atomic()` to `R/dft_stac_fetch.R` — temp in same dir, **real extension preserved** (terra picks its driver from it), PID + counter in the name, no leading dot, checked `file.rename()`, `on.exit()` cleanup
- [x] Wrap the two call sites that name `cache_file` (untiled `fetch_extent_to()`, and `mosaic_tiles()`) — **not** inside `fetch_extent_to()`, which is also called per-tile with a `tempfile()` already and would then rename across filesystems
- [x] Fix the tile leak: `on.exit(unlink(tile_files), add = TRUE)` so a `mosaic_tiles()` error does not strand every tile
- [x] Phase 1 tests go green

## Phase 3: `cache_usable()` + validation on both write and read

- [x] `cache_geom_ok()` — predicate over plain numerics, so every branch is unit-testable (terra refuses to construct degenerate rasters)
- [x] `cache_usable()` — arm (a) open **errors only** (never the multidim capability warning), arm (b) geometry incl. empty-CRS **conjoined** with the identity geotransform, arm (c) last-row read raises a warning
- [x] **Validate the temp before renaming** — covers `force = TRUE` and the miss branch, which currently flows unvalidated into `terra::mask()` at `R/dft_stac_fetch.R:192`
- [x] Gate the fetch cache hit on `cache_usable()`; warn naming the failing arm, then re-fetch
- [x] Test arm (a) — zero-byte and truncated fixtures; assert `rast()` really errors (premise)
- [x] Test arm (b) — `cache_geom_ok()` directly on all branches, plus one file-level identity-geotransform fixture for the wiring
- [x] Test arm (c) — CI test injects a warning-raising probe and is **named for that**; fixture-based version is env-guarded and skips (never passes) if the damage fails to warn
- [x] Confirm `force = TRUE` skips read-side validation

## Phase 4: Same two changes in `dft_stac_cube()`

- [ ] Wrap `terra::writeRaster()` at `R/dft_stac_cube.R:429` in `cache_write_atomic()`
- [ ] Gate the cache hit at `:264` on `cache_usable()`, **before** `cube_check_nonempty()` — validity first, so a truncated all-NA file reads as corrupt not as an AOI mismatch
- [ ] Fold arm (c) into the existing `cube_check_nonempty()` `global()` scan via a warning handler — a whole-file probe at zero added cost
- [ ] Tests for both on the cube path

## Phase 5: Docs, NEWS, version

- [ ] Correct `@param force` at `R/dft_stac_fetch.R:44-47` and `R/dft_stac_cube.R:110-111` — the "may silently pick up the rewritten contents" promise is wrong after the rename
- [ ] Cache paragraph at `R/dft_stac_fetch.R:8-13` — entries are published atomically and validated
- [ ] `R/dft_cache.R` docs — `*.tmp*` orphans, and that `dft_cache_clear()` already removes them
- [ ] State plainly that the row probe **samples rather than proves**; the atomic write is the guarantee
- [ ] `devtools::document()`
- [ ] NEWS.md — include that `force = TRUE` previously destroyed a good cache in place, and that concurrent same-key writes are now last-writer-wins
- [ ] Version 0.10.0 → 0.11.0 (final commit)

## Validation

- [ ] `devtools::test()` green
- [x] **False-refusal control**: `cache_usable()` passes all 168 files in the real cache
- [ ] **Restore-the-defect**: each new test goes red against the reverted fix (patch BOTH `asNamespace("drift")` and `as.environment("package:drift")`)
- [ ] `lintr::lint_package()` no new lints vs baseline
- [ ] `devtools::check()` clean
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

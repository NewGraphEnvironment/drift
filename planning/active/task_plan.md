# Task: Adopt the fixed filter_geom now that the gdalcubes segfault is resolved (unblocks #38) (#47)

## Problem

`dft_stac_cube()` streams COGs over the AOI's **bounding box** (`assemble_index_stack()` →
`gdalcubes::cube_view(extent = bbox_ext)`, `R/dft_stac_cube.R:300-332`) and only afterwards clips the
assembled terra stack to the polygon (`stac_cube_clip()` = `terra::mask()`, `:351`, `:370-372`). On the
packaged Neexdzii AOI the polygon is **10.2%** of its bbox, so ~90% of every streamed pixel is thrown away.

`gdalcubes::filter_geom()` would push the polygon into the *read*, but drift was deliberately written
around its absence (#32) because it segfaulted or returned an all-NA cube.
`NewGraphEnvironment/gdalcubes@newgraph` (`8bad203`) fixes that and is installed on this machine.

## What exploration established, that reshapes the issue

| finding | consequence |
|---|---|
| CRAN gdalcubes is **also 0.7.4** and still broken; upstream `appelmar/gdalcubes#110` open, PR #111 unmerged | a `packageVersion()` check cannot distinguish fixed from broken — only a behavioural probe can |
| Failure is bimodal: hard segfault (uncatchable by `tryCatch`) **or** a silent all-NA cube | the probe must run in a subprocess *and* assert on values, not on "it returned" |
| `filter_geom.cpp::read_chunk()` returns early **without** calling `_in_cube->read_chunk(id)` for outside chunks | the read reduction is real, but its granularity is the **chunk**, not the pixel |
| gdalcubes' `default_chunksize()` targets `2 * parallel` spatial chunks; `parallel` defaults to 1 | on the packaged AOI (326 × 313 px at res=10) default chunking is 256×256 → a **2 × 2 grid**. A corridor intersects all four. **Default-chunking `filter_geom` skips nothing.** |
| chunk edge clamps to [64, 1024] px | finest achievable granularity is 640 m at res=10 — real, but nowhere near the polygon-exact ~10× the issue claims |
| the constructor throws `Polygon must be located completely within the data cube` unless the polygon is strictly interior | drift's extent *is* `st_bbox(aoi_target)`, so the polygon touches every edge — the extent must be padded |
| drift already ships `tile_size` (#36/#38), a working read-bound | `filter_geom` must be measured **against** it, not just against the untiled baseline |

The issue's central number is therefore not established, and this plan leads with measurement.

**Decisions taken** (user, 2026-09-01): runtime **capability probe** with fallback (drift stays
installable from CRAN); scope is **`dft_stac_cube()` only** — `dft_stac_fetch()` keeps `tile_size` and its
post-read mask, with a follow-up issue carrying the measured numbers.

## Phase 1: Measure before changing any API

New `data-raw/benchmark_filter_geom.R` (matches the existing `data-raw/benchmark_transition_oom.R`
family). No package API changes in this phase.

- [ ] Reproduce `appelmar/gdalcubes#110`'s offline repro on the installed fork; confirm it succeeds **and**
      that the broken mode is distinguishable by values (non-NA inside, NA outside)
- [ ] Establish the extent padding needed so `aoi_target` is strictly interior to drift's `bbox_ext`
      (`R/dft_stac_cube.R:329-332`) — find the minimum that avoids the `within` throw, in pixels of `res`
- [ ] Benchmark arms on the packaged Neexdzii AOI **and** one large real floodplain AOI (magnitude is
      dataset-specific; the fixture is not the case anyone cares about):
      **A** today's untiled bbox + `terra::mask` · **B** `filter_geom` at default chunking ·
      **C** `filter_geom` at `chunking = c(1, 64, 64)` and `c(1, 128, 128)` · **D** existing `tile_size`
      at comparable granularity (640 m, 1280 m)
- [ ] Cost must be **observed, not inferred from chunk arithmetic**: count `/vsicurl` range requests via
      `CPL_CURL_VERBOSE=YES` (stderr → a file, never merged into stdout), bytes fetched, and wall clock
- [ ] Equivalence check: `filter_geom` output vs today's clipped output — same extent/`nlyr`, per-layer
      means and correlation; characterise any edge-pixel disagreement (GDAL rasterize cell-centre vs
      `terra::mask` cell-centre)
- [ ] Record every arm, including the ones that disappoint, in `findings.md`

**Decision gate.** If arm C beats neither A nor D by a margin worth two code paths, stop: close #47 with
the measurement and file the chunking finding upstream. Only continue past this line if the numbers earn it.

## Phase 2: Capability probe

- [ ] Internal `filter_geom_ok()` in a new `R/dft_gdalcubes_capability.R`
- [ ] Runs the offline reproducer in an **R subprocess** so a segfault kills the child, not the session:
      write the probe to a tempfile and run `system2(file.path(R.home("bin"), "Rscript"), shQuote(path), ...)`
      — never `Rscript -e` (quoting/backslash trap), stderr to its own file, and **read the exit status**,
      not just the output
- [ ] Assert all three, so neither failure mode passes: child exited 0 · ≥1 **non-NA** cell inside the
      polygon (kills the all-NA mode) · ≥1 **NA** cell outside (kills a silent no-op)
- [ ] Cache the verdict in the package env — at most one subprocess per session
- [ ] Escape hatch `options(drift.filter_geom = TRUE/FALSE)` so a user or CI can pin either way without a probe
- [ ] **Bound stated in the roxygen:** the probe establishes the installed *build* is patched (the segfault
      is in `filter_geom`'s own chunk logic, not in the COG reader). It does not prove the network path.

## Phase 3: Wire it into dft_stac_cube()

- [ ] Take the `filter_geom` path when the probe passes, `tile_size` is `NULL`, and `clip = TRUE`
- [ ] Pad `bbox_ext` (`:329-332`) by the Phase-1 margin so the polygon is strictly interior
- [ ] `gdalcubes::filter_geom(cube, sf::st_union(sf::st_geometry(aoi_target)), srs = target_crs)` immediately
      after `raster_cube()` (`:285-287`), with `chunking` set explicitly to the Phase-1 value
- [ ] Skip `stac_cube_clip()` on this path (`filter_geom` already NAs the outside); keep the helper for the fallback
- [ ] Name the two interactions rather than letting them fall out: **`clip = FALSE`** is incompatible
      (`filter_geom` always clips) so it stays on the bbox path; **`tile_size`** and `filter_geom` are
      mutually exclusive — document which wins
- [ ] `stac_cube_cache_key()` (`:407`) gains the read mode, **appended only when the `filter_geom` path is
      taken** — same shape as the `tile_size` append (`:424`), so the frozen legacy hash
      (`638a2be11fdf`, `test-dft_stac_cube.R:57-63`) and every existing `cube_<key>.tif` stay valid

## Phase 4: Tests

- [ ] Offline: probe returns `TRUE` here; and a test that **forces the all-NA / no-op verdict and asserts
      the probe returns `FALSE`** — the guard has to be seen firing, not assumed
- [ ] Offline: legacy cache key byte-identical when the path is not taken; `filter_geom` keys apart
- [ ] Offline: `clip = FALSE` and `tile_size` route away from `filter_geom`
- [ ] Network smoke test (`DRIFT_TEST_NETWORK=true` + probe passes), asserting **non-NA coverage inside the
      polygon** and NA outside — it must not be able to pass on the all-NA cube that #32 was protecting
      against — plus agreement with the `terra::mask` arm

## Phase 5: Docs, dependency, release

- [ ] Rewrite the first bullet of `inst/notes/gdalcubes-pc-gotchas.md` (`:8-20`) — it currently reads "Do NOT
      clip inside the cube pipeline". Record the fork, the chunking finding, the within-cube constraint, and
      the measured numbers
- [ ] Replace the "never `filter_geom`" comment at `R/dft_stac_cube.R:276-280` and `:346-350`; update the
      `tile_size` roxygen at `:75` ("the `filter_geom`-independent way to bound the read")
- [ ] DESCRIPTION: add `NewGraphEnvironment/gdalcubes@newgraph` to `Remotes:` so fresh installs get the
      working build; the probe covers anyone already holding CRAN gdalcubes
- [ ] Follow-up issue for `dft_stac_fetch()`, carrying Phase-1's numbers and noting its cache is written
      unmasked (`R/dft_stac_fetch.R:188`) so adopting this there changes cached content
- [ ] `NEWS.md`; version bump as the **final** commit of the branch

## Validation

- [ ] Tests pass (`devtools::test()`); `devtools::document()` output read for unexpected `.Rd` writes
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, with the Phase-1 numbers in the archive README's Measurement section

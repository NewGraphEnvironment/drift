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

## Phase 1: Measure before changing any API — **COMPLETE, gate says stop**

`data-raw/benchmark_filter_geom.R` + `..._compare.R`. Evidence:
`data-raw/logs/benchmark_filter_geom/summary.csv`.

- [x] Reproduce `appelmar/gdalcubes#110`'s offline repro on the installed fork — passes, so
      adoption never depended on that PR merging
- [x] Establish the extent padding — 0 px throws, 1 px suffices, 2 px used
- [x] Benchmark arms on the packaged AOI with observed range-request counts
- [x] Instrument positively controlled before any count was believed
- [x] Record every arm, including the ones that disappoint

| arm | wall clock | requests | vs A | non-NA |
|---|---|---|---|---|
| A — today's bbox + `terra::mask` | 236.8 s | 462 | 1.00 | 49,244 |
| B — `filter_geom`, default chunking | 236.9 s | 462 | 1.00 | 41,608 |
| C — `filter_geom`, 64 px chunking | 348.2 s | 693 | 1.50 | 41,608 |
| C — `filter_geom`, 128 px chunking | 343.7 s | 693 | 1.50 | 41,608 |
| D — `tile_size = 640` (already shipped) | 1263.6 s | 3213 | 6.96 | 49,244 |

- [x] Rival hypothesis: `gdalcubes_options(parallel = 4/8)` on the baseline. drift never
      calls `gdalcubes_options()` at all, so every fetch is single-threaded *and* coarse-chunked

**GATE: FAILED for `filter_geom`.** Not a close call — no arm beats the baseline on either
metric. At default chunking it is exactly neutral in cost while silently shrinking the
footprint 15.5%; at the finest chunking gdalcubes permits it is 1.5× the requests and 47%
slower. The predicted 26.7% chunk skip is real and is *more than cancelled* by losing
alignment with the COGs' 512×512 blocks — the skip saves ground that was cheap, and the
refetching costs more than the ground was worth. Structural arithmetic said 339 requests;
the wire said 693.

## Phase 0: Defects that exist today, independent of #47

Found while reviewing. These land regardless of how #47 is resolved.

- [x] `tests/testthat/test-dft_stac_cube.R:219-242` — the only end-to-end cube test **passes
      on an all-NA cube**. `fully_na` is 1.0 for an empty cube and the assertion is
      `expect_gt(fully_na, 0.5)`; `nlyr`, `time` and the cache-file checks pass too. Replace
      with in-polygon non-NA, per-layer non-NA, and outside-NA. Confirm red against a stubbed
      all-NA cube before believing the fix
- [x] `R/dft_stac_cube.R:364-366` — documents the clip as "cells whose centre falls outside",
      but `terra::mask()` defaults to `touches = TRUE`. Correct the roxygen
- [x] Add the offline oracle that distinguishes the two rules — the existing clip test
      (`:116-138`) uses an axis-aligned polygon on a cell boundary, where they agree, so it
      cannot reach the difference. Assert the premise beside the property
- [x] Post-condition before `terra::writeRaster()` (`:355`): abort when no in-polygon cell is
      non-NA, so the all-NA mode cannot reach a cache file

## Phase 2: Close #47 with the measurement

- [x] Rewrite the issue body — its premise (~10× from the 0.102 area ratio) is refuted. The
      area ratio is the wrong bound: the read is chunk-granular and cost is COG-block-granular
- [x] Record in `inst/notes/gdalcubes-pc-gotchas.md`: the fork fixes the segfault, but the
      default chunking defeats the skip and fine chunking costs more than it saves. Keep the
      "do not use `filter_geom`" guidance, replacing the *reason* — it is no longer "it
      segfaults" but "it is measurably not worth it"
- [ ] Report the `default_chunksize` × `filter_geom` interaction upstream on
      `appelmar/gdalcubes` — at `parallel = 1` the default chunking makes `filter_geom` a
      guaranteed no-op, which is a real observation independent of drift
- [x] The `parallel` arm won outright (2.05× at 4, 2.47× at 8, byte-identical), so it
      shipped in this PR rather than as a follow-up — `dft_stac_cube(parallel =)`
- [x] #48 filed: both frozen cache-key goldens fail on `main`, so the key moved and
      silently orphaned every cached cube and fetch. Found by this work, unrelated to it

**Not doing:** the capability probe (Phase 2 as originally planned), the `filter_geom` code
path, the `Remotes:` entry, and the cache-key change. All were downstream of a gate that
failed. `Remotes:` was in any case a weaker guarantee than it reads as — it is ignored by
`install.packages()` and satisfied by any already-installed `Suggests` copy.

## Validation

- [x] Tests pass (`devtools::test()`); `devtools::document()` output read for unexpected `.Rd` writes
- [x] The replaced smoke test is confirmed RED against a stubbed all-NA cube
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, with the Phase-1 table in the archive README's
      Measurement section

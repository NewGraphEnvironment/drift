# Findings — Categorical breakpoint detection: sustained switch vs flicker across the annual class series (#9)

## Issue context

## Context

`dft_rast_consensus()` (#8) computes per-pixel mode across classified rasters. This works well for filtering single-year misclassification noise, but has a fundamental limitation: it can't distinguish noise from real change.

## The problem

A pixel that transitions Trees → Rangeland in 2022 looks like this across a 2021-2023 window:

| Year | Class |
|------|-------|
| 2021 | Trees |
| 2022 | Rangeland |
| 2023 | Rangeland |

Mode = Trees (2/3 if tied, or Rangeland 2/3 depending on direction). The consensus either misses the real change or requires the post-change class to dominate the window before it registers.

A 3-year window needs 2+ years of the new class. A 5-year window needs 3+. Real change is slow to detect; noise filtering improves.

## What has landed since this was filed (revised 2026-09-05)

Two of the three axes on which "is this change real" can be asked now exist in drift, and the body below is rewritten around the one that does not:

| axis | question | shipped |
|---|---|---|
| spectral, continuous | did the vegetation signal actually drop, and when? | `dft_rast_break()` / `dft_rast_trend()` (#30) — BFAST on a Sentinel-2 index cube |
| spatial, geometric | is this patch the shape of a registration artifact? | `dft_transition_artifact()` (#44) — width, boundary-hugging, reciprocal pairs |
| **temporal, categorical** | across the annual class series, is this a sustained switch or flicker? | **not built — this issue** |

The BFAST / LandTrendr discussion originally here is resolved: #30 built that pipeline, and it is the *spectral* complement, not something to duplicate. What #30 cannot do is run on classified inputs alone, and what #44 cannot do is see time at all — a boundary-hugging sliver that is Rangeland in every year but one is noise, one that is Rangeland in every year since 2020 is real, and the geometry is identical.

## Proposed solution: categorical breakpoint detection

IO LULC annual v02 gives seven labelled years (2017–2023). For each pixel, scan the class sequence for a **sustained transition**: class A for N consecutive years, then class B for M consecutive years, and nothing else. Report, per pixel:

- `break_year` — the first year of B, or `NA` if the series never settles (flicker) or never changes (stable)
- `from` / `to` — A and B as the same `from * 1000 + to` codes `dft_rast_transition()` uses, so `dft_transition_vectors()` and `dft_transition_artifact()` work on the result unchanged
- `n_before` / `n_after` — N and M; confidence is `min(N, M)`
- `n_flips` — how many class changes the series contains (1 for a clean switch, more for flicker); the `A/B/A/B/A` pixel is 4 flips and no break

A 2017 -> 2023 two-epoch comparison then splits into: pixels with a clean break (real, dated), pixels that differ between the two epochs but flicker in between (label noise — exactly the borderline pixels the trajectory vignette reads as "an outline with no red"), and pixels that differ only because 2017 or 2023 is itself the odd year out.

This is the missing categorical-only route to real change, and it is the correction path too: a per-pixel "corrected" series is the sustained classes with the flicker years overwritten — a mode filter that preserves a real break instead of averaging it away, which is exactly what `dft_rast_consensus()` (#8) cannot do.

### Weighted mode — deprioritised

The original recommendation was a weighted mode on `dft_rast_consensus()`. It is cheap, but it answers a weaker question (which class dominates recently) and still cannot say *when* a pixel changed or distinguish a clean switch from flicker. Keep it only if the breakpoint scan turns out too expensive at scale; the scan is one pass over an n-year stack, so that is unlikely.

## Acceptance

- Synthetic 7-year fixtures: clean switch at each possible year, flicker, stable, and a series where the last year alone differs — each classified as designed.
- Output codes interoperate with `dft_transition_vectors()` and `dft_transition_artifact()` without conversion.
- Measured on the BULK floodplain (the seven `classified_*` years are two downloads away: see drift#44's archive README): what share of the 4,625 ha of 2017 -> 2023 change is a clean break, and what share flickers.
- Documented in the land-cover vignette beside `patch_area_min` and the geometric tags, as the third leg.

Relates to #8 (temporal mode filter this generalises), #30 (spectral route), #44 (spatial route), #31 (labelling spectral breaks with categories).


## Plan-mode exploration (2026-09-05)

- **The BULK STAC item `bulk_co_ff04` carries only `classified_2017/2020/2023`**, not the
  seven years the issue body claims (queried live at images.a11s.one). The scale run has to
  fetch 2017:2023 for the `floodplain` asset polygon via `dft_stac_fetch()`.
- ~~`terra::app()` probes `fun` with a plain numeric vector, then a small matrix~~ — **wrong,
  and the opposite is the trap** (code-check round 1, terra 1.9.34, `selectMethod("app",
  "SpatRaster")`): `app()` first tries `apply(chunk, 1, fun)` — one R call per CELL — and
  falls back to `fun(chunk)` only when that errors. A `fun` that tolerates a bare vector
  therefore runs per cell: measured 360,013 calls / 6.96 s vs 2 calls / 0.12 s on a
  600 x 600 x 7 stack (57x). `fun` must *refuse* a non-matrix input. Chunks always arrive
  as matrices (`readValues(mat = TRUE)`), including single-cell ones.
- **`terra::crosstab()` drops the NA column unless `useNA = TRUE`**, and returns labels once
  cats are set — compute the summary before `set.cats()`.
- `app()` writes `FLT4S` by default; `INT2S` overflows at class code 33 (`33 * 1000 + 33 >
  32767`) and terra writes NA with a *warning*, breaking ESA WorldCover (codes 10-100) silently
  (round 1). Now `INT4S` + `COMPRESS=LZW`, with the overflow warning promoted to an abort.
- `dft_transition_vectors()` / `dft_transition_artifact()` need a single-layer factor raster
  whose first cats column is the id and whose label column is `transition`
  (`R/dft_transition_vectors.R:65-71`, `R/dft_transition_artifact.R:207-223`), hence the
  split return (`$raster` = transition layer, `$breaks` = the four evidence layers).
- `dft_rast_consensus()` aligns geometry by an in-memory resample; `dft_rast_transition()`
  does no alignment. `max.col(chg, "first")` on a logical matrix returns 1 on all-FALSE rows
  and NA on NA rows, both masked by `n_flips == 1`.
- Bundled extdata rasters are ~16 KB each; four more years cost ~65 KB.
  `data-raw/example_aoi.R` needs bcfishpass + a DEM for the AOI step, so the extension is a
  separate fetch-only script building the cube view from the bundled 2017 tile's extent.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Invariant test: interior-NA pixel gave transition `NA` where `dft_rast_transition()` gives `2003` | Design decision: the transition layer is `NA` only where an endpoint is `NA`; an interior `NA` blanks the four evidence layers and reports `status = NA` in the summary. Keeps `$raster` identical to the two-epoch comparison. |
| `s[s$status == "break", ]` returned NA rows once `status` could be `NA` | `%in%` in the tests and the benchmark script |
| `expect_equal(..., info = yr)` errored inside the failure path (`info` must be character), so a restored bug reported as ERROR not FAIL | `info = as.character(yr)`; restore-the-bug then reads 8 failed / 98 passed |
| Code-check round 1: `scan()` ran once per cell (see the corrected `app()` note above); INT2S overflow; a different projected CRS stacked by cell position with only a warning; multi-layer elements died in `names<-` | `if (!is.matrix(v)) stop()`; INT4S + LZW + overflow handler; `terra::same.crs()` guard; `nlyr == 1` guard; tests for each |
| Code-check round 2: the overflow abort fires from `writeValues()` before `writeStop()`, leaving a partial output file that `on.exit` skipped because `out_file` was kept off the cleanup list; the vectorised-path guard had no test (restore stayed green at 113) | `out_file` stays on the cleanup list until each return; scan closure hoisted to `break_class_scan(n, years)` and its vector refusal pinned directly, plus a stranded-file test |
| Code-check round 3 (mechanism + 19-row enumeration of every terra call): `app()` infers output shape from a test chunk of `min(ncol, 13)` cells and reads a 5-column return on a 5-column raster as transposed — silent scrambling, 0 warnings; the stranded-file test aborted before `out_file` existed, so it passed for nothing | pad a 5-column stack by one NA column (`extend` -> scan -> `crop`), 4/5/6-column test against `dft_rast_transition()`; stranded-file test now drives a real INT4S overflow (code 3e6) |
| Code-check round 4 (scoped to the pad fix): `levels<- NULL` leaves the colour table, and `extend()` writing the padded stack made GDAL warn twice on every 5-column call | strip `coltab` too; `expect_no_warning` test |
| BULK run 1: peak RSS 16.3 GB during the scan (#44's whole pipeline peaked at 10.7 GB). Probe on 7 x 16M in-memory cells: `deepcopy` +1.7 GB, `rast(list)` +2.4 GB, `app()` default chunking +4.4 GB (R-side chunk matrices); `steps = 4` cut the app share to +1 GB | stack first and strip levels/coltab on the stack (one copy, caller unmutated — pinned), `wopt$steps = ceiling(ncell / 1e7)` |
| BULK run 1 stalled in the benchmark script's own `cat_fun`, which tolerated a bare vector — the round-1 per-cell path, reproduced in the script that measures it | `if (!is.matrix(v)) stop()` there too; killed and relaunched |
| Code-check round 5 (scoped to the stack-first strip): `coltab<-` on a stack strips layer 1 only, and the caller-unmutated test could not go red because terra's `levels<-`/`coltab<-` deepcopy before stripping — only `set.cats(NULL)` mutates in place | levels stripped in place per layer with `set.cats(layer = i, value = NULL)` (no copy; the test now guards placement); colour tables stripped per layer only on the pad path, where the stack is written |
| BULK probe: all seven fetched inputs are in memory (`inMemory()` TRUE), and `rast(list)` copies in-memory sources — the function added +12.6 GB (9.0 -> 21.6 GB) however the levels were stripped | in-memory inputs are spilled to LZW INT4S temp files (deepcopy -> strip -> `writeRaster`) before stacking, a one-layer transient instead of a seven-layer copy |
| After the spill, file-backed integer sources arrive in `scan()` as an INTEGER matrix, and `code * 1000L` overflowed in R (NA + "NAs produced by integer overflow") before terra's writer — the overflow test went green-by-accident-free: it FAILED (no abort, NA transitions) | encoding computed in double; closure test on an integer matrix with code 3e6 |
| Code-check round 6: `resample()` of a factor input writes a RAT sidecar (`.tif.aux.xml`) beside the intermediate that `unlink(files)` missed; the spill's `set.cats(NULL)` was unpinned (it prevents the same sidecar); the spill transient was two copies (explicit `deepcopy` + `coltab<-`'s own) | `strip_copy()`: `coltab<-` first (the one copy), `set.cats(NULL)` in place on it, used before both `resample()` and the spill write; cleanup also unlinks `<file>.aux.xml`; tempdir-count pins on the resample and spill tests; a file-backed classified series pins the stack strip |
| BULK stage trace (file-backed inputs, 192M cells): `app()` with 9.6M-cell chunks peaked ~10 GB above a 0.3 GB floor; crosstab flat at ~7 GB | chunk target lowered to 2.5e6 cells (`steps`) |
| Code-check round 7: with `files` empty, `paste0(character(0), ".aux.xml")` is `".aux.xml"` and the exit handler unlinked that name in the caller's working directory on the file-backed-first + CRS-mismatch path (the zero-length `paste0` row in `code-check.md`); the cats half of `strip_copy()` is redundant with the cleanup | `if (length(files))` guard, pinned by planting `.aux.xml` in a temp cwd and driving that error; comments say the cats strip is belt and braces |
| `sf::st_read(floodplain.gpkg)` auto-selected `co_ff02` (344.7 km2), not the `co_ff04` (386.5 km2) #44 measured | `layer = "co_ff04"` pinned in the benchmark script; first fetch killed and restarted |

## Phase 1-2 measurements (2026-09-05)

- 106 assertions in `test-dft_rast_break_class.R`; full suite 802 pass / 0 fail / 13 skip.
- Restore-the-bug on `n_after` (`n - idx + 1L` instead of `n - idx`): 8 failed / 98 passed via
  `testthat::test_file()`; fix restored: 106 / 0.
- `devtools::document()` also regenerated `man/dft_transition_artifact.Rd`, whose *Memory*
  section had been updated in the #44 roxygen without the Rd being rebuilt on main — a
  pre-existing stale artifact, carried along here.
- Bundled-tile extension: refetched 2017 reproduces `example_2017.tif` with 0 differing cells
  and 0 NA mismatches; 2018/2019/2021/2022 written at ~6 KB each (LZW) on the identical grid.

## Review spend

Seven `/code-check` rounds plus one plan-mode reviewer on this commit — past the ~5-per-task
bound in `karpathy.md` §6, deliberately: rounds 2-7 each found a defect inside the previous
round's fix (the stopping rule's continue condition), all of one class. Round 3 delivered the
enumeration; rounds 4-7 were scoped to the change since the previous round. Round 7's fix is a
one-line guard on a documented mechanism with a direct pin, and was not sent for an eighth.

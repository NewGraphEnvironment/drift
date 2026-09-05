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
- **`terra::app()` probes `fun` with a plain numeric vector, then a small matrix, then the
  real chunk; a 1-row chunk drops to a vector** (Plan-agent measurement, terra 1.9.34).
  `fun` must open with `V <- matrix(V, ncol = n)` and use `drop = FALSE`.
- **`terra::crosstab()` drops the NA column unless `useNA = TRUE`**, and returns labels once
  cats are set — compute the summary before `set.cats()`.
- `app()` writes `FLT4S` by default (3.4 GB for 169M x 5); `wopt = list(datatype = "INT2S")`.
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

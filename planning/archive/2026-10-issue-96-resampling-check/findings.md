# Findings — resampling typo silently becomes "near" (#96)

## Issue context

## Problem

`resampling` goes straight into `gdalcubes::cube_view()`. The mechanism is the same one that #92 hit for `aggregation`: gdalcubes 0.7.5 reads a value it does not know as a default and raises no error. For `resampling` that default is `"near"`.

Measured by round-tripping values through `cube_view(...)$resampling`:

```
bilinear -> bilinear
bilinaer -> near
foo      -> near
Bilinear -> bilinear     # case-insensitive
cubic    -> cubic
```

So `dft_stac_cube(aoi, resampling = "bilinaer")` returns a nearest-neighbour cube and caches it under the misspelt key, with no warning. The three callers are `stac_cube_assemble()` (`R/dft_stac_cube.R`, used by the cube and the composite) and `fetch_extent_to()` (`R/dft_stac_fetch.R`).

## Ask

Validate `resampling` the same way #92 validates `aggregation`:

- Build the allowed set by measuring the `cube_view()` round trip, not from `?cube_view`.
- Match case-insensitively.
- Run the check before any network call.
- Pin the set with a behaviour test.

Found by the `/code-check` round-3 review on #92.


## Round-trip measurement (gdalcubes 0.7.5, 2026-10-01)

`cube_view(...)$resampling`:

- fixed points: near bilinear cubic cubicspline lanczos average mode max min med q1 q3
- aliases: mean -> average, median -> med
- fallback to near: bilinaer foo sum rms gauss none first nearest nearest_neighbor cubic_spline
- case-insensitive: Bilinear -> bilinear, MODE -> mode, Q1 -> q1

## Plan review (Plan agent, 2026-10-01) — folded in

No blockers. Acted on: (1) `mean`/`median` error claimed gdalcubes "does not know" them — it renames them; added an `aliases` hint ("reads as "average" ... use "average""). (2) The checks inside `stac_cube_assemble()` and `fetch_extent_to()` had no test; added direct calls. (3) `fetch_extent_to()` never had #92's `aggregation_check()`; added beside `resampling_check()`. (4) Refusing `mean`/`median`, which used to give correct output, is a behaviour change: release as 0.21.0, not 0.20.1. (5) Comment rationale corrected: case variants already give one output two keys, so the reason for refusing aliases is one documented spelling per method, not key uniqueness.

Refactor regression caught by hand: with the shared helper, the error header read `cube_view_choice_check(...)`; `call = rlang::caller_env()` restores `aggregation_check()` / `resampling_check()`.

## Mutation table (scratch copy, 2026-10-01)

| mutant | red |
|---|---|
| M0 unmutated | 0 |
| M1 drop check at top of `dft_stac_cube()` | 1 |
| M2 drop check at top of `dft_stac_fetch()` | 1 |
| M3 drop check at top of `dft_stac_composite()` | 1 |
| M4 drop check in `stac_cube_assemble()` | 1 |
| M5 drop resampling check in `fetch_extent_to()` | 1 |
| M6 drop aggregation check in `fetch_extent_to()` | 1 |
| M7 widen set with `nearest` | 4 |
| M8 lower-case the return | 5 |
| M9 drop the alias hint | 1 |
| M10 narrow set (drop `q3`) | 2 |

## Errors Encountered

| Error | Resolution |
|-------|------------|
| First mutation probe reported M1-M3 surviving | probe summed `failed` only; testthat records an uncaught error in `error`. Summed both: all killed |

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

## Errors Encountered

| Error | Resolution |
|-------|------------|

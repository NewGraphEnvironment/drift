# Review — docs/NEWS/notes for #96, round 1

Reviewer scope: staged diff `diff_p2.patch` (NEWS.md, `@param resampling` in
dft_stac_cube.R / dft_stac_fetch.R / dft_stac_composite.R, man/*.Rd,
inst/notes/gdalcubes-pc-gotchas.md). Every claim checked against the code or a
fresh measurement, not against the other documents.

## Clean

No factual defect, stale number or Rd breakage found.

## What was verified

- **Round trip, gdalcubes 0.7.5** (`cube_view(srs = "EPSG:32609", ..., resampling = r)$resampling`,
  run fresh): `near bilinear cubic cubicspline lanczos average mode max min med q1 q3`
  all come back unchanged; `mean -> average`, `median -> med` (and `Mean`, `MEDIAN`
  likewise); `sum rms gauss nearest none "" bilinaer -> near`; `Q1 -> q1`,
  `MODE -> mode`, `Bilinear -> bilinear`. Every value the NEWS entry, the roxygen and
  the notes name matches what was measured.
- **Allowed set**: `.cube_view_resamplings` is exactly the twelve listed, in the same
  order, in all three `@param` blocks, the NEWS bullet and the notes.
- **Aliases**: `resampling_check("mean")` / `("median")` / `("Mean")` refuse with
  class `drift_bad_resampling` and name `"average"` / `"med"`, as NEWS and the
  roxygen say.
- **Hashed as given / no key moves**: `cube_view_choice_check()` returns `x`
  unchanged; all three entry points assign `resampling <- resampling_check(resampling)`;
  `stac_cache_key()`, `stac_cube_cache_key()` and `stac_composite_cache_key()` hash
  that value. So no accepted value's key moves, and `mean -> average` does change the
  key (re-stream once), as NEWS says.
- **"Before any network call, and again at both `cube_view()` call sites"**: entry
  checks sit after only `check_gdalcubes()` (and, in composite, the static
  `dft_stac_config()` lookup, which makes no request). There are exactly two
  `gdalcubes::cube_view()` calls in R/ — `stac_cube_assemble()` and
  `fetch_extent_to()` — and both now call `resampling_check()`.
- **"`aggregation` is now also checked where `dft_stac_fetch()` builds each
  `cube_view()`, tiled or not, as it already was in cube/composite"**: at d6bbaed
  `aggregation_check()` was in `stac_cube_assemble()` (shared by cube and composite)
  but not in `fetch_extent_to()`; `fetch_extent_to()` is used by both the untiled and
  tiled fetch branches. Claim holds.
- **Old caches / `dft_cache_clear()`**: the cache scheme dir is unchanged in this
  release, keys are opaque hashes, and `dft_cache_clear()` defaults to
  `scheme = "all"`. Claim holds.
- **Rd sync**: `devtools::document()` in a copy of the staged tree reproduces
  `man/` byte-for-byte (`/usr/bin/diff -r` clean). `tools::checkRd()` reports only
  the pre-existing non-ASCII notes (standalone checkRd without the package encoding),
  nothing from this diff.
- **Notes "pin test stays a plain round trip"**: tests/testthat/test-dft_stac_cube.R
  L832-850 round-trips each allowed value and each alias through `cube_view()`.
- DESCRIPTION is still 0.20.0; the 0.21.0 NEWS header is the accepted deliberate bump.

## Observations, not defects

- NEWS "Old caches" speaks of a *misspelt* `resampling`; files cached under `sum`,
  `rms`, `gauss`, `nearest` or `none` are in the same state (near data, now
  unreachable). The wording is loose rather than wrong.

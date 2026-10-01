## Outcome

`resampling` went straight into `gdalcubes::cube_view()`, which reads a value it does not know as `"near"` with no error, so `resampling = "bilinaer"` returned and cached a nearest-neighbour cube. `resampling_check()` now refuses anything outside the measured set at the three entry points (`dft_stac_cube()`, `dft_stac_fetch()`, `dft_stac_composite()`) and at both `cube_view()` call sites (`stac_cube_assemble()`, `fetch_extent_to()`, which also gained the #92 `aggregation_check()` it lacked). Both checks share `cube_view_choice_check()`. The honoured aliases `mean`/`median` are refused with the spelling to use. The plan review moved the release from 0.20.1 to 0.21.0, because refusing those two breaks calls that used to give correct output. Learned: an assertion meant to pin the fallback (`"near"`) could not fail, because the same string is the first member of the allowed set printed in the headline (code-check round 1). And a mutation probe that summed testthat's `failed` column alone reported three killed mutants as survivors, because an uncaught error is counted under `error`.

## Measurement

gdalcubes 0.7.5, `cube_view(...)$resampling` round trip, 2026-10-01:
- Twelve fixed points: `near bilinear cubic cubicspline lanczos average mode max min med q1 q3`.
- Two aliases: `mean -> average`, `median -> med`.
- `near` fallback for `sum rms gauss none first nearest nearest_neighbor cubic_spline "" bilinaer foo`.
- Case is ignored.

Mutation table: 11 of 11 killed (`findings.md`), covering each of the five call sites, a widened or narrowed set, a lower-cased return, the alias hint, and a wrong fallback name. `devtools::test()`: FAIL 0, PASS 1508, SKIP 16. BULK scale test not run: the change is argument validation before any read, so it has no memory or runtime surface.

Closed by: PR (see `/gh-pr-push`)

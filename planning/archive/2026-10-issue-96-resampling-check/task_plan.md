# Task: resampling typo silently becomes "near" in dft_stac_cube / dft_stac_composite / dft_stac_fetch (#96)

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

## Measured set (gdalcubes 0.7.5, `cube_view(...)$resampling` round trip, today)

Fixed points (survive unchanged) — **the allowed set, 12 values**:
`near bilinear cubic cubicspline lanczos average mode max min med q1 q3`

Fall back to `near`: `bilinaer foo sum rms gauss none first nearest nearest_neighbor cubic_spline ""`
Case-insensitive: `Bilinear -> bilinear`, `MODE -> mode`, `Q1 -> q1`.

**Aliases (decision, recommendation taken):** `mean -> average` and `median -> med` are honoured but *renamed*. Allow only the fixed points and refuse the aliases, naming the canonical spelling in the set. Reason: one spelling per method, so `"mean"` and `"average"` cannot cache the same output under two keys, and the pin test stays `honoured(r) == r`. `nearest` is refused too — it lands on `near` only via the fallback.

## Phase 1: Validate `resampling` (tests first)

- [x] Tests in `tests/testthat/test-dft_stac_cube.R`, beside the #92 blocks (~L758):
  - `resampling_check()` accepts the 12; returns mixed case **as given** (`"Bilinear"`, `"Q1"`) — cache keys hash it, lower-casing would move them
  - refuses `"bilinaer" "foo" "nearest" "sum" "rms" "none" "mean" "median" "" NA_character_ NA c("near","bilinear") character(0) 1 NULL` with class `drift_bad_resampling`; message names the set and the refused value
  - behaviour pin: every `.cube_view_resamplings` member round-trips through `cube_view()` unchanged, and `"bilinaer"` comes back `"near"` (so the test fails if gdalcubes ever starts refusing, or the set drifts)
  - before-network: `dft_stac_cube`, `dft_stac_fetch` (io-lulc), `dft_stac_composite` with bad `resampling` error with `drift_bad_resampling` under the existing `stac_cube_items`/`stac_items_paged` → `stop("reached the network")` mocks, and the cache dir stays empty (composite case in `test-dft_stac_composite.R` ~L300)
- [x] `R/dft_stac_cube.R`: add `.cube_view_resamplings` (comment carrying the measurement + alias/nearest rationale) and `resampling_check()`. Factor the body of `aggregation_check()` into one private helper (`cube_view_choice_check(x, arg, allowed, fallback, class)`) that both call, so the two messages and the as-given return cannot drift apart; `aggregation_check()`'s signature and existing tests unchanged
- [x] Call sites, each beside the existing `aggregation_check()`:
  - top of `dft_stac_cube()`, `dft_stac_fetch()`, `dft_stac_composite()` (before any network call)
  - `stac_cube_assemble()` — last point before `cube_view()` (covers cube + composite)
  - `fetch_extent_to()` (`R/dft_stac_fetch.R:609`) — last point before `cube_view()` for fetch
- [x] `devtools::test()` green; restore-the-bug check: drop the call in `dft_stac_cube()` and confirm the before-network test goes red

## Phase 2: Docs and NEWS

- [x] `@param resampling` in `dft_stac_cube.R`, `dft_stac_fetch.R`, `dft_stac_composite.R`: list the set, say anything else is refused because gdalcubes reads it as `"near"`; keep fetch's "`near` for categorical" note; `devtools::document()`
- [x] `inst/notes/gdalcubes-pc-gotchas.md` L220: replace the "#96" forward pointer with the measured set, the aliases and the decision
- [x] `NEWS.md` new `# drift 0.21.0` entry (version moved from 0.20.1 on plan review: refusing `mean`/`median` is a behaviour change); 0.20.0 sentence pointing at #96 left as history
- [x] lintr clean on touched files (vignette and `dup` lints predate this branch)

## Phase 3: Release

- [ ] Version bump to 0.21.0 in `DESCRIPTION` as the final branch commit ("Release v0.21.0 (#96)")

## Not doing

- BULK scale test: no raster computation changes, only argument validation before any read — no memory/runtime surface. Will say so in the PR body.
- No cache-key change: values are hashed as given, defaults (`"bilinear"`, `"near"`) unaffected; existing key-pin tests cover this.

## Verification

`devtools::test()` (pins above), `devtools::document()`, `pkgdown::check_pkgdown()` (no new exports, sanity), manual: `dft_stac_cube(aoi, resampling = "bilinaer")` errors immediately with no network.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

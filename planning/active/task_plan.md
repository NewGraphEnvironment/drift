# Task: Categorical breakpoint detection: sustained switch vs flicker across the annual class series (the temporal leg of change QA) (#9)

`dft_rast_consensus()` (#8) computes per-pixel mode across classified rasters. This works well for filtering single-year misclassification noise, but has a fundamental limitation: it can't distinguish noise from real change. A pixel that transitions Trees -> Rangeland in 2022 is voted back to Trees by a 2021-2023 mode. Two of the three axes on which "is this change real" can be asked now exist in drift — spectral (`dft_rast_break()`, #30) and geometric (`dft_transition_artifact()`, #44); this issue builds the third, temporal-categorical one: across the annual class series, is a pixel a sustained switch or flicker?

Function name approved by the user in plan mode: **`dft_rast_break_class()`**. Return shape: `list(raster = <factor transition layer, from*1000+to>, breaks = <break_year, n_before, n_after, n_flips>, summary = tibble)`, so `result$raster` feeds `dft_transition_vectors()` / `dft_transition_artifact()` verbatim. No threshold parameter — raw measurements, the caller composes.

## Phase 1: Fixtures and failing tests
- [ ] `tests/testthat/helper-break_class.R` — build a named 7-layer list (2017:2023) from a cells x 7 code matrix on the synthetic 4-class table from `helper-artifact.R`; 10 m EPSG:32609 grid
- [ ] `tests/testthat/test-dft_rast_break_class.R` — one pixel per case: clean switch at each of the six possible break years, stable, flicker (`A/B/A/B/A/B/A`, 6 flips), settling flicker (`A A B A B B B`, 3 flips, no break), last year alone differs (`n_after == 1`), first year alone differs (`n_before == 1`), NA in one year -> NA everywhere
- [ ] Tests for `summary`: status/`break_year` rows, `n_cells` reconcile to the pixel count, `pct` sums to 100
- [ ] Invariant test: `$raster` identical in values and levels to `dft_rast_transition(x, from = "2017", to = "2023")$raster`
- [ ] Interop test: `dft_transition_vectors($raster, changes_only = TRUE)` then `dft_transition_artifact()` run without conversion
- [ ] Input guards: single SpatRaster, < 2 layers, names not parseable as years, unsorted names (sorted, not error), geographic CRS, differing extents (resampled)
- [ ] Datatype/streaming: output written to file (`terra::inMemory()` FALSE), layer names as documented

## Phase 2: Implement `dft_rast_break_class()`
- [ ] `R/dft_rast_break_class.R` per Design above; `app()` `fun` starts with `matrix(V, ncol = n)` and uses `drop = FALSE` (terra probes with a bare vector and 1-row chunks)
- [ ] Summary computed with `crosstab(useNA = TRUE)` before `set.cats()`; `wopt = list(datatype = "INT2S")`
- [ ] Roxygen with runnable `@examples` on the bundled 7-year series (lands in Phase 3 — write against 2017/2020/2023 first, extend after)
- [ ] `devtools::document()`; read the output; `git diff NAMESPACE` shows exactly one new export
- [ ] `@seealso` cross-links on `dft_rast_consensus()`, `dft_rast_break()`, `dft_transition_artifact()`, `dft_rast_transition()`
- [ ] `lintr::lint_package()` clean on new files; Phase 1 tests green

## Phase 3: Bundled seven-year series
- [ ] `data-raw/example_years_extend.R` — fetch IO LULC 2018, 2019, 2021, 2022 for the bundled AOI on the exact grid of `inst/extdata/example_2017.tif` (cube view from its `ext()`, `dx = dy = 10`, EPSG:32609), mask to `example_aoi.gpkg`, write `INT1U`; re-fetch 2017 as a control and assert it equals the bundled file
- [ ] Commit `inst/extdata/example_2018/2019/2021/2022.tif`; update the `data-raw/example_aoi.R` header comment and CLAUDE.md `inst/extdata` size line
- [ ] Examples, vignette load chunk and one test use the full 2017:2023 series; pin the bundled-tile numbers (n clean breaks, n flicker, share of 2017 -> 2023 change area) in a test

## Phase 4: Scale run on the BULK floodplain
- [ ] `data-raw/benchmark_break_class_bulk.R` — download the `floodplain` asset of `bulk_co_ff04`, `dft_stac_fetch(years = 2017:2023, tile_size = ...)`, `dft_rast_classify()`, `dft_rast_break_class()`, then `dft_transition_vectors(changes_only = TRUE)`; RSS sampler (`ps -o rss=` every 2 s) and timings to `data-raw/logs/benchmark_break_class/`
- [ ] Record: share of the 2017 -> 2023 change area (the 4,625 ha from #44) that is a clean break vs flicker vs endpoint-odd-year; break-year distribution; runtime and peak RSS; compare against the #44 numbers
- [ ] Fix anything the run finds before the PR (the #44 precedent)

## Phase 5: Documentation
- [ ] New section in `vignettes/land-cover-change.Rmd` after *Geometric Artifacts*: the third leg — run on the 7-year series, table of clean/flicker/endpoint shares of the 2017 -> 2023 change, per-patch break fraction via `terra::zonal()` joined to the artifact-tagged patches, one map of `break_year`
- [ ] `NEWS.md` entry (0.14.0 heading; version bump itself is the final commit per conventions) with the bundled-tile and BULK measurements
- [ ] CLAUDE.md pipeline snippet: add the `dft_rast_break_class()` line under the categorical block
- [ ] Correct the issue body's "seven `classified_*` years are two downloads away" claim (edit, not comment)

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

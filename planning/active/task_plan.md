# Task: Accuracy assessment for change maps: stratified sampling and error-adjusted area with CIs (Olofsson et al. 2014) (#81)


drift produces land-cover change maps (`dft_rast_transition()`, `dft_rast_break_class()`, `dft_transition_vectors()`), but it has no way to say **how right they are**. Every area it reports is the mapped area, and mapped area is a biased estimator whenever the map has errors. For a change map it is usually badly biased, because a single wrong label on either date manufactures a transition.

The standard remedy is a stratified sample of reference labels and estimators that correct area for the measured error. That method is generic to any classified map, so it belongs in drift, not in each driver. floodplains#93 is the first consumer: NECR floodplain change, fire/harvest attribution, and wetland change.

## Design

Revised 2026-09-28 after the plan review (`planning/active/review-plan.md`). The review found two blockers, both confirmed or folded in here: B1 (the `freq()` step reports labels while `readValues()` reports codes on factor strata; measured) and B2 (sizing assumed strata = map classes).

A new `dft_accuracy_*` family, one function per file:

| function | input → output |
|---|---|
| `dft_accuracy_sample(strata, n, seed, map = NULL)` | strata SpatRaster → `list(points = sf, strata = tibble, design = list)` |
| `dft_accuracy_estimate(labels, strata, level = 0.95, fpc = TRUE)` | label table + `$strata` → `list(matrix, accuracy, area, stratum)` |
| `dft_accuracy_size(weights, s_h, se_target, allocation, n_min)` | stratum weights + per-stratum SD + target SE → total n and allocation |
| `dft_accuracy_labels(labels, strata)` | validates the label contract; returns it invisibly or errors naming the fault |

**Sampler.** `terra::spatSample()` and `terra::freq()` are not used: `spatSample()` is not stable across versions, and `freq()` returns labels on factor rasters and rounds floats.
1. **Pass 1** reads the layer in explicit row chunks with `readStart`/`readValues`, capped at about 1e7 cells, with `on.exit(readStop())`. It counts `N_h` per integer code (`tabulate`/`table`), and on the same pass refuses non-integer values and `nlyr != 1`.
2. **Draw:** each stratum gets its own sub-stream: `set.seed(<derived from seed and code>, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")`, then `sample.int(N_h, n_h)`. `sample.int` keeps its prefix when n grows, and per-stratum seeds mean that raising one stratum's n, or adding a stratum, leaves every other draw unchanged. So a pilot extends into a superset of itself. The caller's `.Random.seed` is restored, or removed if it was absent. `seed` is required.
3. **Pass 2** runs the same chunked reader, turning ranks into cell ids. It ends by asserting the cumulative counts equal `N_h`.
4. **Allocation** is equal per stratum (a scalar) or a named vector. A named vector that omits a non-empty stratum is refused. Where `n_h ≥ N_h` the stratum is a **census** (`n_h = N_h`) and a message names it; tiny transition strata are normal (the bundled tile has a 3-cell one).
5. **Output:**
   - Factor strata keep the integer code as `stratum` and carry `levels()` as `stratum_label`.
   - Points are cell centres with `point_id = "<stratum>_<draw index, 5 digits>"` in draw order, which is independent of total n. They also carry `stratum`, `stratum_label` and `cell`, with no `x`/`y` columns: the geometry is authoritative.
   - Optional `map =` takes a SpatRaster or a named list of years on the same grid (`terra::compareGeom`) and extracts `map_class` (or `map_<year>`) at each cell.
   - `$strata` carries `stratum`, `stratum_label`, `n_cells`, `area` (ha), `weight` and `n`.
   - `$design` records the seed, RNG kinds, R and terra versions, allocation, and the grid dims, extent and CRS.
   - `dft_check_crs()` guards area. NA cells are outside the population.
   - Raster strata only. The roxygen gives the polygon recipe: rasterise in memory (not `filename =` with an integer datatype, which writes the background as 0, not NA), then `terra::mask()` to the map's NA footprint.

**Label contract**:
- required: `point_id`, `stratum`, `map_class`, `ref_class`
- optional: `confidence`, `reviewer`, `use` (`"accuracy"` / `"training"` / NA)

`dft_accuracy_labels()` refuses:
- `ref_class` NA (nonresponse is the caller's decision, and a silent drop changes `n_h`)
- duplicate `point_id`
- a stratum absent from `$strata`
- a `$strata` row with `N_h > 0` and no labels
- any other `use` value

Its roxygen states that filtering by `confidence` changes the design. For change accuracy, `map_class` is the transition code and `ref_class = ref_from * 1000 + ref_to`, the `dft_rast_transition()` id scheme. Union targets (tree loss, the unattributed residual) are "recode, then estimate": the SE of a union is not the sum of the SEs.

**Train/test.** `use == "training"` rows are refused with their count. Including them is the harm: points that trained a classifier cannot measure it. Reusing a non-random subset of accuracy points for training biases the estimate too. The documented-split option in the issue is not provided. That meets "at minimum a flag"; an `n_train` split at draw time is a possible follow-up.

**Estimators** (Stehman 2014 general form: stratified means of indicator variables, weighted by `N_h`):
- The error matrix is long format over the union of map and reference classes, with estimated proportions. When strata ≠ map classes, the row totals are **estimated**, not the known `W_i`; the roxygen says so.
- OA, UA and PA with SEs. UA and PA are ratio estimators; PA is NA where `p̂_·j = 0`.
- Adjusted area per reference class = `A_total · p̂_·j`, with SE and a Wald CI, `z = qnorm(1 − (1 − level)/2)`. The interval is not truncated at 0, and the roxygen says so.
- `fpc = TRUE` applies `(1 − n_h/N_h)`, so a census stratum contributes zero variance. With `fpc = FALSE` the estimator is algebraically Olofsson eq. 2–11; the Olofsson pin runs that way.
- `$stratum` reports per-stratum `n_h`, `N_h`, agreement mean and SE, and the SD of the OA indicator and of each reference-class indicator. The sizer consumes it.
- A stratum with `n_h = 1` is refused (its variance is undefined), unless it is a census and `fpc = TRUE`.

**Sizing.** The primary form is `n = (Σ W_h S_h)² / SE_target²`, with `S_h` per **stratum** taken from a pilot's `$stratum` for a named quantity: OA or a class's area proportion. `ua =` is a convenience that holds only when strata = map classes, where `S_i = sqrt(U_i(1−U_i))` (Olofsson eq. 13). There are two allocations: `"equal"`, and `"proportional_min"` (Olofsson §5.1.1).

### Phase 1: Reference values in hand
- [ ] User adds the Olofsson 2014 and Stehman 2014 PDFs (decided at the plan gate). Until then, Phases 2–4 code and non-published tests proceed, and the published-value pins wait.
- [ ] Transcribe the worked examples into `tests/testthat/helper-accuracy.R`, each value cited to its page and table number, with the equation numbers verified against the PDF and both papers checked for errata
- [ ] `findings.md`: the estimator equations with numbers, and a check of the Olofsson example by hand arithmetic (deforestation 21,158 ha is reproducible from the row counts; confirm against the PDF)

### Phase 2: Estimator (tests first)
- [ ] `test-dft_accuracy_estimate.R`, published: the Olofsson example (error matrix, UA/PA/OA with SEs, adjusted areas with CIs), run with `fpc = FALSE` and **absolute** tolerance at the published precision; the Stehman 2014 example (strata ≠ map classes). The fixture expands counts to per-point rows with base `rep()`
- [ ] Must-fail: run the **estimator** with equal `n_cells` on the Olofsson counts and assert it differs from the published values
- [ ] Census oracle (independent truth, no PDF needed): map = 2017 and "reference" = 2023 on the bundled tile, with the true error matrix and areas from `terra::crosstab`. Run about 500 stratified draws under map-class strata and under a changed/stable split; check bias ≈ 0, empirical SD ≈ mean SE, and CI coverage ≈ level. Skippable if slow
- [ ] Perfect labels (`ref = map`) give UA = PA = OA = 1, SE = 0, and adjusted area equal to mapped area. Recoding to a 2-class union gives an SE that is not the sum of the SEs
- [ ] Contract refusals: training rows, NA `ref_class`, duplicate ids, an unknown stratum, a stratum with no labels, `n_h = 1`. A reference-only class appears in the matrix, and PA is NA at `p̂_·j = 0`
- [ ] `R/dft_accuracy_estimate.R` + `R/dft_accuracy_labels.R`. Freeze the `$strata` and `$stratum` shapes here
- [ ] Restore-the-bug check: remove the weights from the estimator and confirm the published-value tests go red

### Phase 3: Sampler (tests first)
- [ ] `test-dft_accuracy_sample.R`:
  - golden `point_id`s and cells for a seeded draw on `example_2017.tif`, with an allocation the tile can satisfy (classes 4 and 9 have 2 cells)
  - chunk invariance: identical results at row chunks 1, 7, 50 and full, matching brute-force `which()`
  - pilot extension: the first 30 per stratum at n = 30 are identical at n = 50, and adding a stratum leaves the others unchanged
  - RNG: an existing seed is unchanged, an absent one is still absent, and a caller's L'Ecuyer kind is restored
  - the factor transition raster: codes plus labels, joined correctly
  - census with message
  - within-stratum uniformity (chi-square)
  - weights sum to 1 and areas match `dft_rast_summarize()`
  - refusals: lonlat, non-integer, multi-layer, and a named allocation that omits a stratum
  - NA cells are never drawn
  - `map =` extraction, including a grid-mismatch refusal
- [ ] `R/dft_accuracy_sample.R`
- [ ] Sampler → estimator integration: draw, fake labels from a reference raster, estimate (covered by the census oracle once both exist)
- [ ] Scale test on BULK: `classified_2017.tif` and its `dft_rast_transition()` factor output (the #93 input), with an RSS sampler. Record pass-1 and pass-2 time and peak RSS in the PR body

### Phase 4: Sizing
- [ ] `test-dft_accuracy_size.R`: reproduce Olofsson §5.1.1's sample-size example (n and allocation); the `s_h` form from a pilot `$stratum` agrees with the `ua` form when strata = map classes; edge cases (UA = 1, a zero weight)
- [ ] `R/dft_accuracy_size.R`

### Phase 5: Docs and release
- [ ] A runnable `@examples` block on every function (the estimator example uses Olofsson's published counts; the sampler uses the bundled tile with a satisfiable allocation)
- [ ] `devtools::document()`, `lintr::lint_package()`, `pkgdown::check_pkgdown()`. `_pkgdown.yml` has no `reference:` index, so the check cannot catch an omission; it stays that way (out of scope)
- [ ] NEWS.md, then version 0.19.0 as the final commit
- [ ] CLAUDE.md Core Pipeline: add the accuracy block, and correct the bundled tile's size (314 x 326, not 600 x 600)
- [ ] Update the floodplains#93 body's "What lives where" table: the `map =` argument, the `ref_class` composition recipe, the pilot-extension rule, and per-stratum sizing

No vignette. One made with fabricated labels would illustrate a number nobody measured. The worked example belongs in floodplains#93 once real labels exist.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

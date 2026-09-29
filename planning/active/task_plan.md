# Task: Accuracy assessment for change maps: stratified sampling and error-adjusted area with CIs (Olofsson et al. 2014) (#81)


drift produces land-cover change maps (`dft_rast_transition()`, `dft_rast_break_class()`, `dft_transition_vectors()`), but it has no way to say **how right they are**. Every area it reports is the mapped area, and mapped area is a biased estimator whenever the map has errors. For a change map it is usually badly biased, because a single wrong label on either date manufactures a transition.

The standard remedy is a stratified sample of reference labels and estimators that correct area for the measured error. That method is generic to any classified map, so it belongs in drift, not in each driver. floodplains#93 is the first consumer: NECR floodplain change, fire/harvest attribution, and wetland change.

## Design

A new `dft_accuracy_*` family, one function per file (noun-first, so the family autocompletes together):

| function | input → output |
|---|---|
| `dft_accuracy_sample(strata, n, seed, n_min)` | strata SpatRaster (integer codes) → `list(points = sf, strata = tibble)` |
| `dft_accuracy_size(weights, ua, se_target, …)` | stratum weights + target / pilot user's accuracies → total n, plus allocation |
| `dft_accuracy_estimate(labels, strata, …)` | label table + `$strata` → `list(matrix, accuracy, area)` with SEs and CIs |
| `dft_accuracy_labels(labels)` | validates the label contract; returns it invisibly or errors naming the fault |

**Sampler, stable across terra versions.** `terra::spatSample()` is not stable across versions, so it is not used. Instead:
1. Count cells per stratum with `terra::freq()` (C++, streaming).
2. Draw within-stratum ranks with base `sample.int(N_h, n_h)` under a local seed. The caller's RNG state is saved and restored, and `sample.kind = "Rejection"` is set explicitly.
3. Resolve each rank to a cell id in one block-wise pass (`terra::readStart` / `readValues` by row block, cumulative counts per stratum).

The result depends only on cell order, which is row-major and fixed, and on base R's RNG. Memory stays bounded at BULK's 169M cells. Points are cell centres (`terra::xyFromCell`) and carry `point_id` (stable, zero-padded, stratum-then-rank order), `stratum`, `cell`, and `x`/`y`. `$strata` carries `stratum`, `n_cells`, `area` (ha), `weight` (`n_cells / Σ n_cells`) and `n`. Other details:
- Allocation is either equal per stratum (`n` as a scalar) or caller-supplied (a named vector). `n_h > N_h` is refused.
- `dft_check_crs()` guards the area.
- `NA` cells are outside the population.
- Raster strata only. Polygon strata are rasterised first with `terra::rasterize()` onto the map grid, documented in the roxygen. It is one line, and it keeps the grid (and so the weights) the caller's explicit choice.

**Label contract** (columns the caller's table must carry; drift stores nothing):
- required: `point_id`, `stratum`, `map_class`, `ref_class`
- optional: `confidence`, `reviewer`, `use` (`"accuracy"` / `"training"`)

**Train/test.** `dft_accuracy_estimate()` refuses any row with `use == "training"` and names the count. It has no silent drop: dropping those rows would bias the design, because the training rows were not drawn as part of the probability sample.

**Estimators** (Stehman 2014 general form: per-stratum sample means of indicator variables, weighted by `N_h`):
- An area-weighted error matrix of estimated proportions p̂_ij.
- Overall, user's and producer's accuracy. UA and PA are ratio estimators, with their variances from Stehman eq. 26–28.
- Error-adjusted area per reference class = `A_total · p̂_·j`, with its SE and a 95% CI (`z = 1.96`, as the argument `level`).
- When strata = map classes, these are algebraically Olofsson eq. 2–11. A test asserts that equality on the paper's table.

**Sizing.** Olofsson eq. 13: `n = (Σ W_i S_i / S(Ô))²` with `S_i = sqrt(U_i(1−U_i))`. Two allocation helpers: `"equal"`, and `"proportional_min"` (proportional with `n_min` per rare stratum, Olofsson §5.1.1). Pilot variance comes in as `ua` taken from a pilot's `dft_accuracy_estimate()$accuracy`, documented with an example.

### Phase 1: Reference values in hand
- [ ] User adds the Olofsson 2014 and Stehman 2014 PDFs (decided at the plan gate). Until then, Phases 2–4 code and non-published tests proceed, and the published-value pins wait.
- [ ] Transcribe the worked examples into `tests/testthat/helper-accuracy.R`, each value cited to its page and table number
- [ ] `findings.md`: the estimator equations with numbers, and a check of the Olofsson example by hand arithmetic (deforestation 21,158 ha is reproducible from the row counts; confirm against the PDF)

### Phase 2: Estimator (tests first)
- [ ] `test-dft_accuracy_estimate.R`: Olofsson Table 8/9 (the error matrix, UA/PA/OA with SEs, and the adjusted areas with 95% CIs, to the published precision); the Stehman 2014 example (strata ≠ map classes); a must-fail test showing unweighted accuracy differs from the published values on the Olofsson example; `use == "training"` refused; a stratum with n_h = 1 (variance undefined) refused; a class absent from the reference handled
- [ ] `R/dft_accuracy_estimate.R` + `R/dft_accuracy_labels.R` (the contract validator, which the estimator calls)
- [ ] Restore-the-bug check: remove the weights from the estimator and confirm the published-value tests go red

### Phase 3: Sampler (tests first)
- [ ] `test-dft_accuracy_sample.R`: pinned golden cell ids for a seeded draw on `example_2017.tif`; the same seed gives an identical draw; the caller's `.Random.seed` is untouched; within-stratum uniformity (chi-square over a large draw); weights sum to 1 and areas match `dft_rast_summarize()`; `n_h > N_h`, a lonlat raster and a non-integer raster are refused; NA cells are never drawn; the block-wise resolver agrees with a brute-force `which()` on the small tile
- [ ] `R/dft_accuracy_sample.R`
- [ ] Scale test on BULK `classified_2017.tif` (169M cells) with the RSS sampler; record the time and peak RSS in the PR body

### Phase 4: Sizing
- [ ] `test-dft_accuracy_size.R`: reproduce Olofsson §5.1.1's sample-size example (n and allocation) from the paper; edge cases (UA = 1, a zero weight)
- [ ] `R/dft_accuracy_size.R`

### Phase 5: Docs and release
- [ ] A runnable `@examples` block on every function (the estimator example uses Olofsson's published counts; the sampler uses the bundled tile)
- [ ] `devtools::document()`, `lintr::lint_package()`, `pkgdown::check_pkgdown()` (the new exports go in the reference index)
- [ ] NEWS.md, then version 0.19.0 as the final commit
- [ ] CLAUDE.md Core Pipeline: add the accuracy block
- [ ] Update the floodplains#93 body's "What lives where" table if the delivered API differs from what it assumes

No vignette. One made with fabricated labels would illustrate a number nobody measured. The worked example belongs in floodplains#93 once real labels exist.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

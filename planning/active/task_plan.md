# Task: Validate classified input and support arbitrary factor rasters in transitions (#19)

`dft_rast_transition()` silently produces wrong results when passed raw integer rasters that weren't classified via `dft_rast_classify()`. The `code_lookup` maps integer codes to class names using the default class table, so:

- If codes happen to match (e.g., IO LULC codes), results look correct but the user never explicitly classified
- If codes don't match (custom rasters, climate data, habitat types), class names are `NA` with no error

As drift generalizes beyond land cover (climate zones, habitat classification, soil types, any categorical raster), this becomes more likely. A user with a pre-classified raster from another source has no reason to run `dft_rast_classify()` first.

## Context

`dft_rast_transition()` and `dft_rast_break_class()` both decode codes with
`dft_class_table(source)`, and `source` defaults to `"io-lulc"`. So a raster's own factor levels are
never read. A probe on the bundled tile (read-only, 2026-09-30) shows two silent wrong results on `main`:

- A pair classified with `remap = list(Vegetation = c("Trees", "Rangeland"))` carries the level
  `2 = Vegetation`, but the summary reports `Trees -> Trees` (10,140 cells), because the IO LULC table
  labels code 2 `Trees`. `from_class = "Vegetation"` would match nothing.
- Raw integers that are not IO LULC codes (`r * 1L + 100L`) give `NA -> NA` rows with no error.

What you decided at the gate:
- **`source = NULL` becomes the default.** Labels resolve in this order: `class_table`, then an explicit
  `source`, then the input's factor levels, and otherwise an error that names `dft_rast_classify()` and
  `terra::set.cats()`.
- **`dft_rast_break_class()` gets the same rule** through one shared helper. That keeps its documented
  identity with `dft_rast_transition(first, last)$raster`.

This unblocks #31.

## Design

The new internal helper is `transition_class_table(rasters, class_table, source, fn)` in
`R/transition_class_table.R`. It returns a tibble `code, class_name` with the same columns
`apply_codeset()` and `code_lookup` already use, so nothing downstream of the lookup changes.

1. `class_table` supplied: use it as it is.
2. Otherwise, `source` supplied: `dft_class_table(source)`.
3. Otherwise every raster is a factor (`terra::is.factor(r)[1]`, layer 1 as in `dft_rast_classify()`):
   take the union of `terra::levels(r)[[1]]`, meaning the id and the **active** category, so a published
   RAT works. The union is needed because `dft_rast_classify()` keeps only the codes present in each
   year, so the years' level sets differ.
   - If one code carries different labels in different years, error with the code and both labels.
4. Otherwise error. The message names the raster(s) that are not factors, `dft_rast_classify()`,
   `terra::set.cats()`, and `class_table =` / `source =`.
5. Any resolved code outside the integers 0–999 is an error: the encoding `from * 1000 + to` cannot hold
   it.

Reading the levels is metadata only, with no pass over the cells. The codes are still read from the cells
through the existing `* 1L` (for `dft_rast_transition()`) and `strip_copy()` / `set.cats(NULL)` (for
`dft_rast_break_class()`).

## Phase 1: Failing tests
- [x] `tests/testthat/test-transition_class_table.R`: the precedence order (`class_table` > `source` >
      levels > error), the union across years, the conflicting-label error, the mixed factor/raw error,
      the code > 999 error, and the active category of a multi-column RAT
- [x] `test-dft_rast_transition.R`: raw integers with no `class_table`/`source` error, and the message
      names `dft_rast_classify` and `set.cats`
- [x] `test-dft_rast_transition.R`: a factor with custom codes (100+) and no `class_table` takes its
      labels from the levels, and `from_class`/`to_class` filter by level name
- [x] `test-dft_rast_transition.R`: a remap-classified pair reports `Vegetation -> …` (the probe above
      as a regression test)
- [x] `test-dft_rast_transition.R`: `class_table` and an explicit `source` each beat the levels;
      caller rasters keep their levels after the call
- [x] `test-dft_rast_break_class.R`: the same no-label error; a remapped series gives the same
      `$raster` levels as `dft_rast_transition()` on its endpoints
- [x] Confirm these fail on the current code for the reason each one names

## Phase 2: Implementation
- [x] `R/transition_class_table.R`: the helper, with a roxygen `@noRd` block
- [x] `dft_rast_transition()`: `source = NULL`, call the helper, pass its tibble to `apply_codeset()`
      and `code_lookup`
- [x] `dft_rast_break_class()`: the same change
- [x] Roxygen for both: `@param class_table` and `@param source` state the precedence; add a
      `@details` paragraph on labels read from factor levels; add an `@examples` line on a factor with
      custom levels and no `class_table`
- [x] Update call sites that pass **raw** integers without `source` so they pass one (existing tests
      already pass `class_table`; check `data-raw/benchmark_transition_oom.R` and the vignettes)
- [x] `devtools::document()`, full `devtools::test()`, `lintr::lint_package()`,
      `pkgdown::check_pkgdown()`
- [ ] **PARKED 2026-09-30. Open before Phase 2 can close** (see `review-plan.md` and `review-round1.md`):
  - [ ] B1: error when an observed from/to code has no label (after the freq in transition, the
        removed raster, and after the crosstab in break_class). No extra pass over the cells.
  - [ ] B2: `dft_rast_consensus()` builds its levels from the union of all inputs' levels (a regression
        this branch introduced; reproduced). Add a 3-raster test.
  - [ ] Round 1: one label on two codes across rasters must be refused (breaks `from_class != to_class`)
  - [ ] Round 1: character `class_table$code` fails with an opaque `round()` error (a regression)
  - [ ] Round 1 / G1: the unlabelled message says "not a factor" for a zero-level factor, and the plural grammar is wrong
  - [ ] G2 drop NA labels; O1 test a resampled factor in break_class; A1 doc that break_class reads every year
  - [ ] code-check rounds 2+ on the fixes

## Phase 3: Scale check and docs
- [x] BULK pair (`classified_2017.tif` / `classified_2023.tif`, which carry the published RAT), with no
      `class_table`: check that the labels read from the RAT match the `source = "io-lulc"` labels, and
      `/usr/bin/time -l` on `main` against the branch (expected: no change, since this is metadata only)
- [x] Record the numbers in `findings.md`
- [ ] Update the CLAUDE.md core pipeline snippet if needed (factor levels are the default source of
      labels)

## Phase 4: Release
- [ ] NEWS.md 0.20.0: the default of `source` changed; raw integers now need `class_table` or
      `source`; the remap mislabel is fixed; factor rasters from any source work directly
- [ ] Bump DESCRIPTION to 0.20.0 as the final commit

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Critical files
- `R/dft_rast_transition.R` (lookup at ~L95, `apply_codeset()` at the end)
- `R/dft_rast_break_class.R` (lookup at L158–161; levels at L295)
- `R/dft_rast_classify.R`: the `is.factor(x)[1]` convention and `strip_copy()` context
- `tests/testthat/helper-artifact.R`: `artifact_class_table()` / `artifact_class_rast()` fixtures
- New: `R/transition_class_table.R`, `tests/testthat/test-transition_class_table.R`

## Verification
`Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`. Rerun the probe above: it
should show `Vegetation`, and raw non-IO codes should error. Rebuild the `land-cover-change` vignette
(its inputs are classified factors, so the output should be unchanged). Run the BULK timing from Phase 3.

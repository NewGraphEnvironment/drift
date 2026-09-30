# Task: dft_rast_classify() returns empty levels when its input is already a factor (#91)

`dft_rast_classify()` returns a raster with **zero levels and no colour table** when its input is already a factor. It raises no error and no warning.

```r
r  <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
cl <- dft_rast_classify(r * 1L, source = "io-lulc")
again <- dft_rast_classify(cl, source = "io-lulc")
nrow(terra::cats(again)[[1]]); terra::has.colors(again)   # 0  FALSE
```

The cause is `present_codes <- terra::unique(x)[, 1]` (`R/dft_rast_classify.R:44`). On a factor, `terra::unique()` returns the **labels** (`"Water"`, `"Trees"`, ...), not the codes. `class_table$code %in% present_codes` then matches nothing, so `ct` is empty and both setters are given empty tables.

This is the ordinary case, not a contrived one. The published floodplain rasters are factors: `stac-floodplains-bc/bulk_co_ff04/classified_2017.tif` carries a RAT with a `class_name` column and a palette. Classifying one of those, for example to apply a `remap =`, returns a factor raster with no categories. Found in #89's BULK scale check, where the output had neither levels nor colours on `main` and on the branch alike.

## Context (from plan)

`dft_rast_classify()` takes its present codes from `terra::unique(x)[, 1]` (`R/dft_rast_classify.R:44`).
terra's `unique()` reads the raw codes (`x@pntr$unique()`) and then turns them into labels with
`get_labels()`. So on a factor it returns `"Water"`, `"Trees"`, and so on. `class_table$code %in%`
those labels matches nothing, and the output has no levels and no colours. No error or warning is raised.
This is the ordinary case for the published floodplain rasters, which carry a RAT.

Probed on terra 1.9.50:
- A classified raster reclassified gives 0 levels and `has.colors` FALSE. Confirmed.
- **The `remap =` path does not have this bug when a group matches.** `terra::classify()` drops the
  factor, so `unique()` sees codes: 6 levels, correct. **It does have the bug when no remap group
  matches.** `rcl` is then NULL, `classify()` is skipped, `x` stays a factor, and levels come back empty.
- The raw codes can be recovered from a copy with its levels stripped. There is already a helper
  for this: `strip_copy()` (`R/dft_rast_break_class.R:361`). `coltab<-` makes one copy, and then
  `set.cats(NULL)` strips the levels in place on that copy.

## Approach

At the top of the single-raster path, before the remap step, add
`if (terra::is.factor(x)) x <- strip_copy(x)`. Everything after that sees plain codes: `unique()`,
`apply_remap()` (including the case where nothing matches), and the setters. `coltab<-` then makes
a second copy, but only for factor input. Non-factor input keeps the one-copy path from #89 unchanged.
The input's own RAT and palette are replaced by `class_table`. That is the existing contract,
and it is documented in `@param x`.

## Phase 1: Failing tests (`tests/testthat/test-dft_rast_classify.R`)
- [ ] Reclassifying a classified raster returns the same `cats()` and `coltab()` as the first pass
- [ ] A raster carrying its own RAT gets levels and colours from `class_table`. The raster is
      written to a tempfile tif and read back, so it is file-backed. Its RAT labels differ from `class_table`.
- [ ] Factor input with a matching `remap =` keeps working. Factor input with a non-matching `remap =`
      gives a warning and still returns levels.
- [ ] The caller's factor raster is not modified: its levels and colours are still its own after the call
- [ ] Confirm that each new test fails on current code

## Phase 2: Fix (`R/dft_rast_classify.R`)
- [ ] Strip factor input with `strip_copy()` before remap; update the copy-count comment
- [ ] Update `@param x` to say factor input is accepted and its RAT is replaced by `class_table`;
      run `devtools::document()`
- [ ] Full `devtools::test()` green; `lintr::lint_package()` clean

## Phase 3: Scale check (BULK, per CLAUDE.md)
- [ ] `/usr/bin/time -l` on `bulk_co_ff04/classified_2017.tif`, which is a file-backed factor with a RAT.
      Compare `main` with the branch, checking peak RSS, wall time, and that the output has levels and colours.
- [ ] The same for an in-memory factor input: the in-memory classified output fed back in.
      Record the cost of the extra copy.
- [ ] Put the numbers in `findings.md`; the script goes in scratchpad or `data-raw/` if worth keeping

## Phase 4: Release bookkeeping
- [ ] NEWS.md `# drift 0.19.2` entry, with numbers derived from the scale run
- [ ] `/planning-archive`, then bump the version to 0.19.2 as the final commit, then `/gh-pr-push`.
      Tag the PR with `Relates to NewGraphEnvironment/sred-2025-2026#16`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

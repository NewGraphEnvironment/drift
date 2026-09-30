# Review round 1: #19 staged diff + HEAD tests (transition_class_table)

Reviewer: code-check round 1 subagent, 2026-09-30. The repo was not modified; the probes ran
read-only via `pkgload::load_all()`, and one comparison ran against `git archive main` in the scratchpad.

## Verdict

No blocking bugs. There are three low-severity findings, all probed. None breaks an existing caller.

## Findings

- **[severity: fragile]** R/transition_class_table.R:77-85 (`transition_levels()`, duplicate check):
  the guard catches one code carrying two labels across the rasters. It does not catch the reverse,
  one label carrying two codes, and that is the same scheme-mismatch signal. Probe: raster `a` has
  levels `1 = "Trees"`, raster `b` has `2 = "Trees"`, and every cell changes 1 -> 2.
  `dft_rast_transition(list(a=a,b=b),"a","b")$summary` returns a single row, `Trees -> Trees`, 4 cells,
  with no error. The change is real at the code level (`code_from != code_to`, so `patch_area_min`
  treats it as change), but anything that compares labels reads it as stable.
  `dft_break_category()` (R/dft_break_category.R:167 uses `s$from_class != s$to_class`) would put
  those pixels in the stable categories, and the `@examples` idiom `from_class != to_class` drops them.
  This only happens when the rasters come from inconsistent schemes. The new levels path is what now
  admits such input with no table, though. If the intent is to refuse mismatched schemes, check
  `duplicated(all_lv$class_name)` across different codes as well, at least across rasters.

- **[severity: fragile]** R/transition_class_table.R:35-36 (`bad <- ... lookup$code != round(lookup$code) ...`):
  this is a regression for a `class_table` whose `code` column is character (for example a table read
  with all-character col types). On `main`, `dft_rast_transition(list(a=r17,b=r20),"a","b",
  class_table = tibble(code = as.character(1:11), class_name = letters[1:11]))` returns a correct
  19-row summary. With the from/to filters it failed in `subst()`. On this branch every call fails
  with `Error in round(lookup$code): non-numeric argument to mathematical function`. That error names
  neither the argument nor the rule. Either coerce with `suppressWarnings(as.numeric(...))` and let the
  0-999 check report the result, or refuse non-numeric `code` with a message that names `class_table$code`.

- **[severity: fragile]** R/transition_class_table.R:66-71 (unlabelled-raster message): the sentence
  claims `... carries none (not a factor raster)`. The branch also catches a factor with zero levels
  (`is.null(l) || nrow(l) == 0`), and the test `"a factor with zero levels counts as unlabelled"`
  confirms `is.factor()` is TRUE there. The message then tells the user their factor raster is not a
  factor. Probe output: ``f() needs class labels, and `x`, `y` carries none (not a factor raster)``.
  The test asserts only `"dft_rast_classify"`, so it can't see the false claim (see
  "An assertion that matches an interpolated value cannot see the claim around it"). The same message
  also reads "`x`, `y` carries" for the plural case, which is cosmetic. Suggest "(no factor levels)".

## Checked, not flagged

- **Callers of the `source` default change.** Every in-repo caller passes `dft_rast_classify()`
  output or an explicit `class_table`/`source`:
  - R/ examples
  - vignettes (land-cover-change.Rmd lines 58/456 classify first)
  - tests (test-dft_transition_vectors, test-dft_accuracy_sample:139, test-dft_rast_consensus:106,
    test-dft_check_crs, test-dft_map_interactive:293, helper-artifact `make_transition`)
  - data-raw (vignette_data_break, disturbance_compare, break_class_groups x4,
    benchmark_break_class_bulk, benchmark_break_category_bulk)

  `dft_rast_consensus()` output keeps the first input's levels (filtered to present codes), so it
  resolves. data-raw/benchmark_transition_oom.R builds factor rasters labelled `class_<code>`; those
  labels now replace the IO LULC names. That is harmless for a memory benchmark.
- **Downstream repo.** floodplains/scripts/floodplain_lcc/03_lulc_classify.R classifies first.
  inspect_sieve_thresholds.R reads the published `classified_YYYY.tif` with no `source`. I verified
  that the published BULK COG (`/vsicurl/.../bulk_co_ff04/classified_2017.tif`) reads as
  `is.factor() == TRUE` with active category `class_name` (Water..Rangeland), so it resolves through
  the levels path unchanged.
- **File-backed factor round trip.** For `writeRaster()` then `rast()`, both GTiff and COG, the RAT is
  read back with the same levels. The summaries are identical to the in-memory result, and
  `dft_rast_break_class()` on file-backed input runs clean.
- **New `@examples` block.** It runs. The IO LULC codes present in example_2017/2020 are
  1,2,4,5,7,9,11, all covered by the `1:11` reclass, so no unlabelled code leaks into the labels.
  `set.cats()` there acts on the `classify()` result, never the caller's raster.
- **Label path is metadata only.** It uses `terra::is.factor()` and `terra::levels()` and reads no
  cells. The new code makes no `set.cats()` call on caller rasters. In `dft_rast_break_class()`,
  labels are read after the year sort and before the stack strip, which is correct.
- **`levels()[[1]]` gives id + active category.** The multi-column/activeCat test covers this and passes.
- **Scan-overflow test rewrite (test-dft_rast_break_class.R).** It still reaches the INT4S overflow
  handler: the plain rasters hold 3e6, and the table lists only 1 and 2.

## Note (pre-existing, not a regression)

The 0-999 guard validates the lookup's codes, not the raster's cell values. That is correct given the
no-cell-read constraint. A plain raster holding an undeclared code of 1000 or more (for example an
undeclared UInt16 nodata of 65535) still mis-decodes silently in `dft_rast_transition()`:
`1*1000 + 65535` decodes as `66 -> 535`, labelled `NA -> NA`. `dft_rast_break_class()` only catches
values past INT4S. The new @details sentence "Class codes must be whole numbers in 0-999" reads as
enforced, but it is enforced only for declared codes. This behaved the same on `main`.

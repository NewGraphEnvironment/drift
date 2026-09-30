# Plan review (Plan agent, read-only; written here by the parent) — #19

Returned after Phase 1 was committed and Phase 2 was staged, so it reviewed the code as well as the plan.

## Blockers
- **B1** Only the label *table* is validated, never the codes actually in the cells. On the branch,
  a factor whose levels list only `1 = Water` over IO cells, or raw `r + 100L` with `source = "io-lulc"`,
  still gives `NA -> NA` rows with no error. Fix: after the freq/crosstab, error when an observed from/to
  code has no label (both functions, plus the `removed` raster). No extra pass over the cells.
- **B2** `dft_rast_consensus()` copies only `x[[1]]`'s levels, and classify keeps only the codes present
  per year, so a winning code absent from year 1 has no level. On main the io-lulc default hid this; on
  the branch it gives NA labels. **Confirmed** by probe (3 rasters, `NA -> A` row). Fix: union of levels.

## Gaps
- G1 empty-levels message wording ("not a factor" is wrong there; grammar with several names). Needs a test.
- G2 an NA label passes through as `class_name NA`. Drop those rows.
- G3 label column type and name vary (numeric, `id.1`, `value/category`, written->read). Reading by
  position with `as.character()` is right; pin it with a test, including a factor written to disk and read back.
- G4 a multi-column RAT does not survive a local writeRaster round trip. The published BULK COG reads
  fine: activeCat 1 = class_name, 9 rows.
- G5 the example's `others = 104` turned NA into Upland. **Already fixed** before the review landed.
- G6 duplicate labels on different codes make label-based and code-based filters disagree. This predates
  the branch (class_table had it too). Document it only.

## Ordering
- O1 break_class reads the levels before the strip (correct). Add a test for a factor on a different grid.
- O2 CRS check first in transition (correct). The plan text said otherwise.
- O3 the Phase 1 "fails on current code" step was run before the implementation (commit 1ded928), so it holds.

## Assumptions
- A1 break_class reads every year's levels, while transition reads only from/to. Document it.
- A2 the 0-999 check applies to every table row, including rows for codes absent from the data. Put it in NEWS.
- A3 no caller passes raw integers without class_table/source. The "update call sites" step is a no-op.
- A4 benchmark_transition_oom labels become `class_N`. Harmless.

## Scope
- dft_map_interactive() still defaults to `source = "io-lulc"`, so levels-labelled transitions get grey
  fallback colours. Follow-up issue.

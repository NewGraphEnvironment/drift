# Progress — Validate classified input and support arbitrary factor rasters in transitions (#19)

## Session 2026-09-30

- Plan-mode exploration; phases approved by user (source = NULL default; break_class included)
- Created branch `19-validate-classified-input-and-support-ar` off main
- Scaffolded PWF baseline from issue #19 with approved phases
- Next: start Phase 1
- Phase 1: failing tests. `test-transition_class_table.R` (the helper does not exist yet); 10 failures
  in `test-dft_rast_transition.R` (no error on raw input, NA labels on a custom factor, `Trees` where
  the level is `Vegetation`); 2 in `test-dft_rast_break_class.R`. Each fails for the reason it names.
  The class_table/source-precedence test passes already, because that part is not new behaviour.

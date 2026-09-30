# Progress — dft_rast_classify() returns empty levels when its input is already a factor (#91)

## Session 2026-09-29

- Plan-mode exploration — phases approved by user ("go all phases")
- Created branch `91-dft-rast-classify-returns-empty-levels-w` off main
- Scaffolded PWF baseline from issue #91 with approved phases
- Next: start Phase 1
- Phase 1: four factor-input tests; 9 assertions red on current code (remap-with-match green, as probed)
- Phase 2: `strip_copy()` on factor input before remap; 50/50 in the file, full suite 1336 pass / 0 fail / 15 skip
- Mutation: replacing `strip_copy()` with in-place `set.cats(x, NULL)` turns 4 assertions red, including both caller-unmodified checks
- Plan review + code-check round 1 both found: `if (is.factor(x))` errors on a multi-layer stack → `is.factor(x)[1]` (main classified layer 1 only; kept). Mutation: dropping `[1]` reddens the new stack test.
- Plan review: strip moved after remap (classify() already reads raw codes), stale #89 comment updated, colour check compares to class_table, active-category test added
- Scale check (Phase 3) numbers in findings.md
- code-check: 3 rounds (round 1: stack error, fixed; rounds 2-3 Clean, round 3 verified NEWS claims against main); full suite 1344 pass / 0 fail / 15 skip

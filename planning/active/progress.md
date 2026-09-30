# Progress — dft_rast_classify() mutates the caller's raster in place (set.cats on the input) (#89)

## Session 2026-09-29

- Plan-mode exploration — phases approved by user
- Created branch `89-dft-rast-classify-mutates-the-caller-s-r` off main
- Scaffolded PWF baseline from issue #89 with approved phases
- Next: start Phase 1
- Phase 1: caller-unmodified test added; red on current code for all three inputs (file-backed, in-memory, list element), 6 failures
- Phase 2: `coltab<-` moved before `set.cats()`; classify tests 32 pass; the Phase 1 red run against the original ordering is the restore-the-bug check
- Full suite `[ FAIL 0 | WARN 0 | SKIP 15 | PASS 1318 ]` (49 s); changed lines lint clean (two pre-existing indentation lints in the remap tests, untouched); `document()` no change

# Progress — Accuracy assessment for change maps (#81)

## Session 2026-09-28

- Plan-mode exploration; phases approved by user
- Created branch `81-accuracy-assessment-for-change-maps-stra` off main
- Scaffolded PWF baseline from issue #81 with approved phases
- Next: Phase 2 estimator code and tests; published-value pins wait on the PDFs (Phase 1)
- Decision: the estimator wraps `mapaccuracy::stehman2014()` (user, 2026-09-28) instead of reimplementing it; plan revised
- Phase 1 done: Olofsson 2014 read from the local Zotero PDF; values in `helper-accuracy.R`; three printed values contradict the paper's own equations (findings). Issue body revised. Stehman 2014 is not needed (mapaccuracy tests it)

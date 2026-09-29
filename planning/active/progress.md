# Progress — Accuracy assessment for change maps (#81)

## Session 2026-09-28

- Plan-mode exploration; phases approved by user
- Created branch `81-accuracy-assessment-for-change-maps-stra` off main
- Scaffolded PWF baseline from issue #81 with approved phases
- Next: Phase 2 estimator code and tests; published-value pins wait on the PDFs (Phase 1)
- Decision: the estimator wraps `mapaccuracy::stehman2014()` (user, 2026-09-28) instead of reimplementing it; plan revised
- Phase 1 done: Olofsson 2014 read from the local Zotero PDF; values in `helper-accuracy.R`; three printed values contradict the paper's own equations (findings). Issue body revised. Stehman 2014 is not needed (mapaccuracy tests it)
- Phases 2–4 code and tests written; code-check rounds 1–2 found 6 defects (fixed), round 3 running; BULK scale run 3.3 s / 0.95 GiB for the sampler; filed #89 (classify mutates input)
- Code-check: 3 rounds. R1: 4 findings (1 bug). R2: 2 (1 bug, 1 inside the R1 fix). R3: 6 (2 bugs, 1 inside the R2 fix); ended by enumerating 29 identity sites, and every fix was mutation-checked
- Phase 5: examples run; NEWS 0.19.0 drafted; CLAUDE.md accuracy block added and tile size corrected (314 x 326); floodplains#93 body updated with the delivered API. Full suite 1289 pass / 15 skip; R CMD check 0 errors, 1 WARNING (non-ASCII in R/dft_stac_fetch.R, already on main, untouched here), 1 NOTE (future timestamps)

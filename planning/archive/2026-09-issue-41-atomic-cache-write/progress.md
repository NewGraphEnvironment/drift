# Progress — corrupt cache trusted as a hit on resume (#41)

## Session 2026-09-02

- Plan-mode exploration; measured the failure directly rather than reasoning from the traceback.
  Found **three** distinct damage shapes, not one — each of which kills an otherwise-obvious design.
- Scanned all 168 files in the real cache: no existing corruption, so no cache-key break needed.
- Found the identical defect in `dft_stac_cube()`; user scoped it into this fix.
- Phases approved by user.
- Plan subagent review returned; probed its three empirical premises rather than adopting them.
  Two refuted (truncated `.tif` does error on open; no PAM sidecar on the cube write shape), one
  confirmed in substance for the wrong reason (arm (c)'s fixture genuinely cannot reach the arm).
  Adopted its two strongest structural points: validate the temp before renaming, and fold the
  cube's read probe into the `global()` scan it already pays for.
- Created branch `41-stac-fetch-atomic-cache-write` off main.
- Scaffolded PWF baseline with approved phases.
- Next: Phase 1 — failing tests for atomic write.

- Phases 1-3: atomic write + three-arm validation on the fetch path. Commit c3c46a4.
  My own tests found two bugs in the first implementation: terra emits a PAM sidecar writing
  `.nc` (I had refuted that having tested only `.tif` — the refutation was over-scoped), and an
  injected probe's warning escaped because the judging lived in the probe rather than the caller.
- Phase 4: same two changes on the cube path, plus the zero-cost whole-file probe folded into the
  `global()` scan `cube_check_nonempty()` already pays for. Commit 30442ed.
- Phase 5: docs, NEWS, version 0.11.0.
- Verification: full suite 522 pass / 1 fail, the failure being the frozen cube-key guardian at
  `test-dft_stac_cube.R:62`, confirmed red on `main` before any of this work (checked via
  `git stash`). Not touched here; needs its own issue.
- Restore-the-defect: new tests confirmed red against `main`'s R sources.
- False-refusal control: 0 of 168 real cache entries refused.
- Lint: the two `no visible global function definition` warnings are the documented
  installed-vs-source artifact — installed drift is 0.8.0 and lacks the new helpers, while
  `stac_cache_key`/`mosaic_tiles` resolve. Clears on reinstall.

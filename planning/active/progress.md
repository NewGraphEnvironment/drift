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

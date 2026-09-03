# Progress — the cache key moved (#48)

## Session 2026-09-03

- Plan-mode exploration. Did not take the issue's diagnosis on trust: measured the key at its own
  pinning commit in today's environment, which localised the cause to `rlang::hash()` rather than
  the sf/PROJ drift the issue suspected. rlang 1.3.0's NEWS states the change outright.
- Established that the passing fetch golden is **not** a control — it was re-pinned after the
  drift; its #36-era contemporary fails too.
- Measured the real cost (~10 s/entry, flat; ~20 min for the whole orphaned set) and found **zero**
  cube entries cached, correcting the "10-30 min per cube" framing I had carried into the first
  draft of the plan from the issue.
- User chose: canonical string + `digest` (not a reduced-risk rlang variant), and a versioned cache
  directory with reporting but no auto-delete.
- User asked whether this helps on the m4, whether rlang needs pinning, and what the penalty is —
  answered from measurement; the answers are in `findings.md` and shaped the plan's scope.
- Created branch `48-frozen-cache-key-goldens-fail-on-main-th` off main.
- Scaffolded PWF baseline with approved phases; Plan review spawned concurrently.
- Next: Phase 1 — failing tests.

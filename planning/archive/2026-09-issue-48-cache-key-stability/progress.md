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

- Plan review returned. Unlike #41's, essentially every empirical claim held when probed — and two
  would have shipped a broken key: `digest(serialize = FALSE)` silently hashes only the first
  element of a character vector, and `sf::st_as_binary()` returns a list so `is.raw()` is FALSE.
  Both are now guarded and both have premise-asserting tests.
- It also caught that the new scheme directory would make a #41 test pass for the wrong reason
  (a corrupt-cube seed at the pre-scheme path becomes a plain cache miss, which reaches the same
  re-fetch stub). Fixed and given an explicit premise.
- Phases 1-3 landed in edfe0ff: canonical string + digest, 16-char keys, `v2/` scheme routed
  through all four path sites including `dft_cache_clear()`.
- Verified: full suite 571 pass / 0 fail (the cube golden that was red on main is now green);
  restore-the-defect produced 8 failures across both files; end-to-end cold 9.8 s -> warm 0.62 s
  with the entry written to `v2/io-lulc/2020_3115935e92e3325e.nc`.
- Corrected my own cost figure: the scheme move supersedes **all 204** entries (1.09 GB), not just
  the 129 the rlang bump orphaned — the key changes regardless, so the 54 post-upgrade entries go
  too. ~34 min if every one is re-fetched, on demand.
- Phase 5: NEWS, docs, version 0.12.0. Corrected the 0.10.0 NEWS line asserting in bold that cube
  caches were unaffected — true of #51, false now.

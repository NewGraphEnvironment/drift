# #48 — the cache key moved, silently orphaning every cached cube and fetch

**Outcome:** cache keys are now a function of content alone — a canonical string hashed by its
bytes with `digest::digest(algo = "xxhash64", serialize = FALSE)` — and entries live under a
versioned scheme directory so a deliberate key change is a migration rather than a silent
orphaning. Released as v0.12.0.

## The diagnosis in the issue was wrong

The issue suspected sf/PROJ drift under `sf::st_as_binary()` and proposed making the key robust to
"the drifting member". There is no drifting member: the cause is `rlang::hash()` itself, which
rlang 1.3.0 rewrote. Its own NEWS says so — *"with this version all hash values will now be
different… you should assume it's always possible for a new version to invalidate existing
hashes."* A fix aimed at the geometry member would have left the real cause untouched and the
outage would have recurred on the next rlang bump.

## Measurement

| what | measured |
|---|---|
| key function at its own pinning commit, run today | reproduces **today's** value, not the pin — so drift's code never moved |
| fetch @ `cf04bfe` (#36) | `79f67b7b9dae` → `68d66c3fbad9` (moved) |
| cube @ `90f9d93` (#38) | `638a2be11fdf` → `45685ccbda33` (moved) |
| fetch @ `fc2e861` (#51) | `2264b5dbef6e` → unchanged (**holds**) |
| rlang 1.3.0 installed | 2026-08-06 — between the two pins |

**The passing golden was not a control.** It holds only because #51 re-pinned it *after* the
upgrade; its contemporaneous #36-era value fails too. Reading its green tick as "the shared members
are fine" was the available wrong inference, and it is what the issue's "FAIL 2" claim (a stale
tree; current `main` was FAIL 1) would have reinforced.

**Cost, measured rather than assumed:** re-fetch is **~10 s per entry and flat in entry size**
(0.05 / 0.12 / 0.36 MB all ~10 s) — the cost is STAC query, signing and COG opens, not bytes. The
issue's "10–30 min per cube" is real for Sentinel-2 but was **not a cost anyone was paying**: that
cache held **zero** cube entries. It remains the forward-looking reason to fix this.

## Wrong turns, kept because they are the evidence

- **I carried the issue's "10–30 min per cube" into my first plan draft without checking whether
  any cubes were cached.** None were. The same unverified-claim-carried-forward mistake the
  conventions warn about, made while correcting someone else's.
- **My first cost extrapolation scaled by megabytes** and produced ~31 hours. The cost is flat in
  size, so the per-MB figure was meaningless. Two points on a curve killed it.
- **I under-counted the migration.** I reported 129 orphaned entries (451 MB) — what the *rlang
  bump* orphaned. The scheme move supersedes **all 204** (1.09 GB), because the key changes
  regardless; the 54 post-upgrade entries go too.
- **A Plan review's claims held, unlike #41's** — and two of them would have shipped a broken key:
  `digest(serialize = FALSE)` silently hashes **only the first element** of a character vector
  (total collision, no warning), and `sf::st_as_binary()` returns a **list**, so the planned
  `is.raw()` branch would never have matched the geometry member. Both verified before adoption.
- **The review also caught that the new scheme directory would make a #41 test pass for the wrong
  reason:** "a corrupt cube cache is re-fetched" seeds a file and asserts the call reaches the
  re-fetch stub — which a plain cache *miss* satisfies equally well. Left alone, the
  corrupt-rejection gate would never have run while the suite stayed green.

## Design decisions worth not re-litigating

- **16 chars, not 12.** A key collision does not crash; it silently serves the wrong raster, and
  nothing downstream detects it. 48 → 64 bits costs four characters and buys 65,536×, and re-keying
  was already being paid for.
- **IEEE-754 bytes, not `sprintf("%.17g")`.** The byte form keeps `NaN` and `NA_real_` apart
  (`is.na(NaN)` is `TRUE`, so any `is.na` sentinel collapses them) and avoids a libc call whose
  exponent formatting is a platform variable — which matters because this repo has **no
  cross-platform CI**, so these goldens are verified on one machine.
- **Type tags per member**, so type collisions are structural rather than resting on call-site
  coercion that is written down nowhere and which the cube key does not even follow.
- **No rlang pin.** rlang is no longer in the key path, so a pin buys nothing and holds back an
  unrelated dependency.
- **Nothing auto-deleted.** `dft_cache_info()` counts superseded entries;
  `dft_cache_clear(scheme = "superseded")` reclaims them when the user chooses.

## Evidence

`findings.md` — the root-cause bisect, the review adjudication, and the cost measurements.
Commits: `edfe0ff` (key + scheme), `b626c37` (docs, NEWS, v0.12.0).

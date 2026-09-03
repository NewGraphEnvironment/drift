# Findings — the cache key moved (#48)

## Root cause: `rlang::hash()`, not sf/PROJ

The issue's prime suspect was `sf::st_as_binary()` output or `sfc` attribute serialization drifting
with PROJ. That is **wrong**. The cause is documented by the vendor, in rlang 1.3.0's own NEWS:

> `hash()` now uses its own walking strategy to make it independent of pecularities of the R
> serialiser. **This does mean that with this version all hash values will now be different.** In
> general we gain stability across versions of R, but may lose some stability across versions of
> rlang. …you should assume it's always possible for a new version to invalidate existing hashes.

So this is not a one-off environment wobble — it is a standing property of the dependency. Every
rlang upgrade silently re-keys every cache entry.

## Evidence

**The code did not change.** `stac_cube_cache_key()` extracted from its own pinning commit
`90f9d93` and run in today's environment yields `45685ccbda33` — identical to HEAD, and not the
pinned `638a2be11fdf`.

**Both historical keys moved; only the post-upgrade one holds.** Recomputed today:

| key | pinned | today | |
|---|---|---|---|
| fetch @ `cf04bfe` (#36) | `79f67b7b9dae` | `68d66c3fbad9` | moved |
| cube @ `90f9d93` (#38) | `638a2be11fdf` | `45685ccbda33` | moved |
| fetch @ HEAD (#51) | `2264b5dbef6e` | `2264b5dbef6e` | **holds** |

**The fetch golden is not a control.** It passes only because #51 re-pinned it *after* the drift.
Reading its green tick as "the shared members are fine" is exactly the wrong inference — the
contemporaneous #36-era value fails too.

**Timeline fits exactly:** rlang 1.3.0 installed 2026-08-06; cube golden pinned 2026-07-11
(before), fetch golden re-pinned 2026-09-01 (after).

**The issue's failure count is stale.** It reports `FAIL 2 | PASS 407`; current `main` is
`FAIL 1 | PASS 522` — only the cube golden. The fetch golden at `test-dft_stac_fetch.R:88` passes.

## Measured cost — smaller than the issue implies

| quantity | measured |
|---|---|
| orphaned entries | 129 of 183 (450.9 MB of 1.1 GB), mean 3.50 MB |
| re-fetch, cold | 0.05 MB → 10.1 s; 0.12 MB → 9.2 s; 0.36 MB → 9.7 s |
| ⇒ per-entry cost | **~10 s, flat** — all fixed overhead (STAC query, signing, COG opens), not bytes |
| whole orphaned set | **≈20 min**, serial, one machine |
| warm cache hit | 1.39 s (includes the #41 validation probe) |

**There are zero cube entries cached.** The entire 1.1 GB is `io-lulc` *fetch* entries. The issue's
"each cube costs 10–30 min to rebuild" describes a cost nobody is currently paying — and I repeated
it in a first draft of the plan without checking, which is the same unverified-claim-carried-forward
mistake the conventions warn about. It stays the *forward-looking* reason to fix this: a Sentinel-2
cube genuinely is that expensive, and the next rlang bump would destroy those silently.

## Cross-machine (the m4 question)

- The fix **does not** avoid a first-run rebuild on a new machine: the cache is machine-local
  (`rappdirs::user_cache_dir("drift")`), so a fresh machine starts empty regardless.
- What it buys is that the filename becomes a function of **content alone** — identical on any
  machine, R version, rlang version, architecture. That makes a cache shareable/rsyncable between
  machines, which today it is not: two machines on different rlang versions compute different names
  for byte-identical content.
- And it ends the recurring invalidation. One more rebuild now (~20 min), then upgrades stop
  re-keying.

**No rlang pin is needed or wanted.** After the fix rlang is not in the key path at all, so a pin
buys nothing for cache stability while holding back an unrelated dependency everywhere else. A pin
is only a workaround for *keeping* `rlang::hash()`, which is the option being rejected.

**How much better is digest, stated honestly.** Not a guarantee-forever. But rlang *explicitly
reserves the right* to change its hash and did so; `digest` implements **published** algorithms
(xxhash64, md5) over bytes we canonicalize ourselves, where a change in output would be a bug
rather than a design decision. The constant-hash control test is what catches even that.

## Sites that construct a cache path

Only four, so the `v2/` scheme has a small blast radius:
`R/dft_cache.R:50` (clear), `R/dft_cache.R:74` (info), `R/dft_stac_fetch.R:162`,
`R/dft_stac_cube.R:250`. Only two `rlang::hash()` call sites:
`R/dft_stac_fetch.R:409`, `R/dft_stac_cube.R:645`.

## Errors Encountered

| Error | Resolution |
|-------|------------|

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

## Plan-review findings, verified by measurement

A `Plan` subagent reviewed the design. Unlike the #41 review, essentially every empirical claim
here **held up** when probed. Verified on digest 0.6.39 / sf 1.1.2 / R 4.5.2:

### Two that would have shipped a broken key

1. **`digest(x, serialize = FALSE)` silently hashes only element 1 of a character vector.**
   ```
   digest(c("a","b"), algo="xxhash64", serialize=FALSE)  ->  d24ec4f1a98c6e5b
   digest("a",        algo="xxhash64", serialize=FALSE)  ->  d24ec4f1a98c6e5b   (identical)
   ```
   No warning, no error. If `cache_key_string()` ever returns length > 1, **every key collapses to
   the hash of its first member** — a total collision, not a probabilistic one. Guarded with
   `stopifnot(is.character(s), length(s) == 1L, !is.na(s))` immediately before the digest call.

2. **`sf::st_as_binary()` returns a `list` of raw vectors, not a raw vector.** `class` is `"WKB"`,
   `typeof` is `list`, `is.raw()` is **FALSE**. My spec said "raw/WKB → hex", so the WKB member
   would have fallen through the `is.raw()` branch into the numeric one and either errored or
   hashed something meaningless. Needs an explicit `is.list()` branch, tested **before** the vector
   branches.

### Numerics: `writeBin` bytes, not `sprintf("%.17g")`

`%.17g` is injective and adequate, but it is a libc call, and:

| value | `%.17g` | `writeBin` hex |
|---|---|---|
| `NA_real_` | `"NA"` | `a20700000000f07f` |
| `NaN` | `"NaN"` | `000000000000f87f` |

`is.na(NaN)` is `TRUE`, so an `is.na()` → `"<NA>"` sentinel collapses the two — a distinction
`rlang::hash` makes today. `writeBin(as.double(x), raw(), endian = "little")` keeps them apart, has
no locale exposure, and reuses the same hex path the WKB member already needs, so the canonicalizer
gets *simpler* rather than more complex. Adopted.

(I did not confirm the review's `-0` claim — my two probes disagreed on it and it is immaterial
here, since no drift key member is ever negative zero. Not relied upon.)

Also: `sprintf("%.17g", TRUE)` is `"1"`, so **logical must be branched before numeric** or `TRUE`
and `1` collide. Confirmed.

### Type tags, because position-and-coercion is an unwritten invariant

Under a plain string scheme, `NULL` collides with the literal `"<none>"`, `NA` with `"<NA>"`,
numeric `10` with character `"10"`, `TRUE` with `"TRUE"`. None of these bite production today —
every member position is type-fixed by coercion at the call site — but that is an invariant held by
convention, nowhere written down, and the cube key does not coerce most of its character members
(`R/dft_stac_cube.R:638-644`). A one-character type tag per member (`s`/`n`/`b`/`x`/`0`) removes the
whole class for one byte. Adopted.

### 12 → 16 characters

12 hex chars is 48 bits; at ~10^6 lifetime keys the birthday collision probability is ~1.8e-3. A
collision here is not a crash — it is **silently serving the wrong raster**, with no detection path
in `cache_hit_ok()`. xxhash64 emits 16 chars natively, so keeping all of them costs four characters
of filename and buys a 65,536× margin. Taken now because the break is already being paid for; it
will not be free again.

This changes `attr(, "cache_key")`, which is a **documented public return value**
(`R/dft_stac_fetch.R:69-71`, `NEWS.md:21`), and the `^[0-9a-f]{12}$` assertions.

### digest is auditably stable — better evidence than I had

digest ships **pinned upstream test vectors** for exactly this call shape
(`inst/tinytest/test_digest.R`): `digest("abc", algo="xxhash64", serialize=FALSE)` must equal
`"44bc2cf5ad770999"`. Reproduced locally on 0.6.39. So digest is locked to the reference algorithm
by its own CI, where rlang explicitly disclaims stability. That asymmetry is the real argument and
belongs in the roxygen. Using digest's own published vector as the control test, rather than an
arbitrary string, so a failure is directly attributable upstream.

`enc2utf8()` confirmed necessary: the same text in UTF-8 vs latin1 hashes differently, and
`enc2utf8()` reconciles them — it removes a spurious distinction rather than losing a real one.

### The versioning plan was under-specified and would have broken two things

- **`dft_cache_clear(source = )` becomes a silent no-op.** `R/dft_cache.R:52` builds
  `file.path(path, source)`, which after the move points at the *orphaned v1* directory. It would
  report success having deleted nothing current — and it is the documented recovery lever. All four
  path-construction sites must route through `cache_scheme_dir()`, and `dft_cache_clear()` gains a
  `scheme` argument so the v1 orphans remain reclaimable.
- **My own #41 test would have gone green for the wrong reason.**
  `test-dft_stac_cube.R` "a corrupt cube cache is re-fetched rather than served" seeds
  `cube_deadbeef0000.tif` at `<cache>/sentinel-2-l2a/`. Once the code reads `<cache>/v2/...`, the
  seed is simply *not found* — a plain cache miss — so the call still reaches the re-fetch stub and
  the assertion still passes, while the corrupt-rejection gate it exists to exercise is never run.
  Exactly the failure class the #41 work was about, introduced by an unrelated change.

### The rlang-independence test does not prove what it claims

After the change drift never calls `rlang::hash`, so mocking it and asserting the key is unchanged
reduces to "code that no longer exists does not affect output". It is still a live *regression*
guard (a reintroduction would fail it), so it stays — but named precisely, and joined by two
stronger pins:

1. **Pin the intermediate `cache_key_string()` output**, not just the digest. If the string pin
   passes and the key pin fails, the hashing layer moved; if the string pin fails, *our inputs*
   moved and the diff names the member. This is the honest version of the goal.
2. **A source assertion** that neither `rlang::hash` nor `serialize(` appears in the key functions'
   bodies — which also catches an accidental `serialize = TRUE` on the digest call, the specific
   regression that would silently re-couple the key to R's serialization version.

### Also adopted

- `NEWS.md:20` states in bold that "**`dft_stac_cube()` caches are unaffected**". This change
  invalidates them; that line needs an explicit correction, not just a new entry beneath it.
- `dir.create()` at both fetch and cube must create the **full** `v2/<source>` path, or
  `cache_write_atomic()`'s sidecar rename fails on the first fetch.
- Confirmed complete scope: exactly two `rlang::hash()` sites, no other `serialize`/`saveRDS` in
  `R/`.
- No `R-CMD-check` workflow exists, so every golden pinned here is verified on one platform only.
  That is a further argument for the byte encoding over `sprintf`, whose `%g` exponent formatting
  could differ under a different libc.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `digest(serialize=FALSE)` on a length-2 vector returns the hash of element 1, silently | `stopifnot(length(s) == 1L)` before the digest call |
| `is.raw()` is FALSE for `sf::st_as_binary()` output (it is a list) | explicit `is.list()` branch, tested first |

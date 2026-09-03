# Task: Frozen cache-key goldens fail on main: the key moved, silently orphaning every cached cube and fetch (#48)

The cache key **is** the cache filename (`cube_<key>.tif`, `<year>_<key>.nc`), so when the hash
moved, every cached entry was silently orphaned — no error, no warning, just "the pipeline got
slower".

**The issue's diagnosis is wrong and the correction changes the fix.** It suspects sf/PROJ drift
under `sf::st_as_binary()`. Measured cause is `rlang::hash()` itself: rlang 1.3.0's NEWS states
"with this version all hash values will now be different" and that any future version may
invalidate hashes again. That makes every rlang upgrade a silent cache-wide outage.

Revised after a Plan review whose empirical claims were probed and **held** — see `findings.md`.
Two of them would have shipped a broken key.

## Phase 1: Failing tests

- [x] Canonicalization contract: `writeBin` byte encoding, `10L` vs `10`, zero-length/`NULL`, `NA` vs `NaN`, logicals
- [x] **Length guard**: `cache_key_string()` must return a length-1 non-NA character (digest silently hashes only element 1 otherwise)
- [x] Collision set: `NULL` vs `"<none>"`, `NA` vs `"<NA>"`, `NaN` vs `NA_real_`, numeric `10` vs `"10"`, `TRUE` vs `"TRUE"`, `c("B08","B04")` vs `"B08,B04"`
- [x] Multi-feature AOI: two feature orderings must key differently
- [x] **Pin the intermediate `cache_key_string()` output** (the honest form of the stability goal)
- [x] Source assertion: no `rlang::hash` and no `serialize(` in either key function
- [x] rlang-independence mock, named as a reintroduction guard rather than a proof of independence
- [x] Control: digest's own published vector `digest("abc", "xxhash64", serialize=FALSE) == "44bc2cf5ad770999"`
- [x] Confirm all fail against current `main`

## Phase 2: `cache_key_string()` + digest in both key functions

- [x] `cache_key_string()` in `R/dft_stac_fetch.R`: **`is.list()` branch first** (WKB is a list, `is.raw()` is FALSE), then raw→hex, logical **before** numeric, numeric→`writeBin` hex, character→`enc2utf8()`, zero-length/`NULL` sentinel
- [x] One-character **type tag** per member (`s`/`n`/`b`/`x`/`0`) so type collisions are impossible by construction rather than by call-site convention
- [x] `stopifnot(is.character(s), length(s) == 1L, !is.na(s))` before the digest call
- [x] `stac_cache_key()` (`R/dft_stac_fetch.R:409`) → `digest::digest(..., algo="xxhash64", serialize=FALSE)`, **16 chars**
- [x] `stac_cube_cache_key()` (`R/dft_stac_cube.R:645`) → same
- [x] Update `^[0-9a-f]{12}$` assertions to 16
- [x] `digest` → Imports in DESCRIPTION
- [x] Every existing "key changes with each parameter" test still passes

## Phase 3: Versioned cache directory

- [x] `cache_scheme_dir(cache_dir, source = NULL)` → `<base>/v2[/<source>]`
- [x] Route **all four** sites through it: `R/dft_stac_fetch.R:162`, `R/dft_stac_cube.R:250`, and **`R/dft_cache.R:52`** (`dft_cache_clear(source=)` would otherwise silently become a no-op on current entries)
- [x] `dft_cache_clear()` gains `scheme = c("current","all")` so the v1 orphans stay reclaimable
- [x] `dir.create()` must create the **full** `v2/<source>` path, or `cache_write_atomic()`'s sidecar rename fails on first fetch
- [x] `dft_cache_info()` reports superseded-scheme entries; update `expect_named()` in `test-dft_cache.R`
- [x] `dft_cache_path()` keeps its exported contract unchanged
- [x] **Re-verify `test-dft_stac_cube.R` "a corrupt cube cache is re-fetched"** — it seeds at the pre-v2 path and would pass as a plain cache miss, never exercising the gate. Must fail when the gate is broken.
- [x] Update the ~8 test sites building `file.path(cache, "<source>")`

## Phase 4: Re-pin the goldens, once, deliberately

- [x] Re-pin fetch and cube goldens (`test-dft_stac_cube.R:62`, `test-dft_stac_fetch.R:94`)
- [x] Comments naming the rlang cause and the v2 bump — not "re-pinned until green"
- [x] Goldens are now portable facts, so they double as the cross-machine check

## Phase 5: Docs, NEWS, version

- [x] Roxygen: keyed by content; digest pinned to a published vector where rlang disclaims stability; note `st_as_binary()` honours `st_precision()`
- [x] **Correct `NEWS.md:20`**, which states in bold that cube caches are unaffected — this change invalidates them
- [x] NEWS: rlang root cause, one-time migration (~451 MB / ~20 min), `attr(,"cache_key")` format **and length** change, new `digest` Import, no rlang pin needed
- [x] `R/dft_cache.R` docs: the `v2/` scheme and `scheme=` argument
- [x] `devtools::document()`
- [x] Version bump (final commit)

## Validation

- [x] `devtools::test()` green
- [x] **Restore-the-defect**: each new test red against reverted code (patch BOTH `asNamespace("drift")` and `as.environment("package:drift")`)
- [x] Re-run the historical-key bisect: v2 key reproduces; the two pre-rlang-1.3.0 values do **not**
- [x] Network: a real fetch hits cache twice in a row under the new scheme
- [x] `lintr::lint_package()` no new lints vs baseline
- [x] `devtools::check()` — run; pre-existing non-ASCII WARNING in `R/dft_stac_fetch.R` unchanged
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

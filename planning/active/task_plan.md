# Task: Frozen cache-key goldens fail on main: the key moved, silently orphaning every cached cube and fetch (#48)

The cache key **is** the cache filename (`cube_<key>.tif`, `<year>_<key>.nc`), so when the hash
moved, every cached entry was silently orphaned — no error, no warning, just "the pipeline got
slower".

**The issue's diagnosis is wrong and the correction changes the fix.** It suspects sf/PROJ drift
under `sf::st_as_binary()`. Measured cause is `rlang::hash()` itself: rlang 1.3.0's NEWS states
"with this version all hash values will now be different" and that any future version may
invalidate hashes again. That makes every rlang upgrade a silent cache-wide outage.

## Phase 1: Failing tests

- [ ] Canonicalization contract: `%.17g` precision, `10L` vs `10`, zero-length/`NULL`, `NA`, logicals
- [ ] Collision test: `c("B08","B04")` must not key the same as `"B08,B04"`
- [ ] Multi-feature AOI: two different feature orderings must key differently
- [ ] **rlang-independence** — mock `rlang::hash` to return garbage; the key must not move
- [ ] Constant-hash control: pin `digest` output for a fixed string
- [ ] Confirm all fail against current `main`

## Phase 2: `cache_key_string()` + digest in both key functions

- [ ] Add `cache_key_string()` to `R/dft_stac_fetch.R`
- [ ] `stac_cache_key()` (`R/dft_stac_fetch.R:409`) switches to `digest::digest(..., algo="xxhash64", serialize=FALSE)`
- [ ] `stac_cube_cache_key()` (`R/dft_stac_cube.R:645`) same
- [ ] `enc2utf8()` on character members so encoding cannot alter bytes
- [ ] `digest` → Imports in DESCRIPTION
- [ ] Every existing "key changes with each parameter" test still passes

## Phase 3: Versioned cache directory

- [ ] `cache_scheme_dir()` internal; fetch (`R/dft_stac_fetch.R:162`) and cube (`R/dft_stac_cube.R:250`) write under `<cache>/v2/<source>/`
- [ ] `dft_cache_path()` keeps its exported contract unchanged
- [ ] `dft_cache_clear(source=)` (`R/dft_cache.R:50`) still resolves correctly under the scheme
- [ ] `dft_cache_info()` (`R/dft_cache.R:74`) reports superseded-scheme entries
- [ ] Update the `expect_named()` assertion in `test-dft_cache.R` deliberately (return list gains fields)

## Phase 4: Re-pin the goldens, once, deliberately

- [ ] Re-pin fetch golden (`test-dft_stac_fetch.R`) and cube golden (`test-dft_stac_cube.R:62`)
- [ ] Comments naming the rlang cause and the v2 scheme bump — not "re-pinned until green"
- [ ] Both goldens become portable facts (same on any machine), so they double as the cross-machine check

## Phase 5: Docs, NEWS, version

- [ ] Roxygen: cache entries keyed by content, stable across R/rlang/sf upgrades and machines
- [ ] `R/dft_cache.R` docs: the `v2/` scheme and what sits under superseded versions
- [ ] `devtools::document()`
- [ ] NEWS.md — rlang root cause, the one-time migration, the ~451 MB / ~20 min note, no rlang pin needed
- [ ] Version bump (final commit)

## Validation

- [ ] `devtools::test()` green
- [ ] **Restore-the-defect**: each new test red against reverted code (patch BOTH `asNamespace("drift")` and `as.environment("package:drift")`)
- [ ] Re-run the historical-key bisect: v2 key reproduces; the two pre-rlang-1.3.0 values do **not** (re-pinning those would be the loosening the issue forbids)
- [ ] Network: a real fetch hits cache twice in a row under the new scheme
- [ ] `lintr::lint_package()` no new lints vs baseline
- [ ] `devtools::check()` — note the pre-existing non-ASCII WARNING in `R/dft_stac_fetch.R`
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

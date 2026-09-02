# Task: `dft_stac_fetch()` reads one STAC page — a wide AOI can build a raster from a truncated item set (#51)

## Problem

`dft_stac_fetch()` calls `rstac::get_request()` with no `items_fetch()`
(`R/dft_stac_fetch.R:127-134`), so the item collection handed to
`gdalcubes::stac_image_collection()` is **one page**. If the API paginates, the cube is
built from a partial item set and the returned raster is silently wrong over the missing
tiles — no error, no warning, plausible output.

Planetary Computer returns **no `numberMatched`**, so nothing in the response advertises
the total. The only signal is a `rel="next"` link.

## Measured before planning (2026-09-01, live against Planetary Computer)

Collection `io-lulc-annual-v02`, packaged AOI `inst/extdata/example_aoi.gpkg`,
`2017-01-01/2023-12-31`. Ground truth **14 items**.

```
limit=NULL raw_n=14 raw_next=FALSE | fetched_n=14 fetched_next=FALSE | matched=NULL
limit=1    raw_n=1  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
limit=3    raw_n=3  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
limit=500  raw_n=14 raw_next=FALSE | fetched_n=14 fetched_next=FALSE | matched=NULL
```

**The issue's suggested guard is wrong and will not be implemented.** The `next` link
*survives* a successful `items_fetch()` — confirmed at source: `items_fetch.doc_items`
mutates only `items$features` and never `items$links`, so the returned object is page 1's
document with a concatenated feature list. A surviving `next` means "paging happened",
not "paging is incomplete". Erroring on it would abort every correctly-paged fetch.

`items_matched()` is NULL at every page size on PC (it looks up `matched_field`,
`search:metadata$matched`, `context$matched`, then `numberMatched` — PC supplies none).

## Phase 1: Failing tests first

- [x] `stac_items_paged()` unit tests, offline, with mocks that **pass through and
      augment** rather than return a fixed object — a fixed-return mock cannot detect
      sign-before-page and is a test that cannot fail
- [x] Signing-after-paging: mocked `items_fetch` appends an unsigned page-2 feature,
      mocked `items_sign` marks features; assert **every** feature is marked
- [x] Duplicate-id assertion fires on a hand-built collection with a repeated id
- [x] `items_matched()` completeness guard: fixture a `doc_items` with
      `numberMatched = 99` and 3 features, assert it aborts; assert it does **not** abort
      when `numberMatched` is absent (both known answers)
- [x] Wiring test: mock the drift-internal `stac_items_paged()` and
      `gdalcubes::stac_image_collection()` to prove `dft_stac_fetch()` actually calls the
      helper — the helper's own unit tests all pass with the old inline pipeline in place
- [x] Pin the stale-`next`-link fact so a future rstac change fails by naming the cause
- [x] Confirm each test FAILS against current `main` before writing the fix

## Phase 2: Page to exhaustion

- [x] Add `stac_items_paged()` — `stac_search(limit = 500)` → `get_request()` →
      `items_fetch()` → `items_sign(sign_fn)`, in that order
- [x] Assert no duplicate item ids after paging. This is the one completeness invariant
      never skipped on PC; `gdalcubes::stac_image_collection()` silently skips duplicates
      behind a `.pkgenv$debug` gate, so nothing downstream would ever report them
- [x] `items_matched()`-conditional completeness guard (fires only when non-NULL)
- [x] **Strip `rel="next"` from `items$links` before returning.** The fix creates this
      hazard: `attr(result, "stac_items")` carries the collection to callers, and a caller
      calling `items_fetch()` on an object with a stale `next` re-fetches pages 2..N and
      appends them to an already-complete feature list — silent duplicates in user code
- [x] Rewire `dft_stac_fetch()`; keep the `n_items` message and zero-item `stop()`
- [x] Comment **why** this keeps GET where `dft_stac_cube()` uses POST (the cube needs
      POST for `ext_filter`/CQL2, not for paging), and the trigger to switch
- [x] `devtools::document()`; read output for unexpected `.Rd` writes

## Phase 3: Cache invalidation — the truncated rasters already on disk

`stac_cache_key()` hashes geometry, res, crs, dt, aggregation, resampling, stac_url,
collection, asset, tile_size — **nothing this fix changes.** So a previously truncated
`<year>_<key>.nc` keeps being served by the `file.exists()` short-circuit
(`R/dft_stac_fetch.R:171`). The users hit hardest by the bug get no fix at all on
upgrade, silently and permanently under `force = FALSE`. Same trap the cube already
fixed on its read path (`R/dft_stac_cube.R:272`).

- [x] Bump the fetch cache key deliberately (salt), so affected caches rebuild once
- [x] Re-freeze the legacy-hash test (`tests/testthat/test-dft_stac_fetch.R:83-89`) **with
      a comment recording why it moved** — its own comment demands the break be flagged,
      not silently re-frozen
- [x] Say so in NEWS: this is a one-time re-fetch of small annual rasters, not the cube's
      multi-hour stream

## Phase 4: Network two-answer test

- [x] Opt-in `DRIFT_TEST_NETWORK=true`, matching the existing pattern
- [x] Assert the **identical ordered vector of item ids** across `limit=1` and
      `limit=500`, not just counts — item order is output-visible under
      `aggregation = "first"` where items share a datetime and overlap spatially
- [x] Assert an unpaged `limit=1` gives strictly fewer (the defect and the fix give
      different answers on the same call)
- [x] Assert signed hrefs on an item from beyond the first page
- [x] Build the unpaged arm inline in the test — no production `paged=` switch whose only
      caller is a test

## Phase 5: Secondary — expose the cache key

- [x] `attr(result, "cache_key") <- cache_key` beside `attr(result, "stac_items")`
- [x] Update `@return` (`R/dft_stac_fetch.R:51-53`), documenting it as **per-call, not
      per-year**, since cache filenames are `<year>_<key>`
- [x] Test recomputes `stac_cache_key()` with the same inputs and asserts equality —
      pinning the attribute to its definition, not merely to non-NULL

## Phase 6: Docs and release

- [x] `inst/notes/gdalcubes-pc-gotchas.md`: record that the surviving `next` link makes
      the obvious guard unusable, so it is not re-litigated
- [x] `NEWS.md` with the measured numbers, the cache-key break, and a note that a larger
      item set means more chance of `stac_image_collection()`'s per-item skip warning —
      so it is not read as a regression from this PR
- [ ] Version bump in `DESCRIPTION` as the **final** commit of the branch

## Out of scope (verified, stated deliberately)

- `dft_stac_cube()` already pages correctly and is not touched.
- No user-facing `limit` argument on `dft_stac_fetch()`.
- `limit = 500` is a round-trip reducer, **not** the truncation fix — `items_fetch()` is.
  With only 14 items available, nothing here distinguishes "PC honours 500" from "PC
  clamps to its 250 cap", so NEWS must not imply `limit` avoids paging.
- `limit=1` is a faithful proxy for the paging *mechanism*, not for PC's real 250-item
  page cap. Neither the packaged AOI nor this test reaches that cap.
- `skip_image_metadata = TRUE` and the O(n²) `stac_image_collection()` build cost at
  large item counts — a follow-up issue, not this PR.
- The cache key does not hash `years` (pre-existing, deliberate — year is the filename
  prefix), so `years=2020` and `years=c(2017,2023)` share a key for 2020 while querying
  different windows. Unaffected by paging.

## Validation

- [x] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

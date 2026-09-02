# 2026-09 — issue #51: `dft_stac_fetch()` read one STAC page

`dft_stac_fetch()` called `rstac::get_request()` with no `items_fetch()`, so it read one
page of STAC items and handed the partial collection to
`gdalcubes::stac_image_collection()`. A wide AOI therefore built a raster with missing
tiles — silently, with no error and plausible output. `dft_stac_cube()` had always paged;
fetch was never brought across. Fixed by an internal `stac_items_paged()` that pages to
exhaustion and then signs (order is load-bearing — signing first leaves every item from
page 2 onward unsigned), plus a deliberate cache-key break so rasters already written from
truncated item sets cannot keep being served. Shipped in v0.10.0.

## Measurement

The issue proposed erroring when a `rel="next"` link survives. **Measurement killed that
design before any code was written.** Against Planetary Computer, `io-lulc-annual-v02`,
packaged AOI, `2017-01-01/2023-12-31` — ground truth 14 items:

```
limit=NULL raw_n=14 raw_next=FALSE | fetched_n=14 fetched_next=FALSE | matched=NULL
limit=1    raw_n=1  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
limit=3    raw_n=3  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
limit=500  raw_n=14 raw_next=FALSE | fetched_n=14 fetched_next=FALSE | matched=NULL
```

The `next` link survives a *successful* `items_fetch()` — confirmed at source:
`rstac:::items_fetch.doc_items` mutates only `items$features` and never `items$links`. So
the proposed guard would have aborted every correctly-paged fetch. The link is stale, so
the fix **strips** it instead; left attached to `attr(, "stac_items")` it lets a caller
re-page an already-complete collection and silently duplicate features.

`items_matched()` is NULL at every page size on PC, so no count-based completeness check
is available there. Duplicate item ids is the one invariant that is never skipped —
and it matters because `gdalcubes::stac_image_collection()` drops duplicates behind a
`.pkgenv$debug`-gated message, so nothing downstream would ever report them.

Restore-the-bug over **9** defects, against a clean baseline of FAIL=0: no paging 2,
sign-before-page 1, next-link-kept 2, no duplicate check 1, no `items_matched` guard 1,
cache salt removed 9, `is.null` instead of `length` guard 1, helper bypassed 1,
exact-case strip 2.

## The wrong turns, kept

- **The first probe measured the wrong collection.** `io-lulc-9-class` (6 items) rather
  than drift's actual `io-lulc-annual-v02` (14). Re-run before any number was used.
- **The wiring test could not fail.** As first written it asserted only that a stubbed
  `gdalcubes::stac_image_collection()` was reached — which the old inline pipeline
  satisfies equally well. It measured **FAIL=0** against the very defect it existed to
  catch, and reading it would never have shown that. Rewritten so the stub reports the
  item ids it received with `rstac::get_request()` booby-trapped; now FAIL=1.
- **A cube test failure was nearly attributed to this change.** `test-dft_stac_cube.R:62`
  went red and the instinct was that the new cache salt had leaked into
  `stac_cube_cache_key()`. Stashing the branch showed it red on `main` too.

## Evidence

Probe scripts were scratch (`/tmp/drift_probe*.R`, `/tmp/restore_bug*.R`); the numbers
they produced are in `findings.md` and in the commit messages, which is where they
belong. Nothing was committed to `data-raw/logs`.

## Out-of-scope defects found, not fixed here

- `test-dft_stac_cube.R:62` — the cube's frozen cache-key guardian expects `638a2be11fdf`
  and gets `45685ccbda33`. Bisected to `90f9d93`, the commit that **introduced** it, and
  every commit since: it has never been green on this machine.
- **drift has no CI workflow that runs the test suite** — `.github/workflows/` holds only
  `pkgdown.yaml` and `update-citation-cff.yaml`. That is why the above survived a release
  cycle: every CI run is green because nothing runs the tests. These two findings are the
  same finding.

## Closing

Commits `283bf55` (baseline) → `fc2e861` (fix) → `bbb679a` (case-insensitive strip) →
`acc3243` (v0.10.0).

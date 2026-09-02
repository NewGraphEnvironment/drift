# Findings — dft_stac_fetch() reads one STAC page (#51)

## Live measurement (2026-09-01, Planetary Computer)

Collection `io-lulc-annual-v02`, packaged AOI `inst/extdata/example_aoi.gpkg`,
datetime `2017-01-01/2023-12-31`. Ground truth **14 items**.

```
limit=NULL raw_n=14 raw_next=FALSE | fetched_n=14 fetched_next=FALSE | matched=NULL
limit=1    raw_n=1  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
limit=3    raw_n=3  raw_next=TRUE  | fetched_n=14 fetched_next=TRUE  | matched=NULL
limit=500  raw_n=14 raw_next=FALSE | fetched_n=14 fetched_next=FALSE | matched=NULL
```

A first probe used collection `io-lulc-9-class` (6 items) — the wrong collection. drift's
`dft_stac_config("io-lulc")` returns `io-lulc-annual-v02`. Numbers above are from the
re-run against the collection drift actually uses.

## The issue's suggested guard is wrong

The issue proposes "a hard error when a `next` link survives". Measurement shows the
`next` link survives a **successful** `items_fetch()` whenever paging occurred (limit=1
and limit=3 both return the complete 14 items *and* carry `rel="next"`).

Confirmed at source — `rstac:::items_fetch.doc_items`:

```r
next_items <- items
while (TRUE) {
  ...
  next_items <- tryCatch({ items_next(next_items, ...) },
                         next_error = function(e) NULL)
  if (is.null(next_items)) break
  items$features <- c(items$features, next_items$features)
}
items
```

Only `items$features` is mutated. `items$links` is never touched, so the returned object
is **page 1's document with a concatenated feature list**, carrying page 1's `next` link
verbatim. Paging itself is correct — `items_next.doc_items` reads the link off
`next_items`, the current page, which does advance.

A surviving `next` therefore means "paging happened", not "paging is incomplete".
Erroring on it is a fail-toward-abort guard that would break every correctly-paged fetch.

## What the loop's exits mean for a completeness check

Every exit from that loop, traced:

- The `tryCatch` catches **only** class `next_error`, raised in exactly one place —
  `items_next.doc_items` when `length(next_link) == 0`.
- Transport failures go through `make_get_request(..., error_msg =)` → `.error(...)` with
  `class = NULL`. Not caught.
- Non-200 status or non-JSON content type → `content_response()` → `.error(...)`, also
  `class = NULL`. Not caught.

So after a successful `items_fetch()` there is no silent-truncation mode left, except a
server returning a page with no `next` while more data exists. That — not "the check
skips on PC" — is the honest justification for not asserting completeness there.

## `items_matched()` is NULL on PC

`rstac:::items_matched.doc_items` looks up, in order: a caller-named `matched_field`,
`search:metadata$matched`, `context$matched`, then `numberMatched`. PC supplies none, so
the result is NULL at every page size (measured above). A count-based completeness guard
is available on other STAC APIs and must be conditional.

## The invariant that IS available on PC: duplicate item ids

`anyDuplicated(vapply(items$features, function(f) f$id, ""))` is cheap and never skipped.
It fires on real paging bugs (token replay, unstable server sort).

Nothing downstream would ever report a duplicate. `gdalcubes::stac_image_collection()`
handles them silently:

```r
if (s[[i]]$id %in% images_df$name) {
  if (.pkgenv$debug) { message(paste0("Skipping STAC item ", s[[i]]$id), " due to duplicate id ...") }
  next
}
```

The skip precedes any `rbind`, so the collection stays consistent — but the message is
gated behind `.pkgenv$debug`, off by default.

## Hazard the fix creates: the stale `next` link reaches callers

`R/dft_stac_fetch.R:192` attaches `attr(result, "stac_items") <- items`. After the fix
that object's links still point at page 2. A caller calling `rstac::items_fetch()` or
`items_next()` on it re-fetches pages 2..N and appends them to an already-complete
feature list — **silent duplicates in user code**. Before the fix the attached object was
single-page and this was harmless.

Strip `rel == "next"` from `items$links` before attaching. That is the constructive form
of the guard the issue asked for: the link is stale, so delete it rather than error on it.

## Cache: the truncated rasters already on disk

`stac_cache_key()` (`R/dft_stac_fetch.R:210-222`) hashes geometry, res, crs, dt,
aggregation, resampling, stac_url, collection, asset, tile_size — **nothing this fix
changes**. So a previously truncated `<year>_<key>.nc` keeps being served by the
`!force && file.exists(cache_file)` short-circuit at `R/dft_stac_fetch.R:171`. The users
hit hardest by the bug (wide AOIs) get no fix at all on upgrade, silently and permanently
under `force = FALSE`.

Identical failure class to the one the cube already fixed:
`cube_check_nonempty(..., cached = TRUE)` on the read path (`R/dft_stac_cube.R:272`),
whose comment reads "the cache key is unchanged, so upgrading does not invalidate it."

Resolved by bumping the fetch key. An io-lulc re-fetch is one small annual raster per
year — cheap — unlike the cube's multi-hour Sentinel-2 stream, which is why the cube
chose a read-path check and the fetch can afford a key break. Precedent: NEWS 0.5.0,
"the clip is folded into the cube cache key, so existing cached cubes rebuild once."

## Why GET stays

`dft_stac_cube()` uses POST because `ext_filter()` (CQL2) requires it
(`R/dft_stac_cube.R:289`) and because `intersects` carries a real polygon
(`R/dft_stac_cube.R:285`, URL-length risk) — **not** for paging.
`dft_stac_fetch()` uses bbox only with no filter, so GET is right, and it is the verb
measured above. `items_next.doc_items` branches on `next_link$method`; PC's GET next link
is a self-contained href carrying the paging token.

Trigger to revisit: if `dft_stac_fetch()` ever gains `intersects` or a property filter.

## Downstream of a larger item set

- `dft_stac_classes()` is safe — it reads only `items$features[[1]]$properties`
  (`R/dft_stac_classes.R:62`), and paging **appends**, never prepends, so feature 1 is
  unchanged and the class table is bit-identical.
- The image collection is built **once** (`R/dft_stac_fetch.R:142`) and reused across
  years and tiles, so `stac_image_collection()`'s O(n²) build cost is paid once. (The
  cube rebuilds per tile — the reason `tile_size` measured 5.3x slower there.)
- `stac_image_collection()` wraps each item in
  `tryCatch(..., error = function(e) warning("Skipping STAC item ..."))`. More items
  means more chance a bad item is skipped with only a warning; users may see warnings
  they never saw before. Named in NEWS so it is not read as a regression from this PR.

## Test-design facts verified locally

- `local_mocked_bindings(.package = "rstac")` **does** intercept a namespace-qualified
  `rstac::items_fetch()` call — `::` resolves through the namespace env at call time.
  Verified against testthat 3.3.2 (DESCRIPTION pins `>= 3.2.0`).
- `rstac::stac()` and `rstac::stac_search()` are pure query constructors with no network
  call; only `get_request`/`post_request` need mocking.
- A mock that ignores its input and returns a fixed object **cannot** detect
  sign-before-page — both orders pass. The mock must pass through and augment.
- The mock cannot be run through `dft_stac_fetch()` offline: the next statement is
  `gdalcubes::stac_image_collection()` (`R/dft_stac_fetch.R:142`) followed by real cube
  reads. This is the strongest argument for extracting `stac_items_paged()` — stronger
  than "testable at a tiny limit".

## Errors Encountered

| Error | Resolution |
|-------|------------|
| First probe returned 6 items, not the expected count | Probe used `io-lulc-9-class`; drift uses `io-lulc-annual-v02`. Re-ran against the real collection (14 items). |

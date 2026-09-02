# Review round 3 — #51 STAC paging: tests that cannot fail

Scope: `R/dft_stac_fetch.R` and `tests/testthat/test-dft_stac_fetch.R` at HEAD
(`e8a30ea`). Single focus: tests that cannot fail, and guards that fail in the
wrong direction.

**Method.** Everything below is measured, not reasoned. A scratch copy of the
package was mutated one edit at a time and `testthat::test_file()` re-run against
the offline suite. Clean baseline: **FAIL=0, ERROR=0**.

**Note on the supplied diff.** `/tmp/cc_diff2.txt` is commit `fc2e861`, which is
*not* the shipping code: it predates `bbb679a` (case-insensitive `next` strip)
and, as committed, **does not parse** — see finding 9. Everything below was
reviewed against HEAD.

---

## Mutation results

Mutations that the offline suite **does** catch (the tests work):

| mutation | FAIL |
|---|---|
| M16 `items_fetch()` removed — no paging | 2 |
| M19 true sign-before-page (sign in pipeline, **no** late sign) | 1 |
| M18 `next`-strip removed entirely | 4 |
| M14 strip back to exact `identical(l$rel, "next")` | 2 |
| M13 strip drops the `is.character(l$rel) && length(l$rel)==1L` guard | 1 |
| M15 `matched` guard uses `is.null()` instead of `length()==1L` | 1 |
| M9 duplicate-id guard disabled | 1 |
| M10 `items_matched` guard disabled | 1 |
| M21 helper truncates its own result after paging | 4 |

Mutations that the offline suite **does not** catch:

| mutation | FAIL | caught anywhere? |
|---|---|---|
| M2 `dft_stac_fetch()` hardcodes `sign_fn = rstac::sign_planetary_computer()` | 0 | **nowhere** |
| M6 `attr(result, "cache_key") <- cache_key` deleted | 0 | network-only |
| M1 `rstac::items_sign(items)` — `sign_fn` dropped | 0 | production runtime error only |
| M3 `bbox = as.numeric(bbox_target)` (UTM instead of WGS84) | 0 | network-only |
| M4 wrong `datetime` sent to STAC | 0 | network-only |
| M5 wrong `collection` sent to STAC | 0 | network-only |
| M7 default `limit = 500` → `1` | 0 | nowhere |
| M11 abort message swaps `{n_items}` and `{matched}` | 0 | nowhere |
| M12 duplicate abort message loses the offending ids | 0 | nowhere |
| M20 the `NA_character_` id branch | 0 | nowhere (unreachable fixture) |

---

## Findings

### 1. [bug] tests/testthat/test-dft_stac_fetch.R:411-413 — the wiring mock discards every argument, so five plumbing defects pass

```r
stac_items_paged = function(...) fake_items(c("sentinel-x", "sentinel-y"), next_link = FALSE)
```

The test proves the helper **was called** and nothing about **what with**. Before
the refactor `bbox_query`, the `datetime` string, `collection`, `stac_url` and
`sign_fn` were inline in one pipeline inside `dft_stac_fetch()`. The refactor
moved all five across a function boundary that no offline test asserts.

Measured: M2, M3, M4, M5 all FAIL=0.

The serious one is **M2**. Replacing `sign_fn = sign_fn` with
`sign_fn = rstac::sign_planetary_computer()` in the call to the helper makes the
documented `sign_fn` argument of `dft_stac_fetch()` (R/dft_stac_fetch.R:48-49,
74) a silent no-op, and **no test in the file catches it** — network test 1 uses
the default, and network test 2 calls `stac_items_paged()` directly with an
explicit `sign_fn`. This is a public documented parameter that can be severed
with a green suite.

M3/M4/M5 are caught by network test 1 (PC returns 0 items → `No STAC items
found`), so they are only invisible offline. M2 is invisible everywhere.

Fix is one line in the existing mock:

```r
seen <- NULL
testthat::local_mocked_bindings(
  stac_items_paged = function(...) { seen <<- list(...); fake_items(c("sentinel-x","sentinel-y"), next_link = FALSE) }
)
# ... after the expect_error():
expect_identical(seen$sign_fn, <the sign_fn passed to dft_stac_fetch>)
expect_equal(seen$bbox, as.numeric(sf::st_bbox(sf::st_transform(aoi, 4326))))
expect_equal(seen$datetime, "2020-01-01/2020-12-31")
expect_equal(seen$collection, dft_stac_config("io-lulc")$collection)
```

(`expect_error()` aborts the call, but `seen` is assigned before the abort, so
the assertions run afterwards fine.)

### 2. [bug] tests/testthat/test-dft_stac_fetch.R:454-464 — `attr(, "cache_key")` is only tested behind an env var

Deleting `attr(result, "cache_key") <- cache_key` (R/dft_stac_fetch.R:197)
measures **FAIL=0**. Its only assertion is at line 454, inside a test gated on
`skip_if(Sys.getenv("DRIFT_TEST_NETWORK") != "true")`.

This is a **new documented `@return` element** (R/dft_stac_fetch.R:55-58) shipping
in v0.10.0 with zero coverage in CI or in any default `devtools::test()`. Per the
"Tests that silently do not run" rule, a guard that only runs on one machine with
an env var set is absent, not weak.

An offline test is viable — verified working in a scratch copy:

```r
# pre-seed the cache so the file.exists() short-circuit fires, then the fetch
# returns normally without gdalcubes doing any work
k <- drift:::stac_cache_key(aoi_target, 10, crs, "P1Y", "first", "near",
                            cfg$stac_url, cfg$collection, cfg$asset, tile_size = NULL)
terra::writeRaster(tiny_raster, file.path(cache, "io-lulc", paste0("2020_", k, ".nc")),
                   filetype = "GTiff")     # GDAL sniffs content, extension is fine
local_mocked_bindings(stac_items_paged = function(...) <a 1-feature doc_items>)
local_mocked_bindings(stac_image_collection = function(...) NULL, .package = "gdalcubes")
out <- dft_stac_fetch(aoi, source = "io-lulc", years = 2020, cache_dir = cache)
expect_identical(attr(out, "cache_key"), k)
```

This also gives the only offline coverage of the `<year>_<key>` filename contract,
which is currently network-only too (line 462).

### 3. [bug] tests/testthat/test-dft_stac_fetch.R:284-287, 304, 320, 340, 353, 363, 376, 388 — `sign_fn` is never observed by any mock, so signing is untested

Answering the fixture question directly: **every `items_sign` mock has signature
`function(items, ...)` and ignores `sign_fn`, and every `fake_items()` feature
carries `assets = list()`** — an empty asset list. So nothing offline can observe
signing of an actual href, and nothing can observe *which* `sign_fn` was used.

Measured: M1 (`rstac::items_sign(items)`, dropping `sign_fn = sign_fn` from
R/dft_stac_fetch.R:288) is **FAIL=0** across the whole offline suite. `rstac`'s
`items_sign(items, sign_fn)` has **no default for `sign_fn`**, so M1 errors on the
first real call — it fails loudly rather than silently, which is why this is
listed after finding 1. But taken with finding 1, the entire `sign_fn` path from
the user's argument to `rstac` is untested.

The "signs AFTER paging" test at :275 does work for the property it names — the
faithful defect (M19: sign inside the pipeline **and** drop the late sign) is
FAIL=1. Note for anyone re-running a restore harness: signing *in addition to* the
late sign (my first attempt, M17) measures FAIL=0 and is not the defect.

Cheapest fix — one mock already has the hook:

```r
seen_fn <- NULL
items_sign = function(items, sign_fn, ...) { seen_fn <<- sign_fn; ... }
# then
expect_identical(seen_fn, the_sign_fn_passed_to_paged())
```

### 4. [fragile] tests/testthat/test-dft_stac_fetch.R:519 — the network test's stated two-answer premise cannot fail

```r
# the two answers must differ, or the test cannot fail
expect_lt(length(truncated$features), length(big$features))
```

This holds identically under the fixed and the unfixed code:

- `truncated` is built inline and **never calls `stac_items_paged()`** — it is one
  unpaged page at `limit = 1`, so always 1 feature.
- `big` is `limit = 500`, and by the test's own comment (line 492) the packaged
  AOI returns all 14 items **in a single page** at that limit — so `big` is 14
  whether or not `items_fetch()` is called.

`1 < 14` in both worlds. The line labelled as the test's two-answer structure is
decoration. The comparison that would discriminate is `truncated` vs `small`
(same `limit = 1`, unpaged vs paged): 1 vs 14 only when paging works.

The test as a whole is **not** broken — `expect_identical(ids(small), ids(big))`
(:522) and `expect_gt(length(small$features), 1L)` (:530) both fail under M16, so
the two-answer structure exists; it just isn't the line that claims to be it. Fix:

```r
expect_lt(length(truncated$features), length(small$features))
```

Also at :526, `vapply(small$links, function(l) l$rel, character(1))` errors on any
`rel`-less link (the offline test at :313 deliberately fixtures one), and the
membership test is exact `"next"` while production now matches case-insensitively.
Mirror the offline form so the network arm checks the same property.

### 5. [fragile] tests/testthat/test-dft_stac_fetch.R:356 — `expect_error(paged(), "99")` cannot tell the two numbers apart

M11 — swapping `{n_items}` and `{matched}` in the abort so it reads
*"returned 99 items but the API reports 3"* — measures **FAIL=0**. Those two
numbers are precisely what a user acts on when the guard fires, and the test
cannot distinguish the correct message from its inverse.

Match the sentence, not the digit:

```r
expect_error(paged(), "returned 3 items but the API reports 99")
```

Same shape, lower stakes, at :343: `expect_error(paged(), "duplicate")` still
passes when the message loses the offending ids entirely (M12, FAIL=0). Assert the
id — `expect_error(paged(), 'duplicate item id.*"a"')` — since the id is the
actionable part.

### 6. [fragile] R/dft_stac_fetch.R:254-256 and tests/testthat/test-dft_stac_fetch.R:371-372 — the stated route to `numeric(0)` is unreachable from this call site

Both comments justify the `length(matched) == 1L` form with *"items_matched()
reads a caller-supplied field name"*. But `stac_items_paged()` calls
`rstac::items_matched(items)` with **no** `matched_field`, and rstac's
`items_matched.doc_items` only enters that branch under
`is.character(matched_field)`:

```r
if (is.character(matched_field) && matched_field %in% names(items))
  matched <- as.numeric(items[[matched_field]])
```

So the named route cannot fire here. The guard is still correct and worth keeping
— a server emitting `"numberMatched": []` reaches `numeric(0)` through the
fallback, and M15 confirms the `length()` form is load-bearing (`is.null()` →
FAIL=1) — but the premise as written is false, and a comment justifying a test is
exactly the kind of thing that gets copied forward as measured fact. Restate it as
the fallback path (`items$numberMatched` being an empty vector), or drop the
reachability claim and keep it as defensive.

### 7. [fragile] tests/testthat/test-dft_stac_fetch.R:383-393 — the shipped default `limit = 500` is unpinned

The only limit test passes an explicit `7`, so changing the default in
`stac_items_paged()` (R/dft_stac_fetch.R:240) to `1` measures **FAIL=0**. Low
stakes — the docstring is explicit that `limit` is a round-trip reducer and
`items_fetch()` is what makes the result complete — but the documented default has
no guard at all, and `dft_stac_fetch()` never passes `limit`, so the default is the
only value production ever uses. One line: `expect_equal(formals(drift:::stac_items_paged)$limit, 500)`,
or call `paged()` with no `limit` and assert `seen$params$limit`.

### 8. [fragile] R/dft_stac_fetch.R:264-275 — the id-less branch is unfixtured, and it fails toward the wrong diagnosis

Every `fake_items()` feature carries a non-`NULL` `id`, so the `NA_character_`
branch at :266 is never executed (M20: replacing it with `""` is FAIL=0).

The direction matters more than the coverage: two id-less features produce
`c(NA, NA)`, `anyDuplicated()` returns 2, and the fetch aborts with *"STAC paging
returned duplicate item ids: NA — Pages overlapped"*. STAC requires `id`, so this
is not reachable against a conformant API; but if it ever were, the guard converts
"the response is missing ids" into "pages overlapped", pointing the reader at the
wrong problem. Either fixture it and assert the message you want, or check for
missing ids separately before the duplicate check.

### 9. [fragile] commit `fc2e861` does not parse

```
$ git show fc2e861:R/dft_stac_fetch.R | R --slave -e 'parse("stdin")'
PARSE ERROR: 300:28: unexpected symbol
299:   resampling, stac_url, collection, asset
300:   tile_size
```

The `stac_cache_key()` argument list lost its comma after `asset`, and the
`"items-paged-v2"` salt string was absent from the `parts` list. Both were
restored by `bbb679a`, whose message describes only the case-insensitivity change.

Nothing ships broken — HEAD and the `acc3243` release commit are fine — but two
consequences are worth recording: a bisect or checkout of `fc2e861` gets a package
that will not load, and the commit that claims to introduce the cache-format break
does not actually contain the salt, so `git log -p` on that file tells a
misleading story. Also the reason the supplied review diff did not match the
shipping source.

---

## Checked and clean

- **No mock leakage.** No call passes `.env`; every `local_mocked_bindings()` sits
  at `test_that()` top level, so `.env` defaults to `parent.frame()` = the test
  frame. `.package` is right in every case: `"rstac"` / `"gdalcubes"` for external
  bindings, omitted (hence the drift namespace) for the internal
  `stac_items_paged`, which is the correct binding because `dft_stac_fetch()`
  calls it unqualified from inside the namespace. Verified empirically —
  `rstac::get_request` and `rstac::items_matched` are the real functions after the
  file runs.
- **Every new `test_that` block has a nameable breaking change**, and one was
  measured for each substantive block (table above). No test in the diff is
  unfalsifiable.
- **The pass-through mocks do discriminate order.** M19 (faithful sign-before-page)
  is FAIL=1.
- **The `next`-strip tests are doing real work.** M13 (dropping the
  `is.character`/`length` guard, which makes `Filter()` misalign its index vector
  on a `rel`-less link) is FAIL=1; M14 (exact match) is FAIL=2.
- **`expect_match(last_href, "\\?")` at :532 cannot pass vacuously.** This testthat
  errors on both `NULL` (`must be a character vector`) and `character(0)`
  (`Expected ... at least one element`), so a missing asset or href fails rather
  than passing empty.
- **`rstac::items_fetch.doc_items` really does mutate only `$features`** and never
  `$links` — the docstring premise at R/dft_stac_fetch.R:218-225 and the fixture's
  `next_link = TRUE` default are accurate.
- The redundancy between :83 (frozen literal) and :97 (`expect_false(== old key)`)
  is real but harmless — both fail when the salt is removed, and :97 fails naming
  the reason, which is its stated purpose.

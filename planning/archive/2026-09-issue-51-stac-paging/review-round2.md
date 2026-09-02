# Review round 2 — #51 `dft_stac_fetch()` pages to exhaustion

Reviewed: `R/dft_stac_fetch.R`, `tests/testthat/test-dft_stac_fetch.R`, `/tmp/cc_diff2.txt`,
against `~/CLAUDE.md` "Code Check Conventions".

**The tree moved during this review.** `/tmp/cc_diff2.txt` was already stale when I opened it:
it shows `stac_cache_key()`'s formals without the comma after `asset` and `parts` without the
`"items-paged-v2"` salt. While I was probing, commit `bbb679a` landed and rewrote the
`next`-link filter from exact to case-insensitive matching. Everything below is measured
against `bbb679a` (worktree == index == HEAD, `md5 2bee644c7ac908fa1967bf079fc096cb`).
Finding 1 is about the commit *before* it, which is still in the branch history.

---

## Findings

### 1. [bug] Commit `fc2e861` does not parse — the package cannot be loaded at that SHA

`fc2e861` ("Page dft_stac_fetch() to exhaustion; break the fetch cache key (#51)") is the
main commit of this branch, and it is broken two ways. Measured:

```
$ git show fc2e861:R/dft_stac_fetch.R > /tmp/p.R
$ Rscript -e 'parse("/tmp/p.R")'
PARSE ERROR: /tmp/p.R:300:28: unexpected symbol
299:                            resampling, stac_url, collection, asset
300:                            tile_size
                                ^
$ git show fc2e861:R/dft_stac_fetch.R | grep -c "items-paged-v2"
0
```

Two independent defects in one commit:

- **Missing comma** after `asset` in `stac_cache_key()`'s formals — the file is not valid R,
  so `load_all()` / `library(drift)` fails outright at that commit.
- **The cache-format salt is absent.** That commit's own `NEWS.md` entry and its own frozen-hash
  test (`expect_equal(cache_key(), "2264b5dbef6e")`) both depend on the salt. Had the file
  parsed, the commit's test suite would have been red — the key without the salt is
  `79f67b7b9dae`, the value the sibling test explicitly asserts *must not* be returned.

Both were repaired by `bbb679a`, whose message names only the case-insensitive strip, so the
syntax fix and the missing salt rode in silently under an unrelated subject.

Why it matters: `git bisect` over this branch hits an unloadable commit; any per-commit CI
(matrix jobs, `R CMD check` on push) fails there; and if the PR is merged with a **merge
commit** rather than a squash, `fc2e861` lands on `main` permanently. This is also the
`code-check.md` "running a generator is not committing what it generated" family in reverse:
the verification was done in the working tree, and the commit carried a different file.

**Suggested:** squash-merge, or `git rebase -i` to fold `bbb679a`'s syntax/salt half into
`fc2e861` and leave only the case-insensitive change as its own commit. Cheap guard for next
time: `Rscript -e 'parse("R/dft_stac_fetch.R")'` in the pre-commit path — this class is
invisible to `devtools::test()` when the working tree is correct and only the index is not.

---

### 2. [fragile] The case-insensitive `next` strip is justified by a hazard that cannot occur, and it deletes the only remaining evidence of a truncated fetch

`R/dft_stac_fetch.R:277-286`:

```r
# ... Case-insensitive: STAC and rstac both emit
# lowercase `rel`, but matching only the exact string would silently leave a
# differently-cased link behind, which is the one outcome this must prevent.
items$links <- Filter(
  function(l) !(is.character(l$rel) && length(l$rel) == 1L &&
                  tolower(l$rel) == "next"),
  items$links
)
```

The stated rationale is contradicted by rstac's own matcher. `rstac:::items_next.doc_items`
locates the next page with `links(items, rel == "next")`, which is **case-sensitive**:

```
rel=next  -> rstac::links(rel=="next") matches 1
rel=NEXT  -> rstac::links(rel=="next") matches 0
rel=Next  -> rstac::links(rel=="next") matches 0
```

So a differently-cased `next` link is **inert** to `rstac::items_fetch()`. It cannot produce
the duplicate-features outcome the strip exists to prevent — which is the *only* stated reason
for stripping at all (`@return` docs, `R/dft_stac_fetch.R:53-55`). The comment asserts a hazard
that measurement says does not exist.

The direction the change *does* have is the harmful one. Against a server that emits
`rel="NEXT"`, rstac silently stops after page 1 — precisely the #51 truncation — and on
Planetary Computer neither of drift's two guards can see it: `items_matched()` is NULL (an
established fact of this PR), and a truncation produces no duplicate ids. The surviving
`NEXT` link was the last local trace that the server had advertised more pages. Stripping it
case-insensitively deletes that trace, so the failure becomes wholly silent.

This is the `code-check.md` shape "a guard placed mid-operation can be defeated by the
operation itself", one step over: the guard destroys the evidence of the bug it exists to
serve.

**Suggested:** match rstac's matcher exactly (`identical(l$rel, "next")` — the `bbb679a`
parent's behaviour), and treat a surviving case-variant `next` as something to *surface*
rather than delete — a `cli::cli_warn()` naming it is enough, since it means rstac did not
page and the item set may be short. If the case-insensitive strip is kept, the comment at
:278-281 needs to stop claiming a duplication hazard, because there isn't one.

---

### 3. [fragile] Two id-less items abort with a diagnosis that names the wrong cause

`R/dft_stac_fetch.R:264-275`. Measured, with two features carrying no `id`:

```
rlang_error : STAC paging returned duplicate item id: NA.
              ℹ Pages overlapped — the item set cannot be trusted.
```

The pages did not overlap. The items are malformed (STAC requires `id`), and the `NA`
sentinel introduced at :266 collapses "no id" into "same id". The abort direction is safe,
but the message sends the reader to debug pagination against a server whose items simply
lack ids — the `code-check.md` "the error names a function nobody wrote" family.

Two adjacent measurements from the same probe:

- **One** id-less item passes silently (`ids = NA_character_`, no duplicate) and goes on to
  `gdalcubes::stac_image_collection()`.
- An `id` of length != 1 escapes as a raw vapply error rather than a drift diagnostic:
  `values must be length 1, but FUN(X[[1]]) result is length 2`.

**Suggested:** split the check — `if (anyNA(ids)) cli_abort("... item{?s} with no id ...")`
before the duplicate test, so the two failures report as the two different things they are.

---

### 4. [fragile] The roxygen claim that "PC clamps `limit` to its own cap regardless" is unmeasured, and `limit = 500` is now sent to every `stac_url`

`R/dft_stac_fetch.R:235-237`. PC's maximum is above 500, so no clamping is exercised by this
code — the sentence asserts behaviour the change never reaches. Low-confidence but concrete
consequence: before this diff no `limit` parameter was sent at all, and `dft_stac_fetch()`
documents arbitrary `stac_url` / `collection` / `asset` ("works with any classified raster").
A third-party STAC server whose maximum page size is below 500 and which returns HTTP 400
rather than clamping would now fail where it previously worked. Untested in either direction.

**Suggested:** drop the clamping claim (or measure it), and say instead what is actually
known — 500 is a round-trip reducer chosen to match `dft_stac_cube()`, and `items_fetch()` is
what makes the result complete.

---

## Checked and clear (measured, not reasoned)

Adversarial input to `stac_items_paged()`, via a probe that swapped `get_request` /
`items_fetch` / `items_sign` / `items_matched` in `asNamespace("rstac")`:

| input | result |
|---|---|
| zero features | returns a 0-feature `doc_items`; caller's `n_items == 0` stop fires. No `vapply`/`anyDuplicated` error on `character(0)`. |
| one feature | clean |
| one feature, `id` NULL | clean (see finding 3 for the caveat) |
| integer `id`s | `as.character()` coerces; clean |
| `links = NULL` | `Filter()` returns NULL, so the `links` element is *removed* (`names`: `type,links,features` → `type,features`). Harmless: `rstac::links()` on an absent `links` returns length 0, so `items_next()` raises `next_error` and `items_fetch()` breaks normally. |
| `links = list()` | preserved as `list()` |
| a link with no `rel` | **kept** (`l$rel` is NULL, the `is.character()` test is FALSE) — correct |
| `rel = "NEXT"` | stripped (this is finding 2, not a defect in isolation) |

Other checks:

- **`doc_items` validity after the `$links` rewrite** — class survives as
  `doc_items, rstac_doc, list`, and `attr(items, "query")` (which `items_next()` needs for the
  POST path) survives the `$<-`. Measured, both TRUE.
- **`items_matched` guard** — correct for NULL and `numeric(0)` (both skip), for `NA` (skips),
  and for a scalar mismatch (aborts). The `n_items > matched` arm is unreachable because
  `rstac:::items_fetch.doc_items` raises first; the reachable arm is `n_items < matched` after
  the next-link chain ends, which is the useful case. It does silently skip for
  `length(matched) > 1`, but `items_matched()` returns `items$numberMatched` or
  `items$context$matched`, both JSON scalars — not reachable in practice.
- **cli pluralization** renders correctly at n = 1 and n = 2 for both abort messages.
- **Downstream assumptions** — `dft_stac_fetch()` reads only `items$features`;
  `attr(, "stac_items")` is consumed by `dft_stac_classes()`, which does not touch `$links`.
  Swept `R/` for `get_request()` / `post_request()` (positive control: the sweep returns 2 hits
  in the file under review, so it can match): the only two call sites are :248 here and
  `dft_stac_cube.R:290`, and both are followed by `items_fetch()`. `dft_stac_cube()` already
  pages *then* signs, so the two paths agree.
- **Test suite** — `test-dft_stac_fetch.R`: `FAIL 0 | WARN 0 | SKIP 3 | PASS 62`.
- **The two headline tests can actually fail** (restore-the-bug, both restored from source
  rather than from memory):
  - `stac_items_paged` signs-after-paging: replaced the helper with a sign-then-page version
    → **3 failures**, including the target test.
  - `dft_stac_fetch routes its STAC query through stac_items_paged`: restored the pre-#51
    `dft_stac_fetch` via `git show $(git merge-base main HEAD):R/dft_stac_fetch.R` → the file
    goes red (**1 errored test**). A file-based marker confirmed the restored body actually
    executed, and a first `grep -E "Failure"` over the summary reporter *missed* it because
    testthat classes it as an error, not a failure — worth recording, since that grep would
    have reported a test that cannot fail as clean.
- **`devtools::document()`** produces no diff in `man/` or `NAMESPACE`.
- **`.Rbuildignore`** covers `^planning$` and `^dev$`, so the new PWF files do not ship.
  (`.git` is a directory here, not a worktree file, so the `^\.git$` gap does not apply.)
- **Cache key** — `limit` correctly stays *out* of the key: it changes page size, not the item
  set, and the network test pins `expect_identical(ids(small), ids(big))` so ordering is
  measured rather than assumed. The salt break and the two frozen-hash tests are consistent
  with each other at HEAD.

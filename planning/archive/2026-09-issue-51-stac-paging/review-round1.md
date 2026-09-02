# Review — round 1 (#51, `stac_items_paged()` paging fix)

Reviewer: code-review subagent. Branch `51-dft-stac-fetch-pages-to-exhaustion`.
Reviewed: staged diff at `/tmp/cc_diff.txt`, `R/dft_stac_fetch.R`,
`tests/testthat/test-dft_stac_fetch.R`, `R/dft_stac_cube.R` (sibling), plus
`~/.claude/conventions/code-check.md` item by item.

**The branch moved under me during the review.** The diff I was handed was
`fc2e861`; by the time I finished, the tip was `e8a30ea` via `bbb679a` (the
case-insensitive strip), `acc3243` (release v0.10.0) and the PWF archive. Every
finding below is re-verified against the **current tip**, and findings 1 and 2
are about that movement rather than about the original diff.

---

## Findings

### 1. **[bug]** `fc2e861` is in the branch history and does not parse — and the repair rode into `bbb679a` unannounced

**The cause is mine.** I ran defect-restoration cycles (restore the bug, run the
suite, restore the source) **in the live shared checkout** instead of a
`git worktree`. `fc2e861` was committed at 18:55:10 while one cycle had
`R/dft_stac_fetch.R` in its mutated state on disk, and the commit captured it.

Measured, per commit on this branch:

```
fc2e861  BROKEN   Page dft_stac_fetch() to exhaustion; break the fetch cache key (#51)
bbb679a  OK       Strip the stale next link case-insensitively (#51)
acc3243  OK       Release v0.10.0 (#51)
e8a30ea  OK       Archive planning files for issue #51
```

```
$ git show fc2e861:R/dft_stac_fetch.R > /tmp/h.R; Rscript -e 'parse("/tmp/h.R")'
PARSE FAIL: /tmp/h.R:300:28: unexpected symbol
299:                            resampling, stac_url, collection, asset      <- comma dropped
300:                            tile_size
```

`fc2e861` also lacks the `"items-paged-v2"` salt line, so even setting the parse
error aside its `stac_cache_key()` would not produce `2264b5dbef6e` — the frozen
hash its own test and commit message assert. Its message reports *"Offline suite
458 pass"* over a tree that will not `load_all()`: the verification was real, the
artifact committed was not the artifact verified (`code-check.md`, *"Running a
generator is not committing what it generated"*).

**The tip is healthy** — I re-verified rather than assuming: `HEAD` parses,
`stac_cache_key()` on the frozen fixture returns `2264b5dbef6e`, and
`testthat::test_local()` is green except the pre-existing cube-key failure.

Two things still need a decision:

- **`bbb679a` carries the repair as an undeclared side effect.** Its message is
  entirely about case-insensitive `rel` matching and its verification line is
  *"restoring the exact-match form: FAIL=2"*; the diff also silently restores the
  signature comma and the salt line. Anyone reading that commit to understand
  the case-insensitivity change gets two unrelated hunks with no explanation, and
  anyone reading `fc2e861` to understand the cache break finds the salt absent
  from the commit that claims to introduce it. Same class as `code-check.md`'s
  *"`git add -A` after a generator sweeps its side effects into your commit"*.
  Cheapest honest fix, since none of this is pushed yet: an interactive rebase
  folding `bbb679a`'s two `stac_cache_key` hunks back into `fc2e861` where they
  belong, leaving `bbb679a` as the pure case-insensitivity change it says it is.
- **A non-building commit in history matters or does not, depending on the merge
  mode.** Squash-merged, it disappears. Merged with history preserved, `git
  bisect` and any CI that builds intermediate commits hit a package that cannot
  be installed. Decide deliberately rather than by default.

Whichever route: verify by parsing the committed blob, not by a clean
`git status`.

```bash
for c in $(git rev-list main..HEAD); do
  git show "$c:R/dft_stac_fetch.R" > /tmp/c.R 2>/dev/null &&
  Rscript -e 'q(status = tryCatch({parse("/tmp/c.R"); 0}, error = function(e) 1))' &&
  echo "$c OK" || echo "$c BROKEN"
done
```

**Worth carrying past this incident.** `CLAUDE.md` already says one worktree per
session. A **review** agent that restores defects is a writer like any other, and
this is the failure mode it warns about, arriving from a direction the rule does
not name. Two cheap guards: restoration harnesses run in
`git worktree add /tmp/<repo>-review --detach`; and on any branch where a
mutation harness has run, gate the commit on parsing the *blob*.

---

### 2. **[bug]** `DESCRIPTION` says `Version: 0.10.0` and `acc3243` is a release commit, but `devtools::test()` is red

```
══ Failed ══
── 1. Failure ('test-dft_stac_cube.R:62:3'): stac_cube_cache_key untiled key is …
Expected `cube_key()` to equal "638a2be11fdf".
`actual`:   "45685ccbda33"
`expected`: "638a2be11fdf"
```

I confirmed this is **not** caused by #51 — the branch touches neither
`R/dft_stac_cube.R` nor `tests/testthat/test-dft_stac_cube.R`
(`git diff --name-only main...HEAD`), both were last modified in #47 on `main`,
and `stac_cube_cache_key()` shares no code with `stac_cache_key()`.

It is still a release blocker rather than someone else's problem, because
`acc3243` cuts 0.10.0 over it. `v0.10.0` is **not tagged yet** (tags stop at
`v0.9.0`), so this is catchable now at zero cost. Two possibilities and they
need different actions:

- The cube frozen hash drifted for a *legitimate* reason on `main` (a dependency
  changed what `rlang::hash()` produces for one of its parts — `sort(as.numeric(NULL))`
  and the `band_assets` character vector are the candidates worth checking
  first). Then it is a deliberate re-freeze plus a NEWS line, and cube caches
  rebuild once — which nobody has decided.
- Something genuinely regressed the cube key. Then 0.10.0 must not ship.

Either way, releasing on a red suite makes the next red suite unremarkable.
Settle it before tagging.

---

### 3. **[fragile]** `R/dft_stac_fetch.R:302` — the `stac_cache_key()` roxygen contradicts the code it documents

Still present at tip:

```r
#' `tile_size` (the download-tiling grid, #36)
#' is appended to the hash ONLY when non-NULL, so an untiled fetch keeps the
#' exact legacy 9-element hash (existing caches stay valid) while a tiled fetch
#' keys distinctly.
```

Both parenthesised claims are now false: `parts` is **10** elements for an
untiled fetch, and existing untiled caches are **deliberately invalidated** —
that is the whole point of the salt.

This matters more than an ordinary stale comment because of what it invites. The
function body carries a nine-line comment ending *"Do not remove it"*, and its
own header says the opposite four lines above. The next person to reconcile the
two has one comment saying the salt is load-bearing and one saying untiled caches
stay valid, with only the tests breaking the tie
(`code-check.md`: *"a comment explaining why a shortcut is safe is load-bearing,
and its premises expire"*).

Reword to name the break — e.g. *"…so a tiled fetch keys distinctly from an
untiled one. The parts list also carries a constant salt (#51); untiled keys
moved once, deliberately, at v0.10.0 — see the comment in the body."*

The exported `@details` at lines 8-13 has the milder version: it enumerates what
the key hashes and says *"Repeat calls with the same AOI and parameters reuse the
cache"*, with nothing telling an upgrading user their cache rebuilds once.
`NEWS.md` covers it; one sentence in `@details` would too, and that is what
`?dft_stac_fetch` shows.

---

### 4. **[fragile]** `limit` sets the page boundaries, is absent from the cache key, and the test file asserts item order is output-visible

The network test states the coupling itself:

```r
# identical ORDERED ids, not merely equal counts: item order is output-visible
# under aggregation = "first" where items share a datetime and overlap
expect_identical(ids(small), ids(big))
```

`stac_items_paged(limit = 500)` sets page size, page size sets where the `next`
token cuts, and `stac_cache_key()` does not hash `limit`.

**There is no current defect**, and the reason is worth stating precisely:
`limit` is a hardcoded internal default with one call site, so it cannot vary
between two calls and nothing can be mis-served today. Two things still make it
worth a line of prose:

- The helper's own roxygen invites the change — *"Revisit if this function ever
  gains `intersects` or a property filter"* — and `limit` is the obvious next
  argument to expose. The moment `dft_stac_fetch(limit = )` exists, two calls
  differing only in `limit` key identically and one is served the other's raster.
  That is drift#25 recurring exactly, in the function whose docstring is
  `code-check.md`'s worked example for *"Cache keys must cover every
  output-affecting input"*.
- The evidence may cut the other way, which is the cheaper resolution: if
  `expect_identical(ids(small), ids(big))` passes live (the commit message reports
  74 pass against PC), PC's ordering is limit-independent and `limit` is **not**
  output-affecting — in which case record that where the key is defined so nobody
  re-derives it.

One comment either way:
`# limit is deliberately out of the key: PC item order is limit-independent (measured #51)`,
or add `as.numeric(limit)` to `parts` when the argument is ever exposed.

Minor and related: `expect_identical(ids(small), ids(big))` is the most breakable
assertion in the file — PC documents no stable sort across page sizes, so a
server-side ordering change reddens it for a non-defect. Keep it (order really is
output-visible), but a comment naming it as the likely-upstream failure would save
someone a bisect.

---

### 5. **[fragile]** the `items_matched()` guard aborts on any disagreement, and some STAC servers report an *estimated* `numberMatched`

```r
matched <- rstac::items_matched(items)
if (!is.null(matched) && !is.na(matched) && n_items != matched) cli::cli_abort(...)
```

`dft_stac_fetch()` is documented as generic — *"Works with any STAC collection
hosting single-band classified rasters (IO LULC, ESA WorldCover, custom COGs)"* —
so Planetary Computer is not the only target. pgstac / stac-fastapi (the stack
behind NGE's own `stac_floodplains_bc` and `rtj` catalogues) has a context
extension that can return an **estimated** count above a row threshold. Against
such a catalogue a *complete* fetch would abort — `code-check.md`'s *"A guard must
not fail toward 'abort' either"*.

**I have not verified this against a live pgstac instance**, and I am naming the
evidence level rather than asserting the finding. One request settles it:

```bash
curl -s '<pgstac-endpoint>/search?collections=<c>&limit=1' | jq '.numberMatched, .context'
# repeat on a collection large enough to cross the estimate threshold
```

If exact, the finding evaporates and deserves one comment saying so. If
estimated, keep the abort for `n_items < matched` (genuine truncation, the thing
#51 is about) and warn on `n_items > matched` — over-count against an estimate is
benign, under-count is not.

The guard is not redundant with rstac: `items_fetch.doc_items` errors only on
`items_length > matched` and otherwise breaks its loop silently, so drift's `<`
arm is the one that adds reach.

---

## Checked and clear

Recording these so they are not re-litigated. Each was measured, not reasoned about.

**Q1 — zero-item, single-item and NULL-id cases in `stac_items_paged()`.** Safe.
- Zero items: `vapply(list(), …, character(1))` → `character(0)`;
  `anyDuplicated(character(0))` → `0L`; `Filter(f, NULL)` → `NULL`; `items_sign()`
  on an empty feature list is a no-op. `dft_stac_fetch()`'s `n_items == 0` abort
  then fires as before.
- Single item: no duplicate; `matched` NULL on PC; the strip is a no-op with no
  `next` link.
- NULL id: mapped to `NA_character_`, so one such item passes and two abort naming
  `NA` — an odd message for a malformed response, but the direction is right and
  STAC requires `id`.
- `!is.null(matched)` is load-bearing, not padding: `is.na(NULL)` is `logical(0)`
  and `logical(0) && TRUE` errors, so dropping it breaks every PC fetch. Covered by
  *"does not abort when items_matched is absent (the PC case)"* — which is what the
  commit message's "zero-length matched FAIL=1" restoration was measuring.

**Q2 — can any new test pass against the defect it rejects?** No. I re-derived the
restorations independently rather than trusting the commit message; all go red
against a green control:

| restoration | tests failing |
|---|---|
| remove `items_fetch()` (the original bug) | 2 |
| move the sign before paging (and drop the trailing sign) | 1 |
| drop only the trailing sign | 1 |
| remove the link strip | 1 |
| exact-match strip instead of case-insensitive (`bbb679a`'s defect) | 2 |
| disable the duplicate-id guard | 1 |
| disable the `items_matched` guard | 1 |
| drop `limit = limit` from `stac_search()` | 1 |
| revert `dft_stac_fetch()` to the inline pipeline | 1 |
| **unmodified tree (control)** | **0** |

Two notes on method, which matters more here than the result:
- A first draft of *"sign before page"* added an early `items_sign()` while leaving
  the trailing one. **That passes** — the trailing sign re-marks everything — so it
  is not the defect. The real restoration must *move* the call. Any future
  re-verification needs the same care.
- The salt restoration must remove the salt **and** the preceding comma in the
  `parts` list, not in the signature. Getting that wrong is what produced finding 1.

The wiring test earns its place: booby-trapping `rstac::get_request()` while
asserting on the ids the stubbed `stac_image_collection()` received means the
inline pipeline produces a *different* error offline, so the assertion depends on
the helper having been called. Correct repair of the could-not-fail first draft.

**`bbb679a`'s case-insensitive strip reviewed on its own terms — correct.**
`!(is.character(l$rel) && length(l$rel) == 1L && tolower(l$rel) == "next")` orders
its `&&` so `tolower()` never sees a non-character, keeps a `rel`-less link
(`is.character(NULL)` is FALSE), and cannot trip the Turkish-locale `tolower`
hazard (`"next"` has no `i`). It strips slightly more than rstac would follow —
`items_next.doc_items` matches `rel == "next"` exactly — which is the safe
direction, and RFC 8288 makes link relation types case-insensitive anyway, so the
looser match is also the more correct one. Its test can fail against the exact-match
form on both assertions (`length(out$links) == 2L` and
`any(tolower(rels) == "next")`).

**Q3 — does stripping `items$links` break anything downstream?** No.
- `dft_stac_classes()` → `stac_classes_from_items()` reads
  `items$features[[1]]$properties` only.
- `rstac::items_sign.doc_items` is `check_items()` + `foreach_item()` — features
  only; `check_items()` requires `type`, `features` and a named list, none of which
  the strip touches.
- `$<-` preserves `class` and `attr(items, "query")`, so the object handed to
  `items_sign()` and attached as `attr(, "stac_items")` is still a valid `doc_items`.
- Nothing in `R/`, `vignettes/` or `data-raw/` reads `$links` or
  `attr(, "stac_items")`.

**Q4 — ordering of guards vs signing vs link-stripping.** Correct. Guards run on the
paged-but-unsigned set (cheapest point, and signing a set you are about to reject is
wasted work); the strip is last before signing; signing is last so page-2 assets are
covered. Verified by restoration, not by reading.

**Q5 — mock leaks.** None. testthat 3.3.2's `local_mocked_bindings()` rebinds into
the namespace, its parent, `globalenv()`, the S3 methods table, the attached
`package:` env *and* `the$testing_env`, all with `.frame = parent.frame()` — the
`test_that()` frame — so every rebind unwinds at the end of its block. Empirically:
the file is green, and the baseline control held at `nfail = 0` after ten
mutate/restore cycles in the same process tree. The un-`.package`'d
`stac_items_paged` mock resolves via `testthat:::dev_package()`, which returns
`testing_package()` under both `test_local()` and `test_check()`, so it works under
`R CMD check` as well as `devtools::test()`.

**Silent-truncation modes other than the one fixed.** `items_fetch()`'s
`tryCatch(…, next_error = function(e) NULL)` looks like it could swallow a network
failure mid-paging — which would be #51 again on a catalogue with no
`numberMatched`. It does not: `next_error` is raised in exactly one place,
`items_next.doc_items`'s *"Cannot get next link URL"*. Transport and non-200
failures come out of `make_get_request()` as ordinary errors and propagate.
`inst/notes/gdalcubes-pc-gotchas.md` already records this correctly.

**Rest of the `code-check.md` sweep, no hits.** Empty-result-as-pass (every paged
test asserts something positive; the `expect_setequal` on link rels fails on
`character(0)`); vacuous `expect_match` / `all()` (each preceded by a length
assertion — `expect_equal(length(out$features), 2L)`,
`expect_gt(length(small$features), 1L)`); tests that silently do not run (no
`expect_snapshot`, no `skip_on_cran`; network skips explicit and opt-in per repo
convention); guard escape hatches (no exemption lists, no container-vs-file
lookups); zero-length values (above); `paste0()`/`sprintf()` on empty frames (none
introduced); hardcoded paths, shell quoting, `system2()`, secrets — none in the
diff. The SAS-token assertion is `expect_match(href, "\\?")`, which does not print
a credential.

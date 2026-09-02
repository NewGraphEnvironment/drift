# Progress — dft_stac_fetch() reads one STAC page (#51)

## Session 2026-09-01

- Plan-mode exploration; measured PC paging behaviour live at four page sizes before
  proposing anything (see `findings.md`)
- Measurement contradicted the issue's suggested fix: the `next` link survives a
  successful `items_fetch()`, so the proposed "error when a next link survives" guard
  would abort every correctly-paged fetch. Confirmed at rstac source.
- Phases approved by user
- Plan-agent review returned concurrently with 3 blockers, all verified real before
  folding in: stale truncated caches survive the fix; the stale `next` link would reach
  callers via `attr(, "stac_items")`; a fixed-return mock cannot detect sign-before-page
- Created branch `51-dft-stac-fetch-pages-to-exhaustion` off main
- Scaffolded PWF baseline with the reviewed phases
- Phases 1-5 implemented; Phase 6 docs done, version bump pending as final commit
- **Restore-the-bug harness run over 7 defects.** Baseline FAIL=0; all six helper/cache
  defects go red (FAIL 2, 1, 2, 1, 1, 9). The seventh — `dft_stac_fetch()` bypassing the
  helper via the old inline pipeline — measured **FAIL=0**, i.e. the wiring test as first
  written could not fail: it asserted only that a stubbed `stac_image_collection()` was
  reached, which the inline pipeline satisfies equally. Rewritten so the stub reports the
  item ids it received and `rstac::get_request()` is booby-trapped; now FAIL=1 against the
  defect. Found only by restoring the defect, not by reading.
- Offline suite: 458 pass. With `DRIFT_TEST_NETWORK=true`: 74 pass, 0 fail on the fetch
  file — paging verified against live Planetary Computer.

## Out-of-scope defects found on main (NOT introduced here)

- `test-dft_stac_cube.R:62` — the cube's frozen cache-key guardian fails:
  expects `638a2be11fdf`, gets `45685ccbda33`. Verified pre-existing by stashing this
  branch's changes. Bisected to the commit that **introduced** it (`90f9d93`, #38) and
  every commit since — it has never been green on this machine. `stac_cube_cache_key()`
  is a separate function and is untouched by #51.
- **drift has no CI workflow that runs the test suite** — `.github/workflows/` holds only
  `pkgdown.yaml` and `update-citation-cff.yaml`. That is why the above went unnoticed for
  a release cycle: every CI run is green because nothing runs the tests.

- Next: `/code-check` rounds, then version bump, archive, PR

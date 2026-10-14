# Progress — gdalcubes read failures after open, mask-open failures and worker crashes are still silent (#99)

## Session 2026-10-14

- Plan-mode exploration (started 2026-10-02): phases and three gate decisions approved by user
- Created branch `99-gdalcubes-read-failures-after-open-mask` off main
- Scaffolded PWF baseline from issue #99 with approved phases
- Next: start Phase 1 (gdalcubes fork fix)
- Plan review (Plan agent) returned: 3 blockers (1 already handled, 2 adopted), gaps folded
  into the fork patch; written to `review-plan.md`
- Phase 1: fork cloned, branch `99-chunk-status-read-failures` off upstream `ed68331`; patch +
  tinytest (30 assertions, 10 fail on 0.7.5, all pass patched); 157/157 suite
- Phase 2: hang reproduced only for a worker killed at startup; mechanism = log-printing loop;
  fixed + tested on the fork branch (fork commits 83eea4c..4175ee1, not yet pushed)
- Phase 3: `stac_features_masked()` wired into `stac_cube_items()`; mutation (unwired) -> 5 fails
- Fork `/code-check` round 1 running
- Fork code-check round 1: 2 findings, both fixed (one inside the G1 fix); round 2 spawned
- Phase 4: fixture writes DEFLATE COGs, can corrupt or delete B04 or SCL; lazy memoised probe at
  parallel 1 and 2 with a forced override; gated tests + ungated production-shape mask-open test +
  composite SCL test; abort text, roxygen and gotchas notes updated
- Fork code-check round 2: 1 pre-existing finding (warp_complex overview transformer type), out
  of scope, in the upstream draft. Round 3: mechanism + 39-row enumeration; every branch-introduced
  row consistent -> loop ended by enumeration. Fork `master` synced with upstream.
- Drift code-check round 1: 3 findings fixed — probe cross-checked against an independent SCL read
  (mutant probe -> fails), `drift_no_mask_items` subclass with its own composite skip reason,
  `tif_corrupt_tile()` asserts classic TIFF and one tile
- Drift code-check round 2: 1 finding (message test matched fixed text, not the id) fixed; no defect inside round-1 fixes; reviewer's mutations (probe FALSE, handler order) went red
- Drift code-check round 3: mechanism (checks written from the same belief they test) + a walk of
  every new assertion/guard with mutations; 2 rows passed with their defect: the probe's
  parallel 1-vs-2 comparison (workers run at every parallel, so it cannot fire) — removed; the
  ungated deleted-SCL test used the helper's copy of drift's shape — added a real-path composite
  test, which fails under M9 (select_bands() in stac_cube_assemble()). Loop ended by that
  enumeration.

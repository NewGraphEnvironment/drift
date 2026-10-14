# Review: drift #99, round 1

Branch `99-gdalcubes-read-failures-after-open-mask`, diff vs merge base with origin/main (planning/ excluded).

## What was run

- `NOT_CRAN=true devtools::test(filter = "dft_stac_(cube|composite|fetch)")` on installed gdalcubes 0.7.5:
  `FAIL 0 | SKIP 13 | PASS 537`. The three new gated tests skip with the drift#99 reason; the #87
  tests (including `"9 of 279"`) pass on the COG fixtures.
- Same with `R_LIBS=<scratchpad>/lib` (patched gdalcubes): `FAIL 0 | SKIP 10 | PASS 543`. The gated
  tests run and pass.
- `DRIFT_TEST_ASSUME_READ_STATUS=true` on 0.7.5 (cube + composite): `FAIL 6`. That is the band-corrupt
  test x2 parallel, the SCL-corrupt test x2, and the composite SCL test (expect_error + cache-empty).
  So the gated tests fail without the fix and are not vacuous.
- The cli drop message renders correctly: `Dropped 1 item ... : "b".` and `Dropped 3 items ... : "a",
  "b", and "c".` The `{?s}` binds to `{n}`, and the single-backslash continuation renders as one line.
- The roxygen claim that a deleted SCL is recorded on 0.7.5 in drift's read shape was checked for the
  count path too. `reduce_time(cube, "count(B04)")` with no `select_bands()` gives 9 of 9 chunks failed
  at parallel 1 and 4, so the claim holds for all three of drift's pixel functions.
- is_pre alignment and the re-sign source are both correct. The drop runs before `is_pre`, and
  `items$features` is reassigned, so `fetched$items` carries the filtered set. The new
  `stac_cube_items` test would fail if the drop moved after `is_pre`.
- Probe scoping is correct. The tempdir is deferred to the probe closure's frame and removed after the
  answer is computed. A forced env value is returned before the memo, so it never leaks into the
  cached answer. `withr::local_envvar` restores the variable at the end of the test.

## Findings

- **[fragile]** tests/testthat/test-dft_stac_cube.R:1213-1220 — The test is titled "the capability
  probe agrees with the installed gdalcubes's own record", but it only checks the
  `DRIFT_TEST_ASSUME_READ_STATUS` override. The real probe path (no env var, the corrupted-band write at
  parallel 1 and 2) has no test.
  - The gate fails toward pass. If the probe ever returns FALSE on a patched gdalcubes, all three
    gated tests SKIP silently and the run stays green. That could happen if the corrupted fixture stops
    failing under a later GDAL, or if the probe's fixture drifts from the tests' fixtures.
  - The premise test (`:1202`) only partly covers this: it shows terra cannot decode the tile, not that
    gdalcubes records it.
  - Related: helper-gdalcubes.R:289 accepts only the exact string `"true"`. `TRUE` or `1` read as FALSE
    and skip the tests, which is the opposite of what someone forcing them wants.
  - Either retitle the test to what it checks, or have it assert that the probe agrees with an
    independent read of the same fixture. Normalise the env value with `tolower()` and reject anything
    other than true or false.

- **[fragile]** R/dft_stac_cube.R:528-533 together with R/dft_stac_composite.R:316 — An all-dropped
  listing raises `drift_no_items`. `dft_stac_composite()` catches that class and turns it into
  `composite_skip(label, "no scenes")`, which throws away the new message ("N STAC items found ..., but
  none has the mask asset 'SCL'").
  - A catalogue or config that systematically lacks the mask asset therefore drops every year as
    "no scenes". It ends in "No year produced a composite ... try more `months` or a higher
    `cloud_cover_max`", which is a remedy that cannot work.
  - Nothing is cached and no wrong pixels result, so this is a misdiagnosis rather than data loss. The
    per-item `cli_inform` drop lines do still print beforehand.
  - Fix with a subclass (e.g. `c("drift_no_mask_items", "drift_no_items")`) that the composite lets
    through or reports with its own reason, or have `composite_skip` use `conditionMessage(e)`.

- **[fragile, latent]** tests/testthat/helper-gdalcubes.R:233-250 — `tif_corrupt_tile()` treats the
  TileOffsets value field as the first tile's offset. That is true only while the tag's count is 1,
  which means one tile.
  - All current fixtures are single-tile: 40x40 px, and the composite AOI is about 326x313 px, under the
    COG's 512 block.
  - A larger `ext` would make the value a pointer to the offsets array, so the 64 bytes would overwrite
    offsets rather than tile data. The `stopifnot` would not notice.
  - The function also checks `"II"` but not the classic-TIFF magic (42 vs BigTIFF 43).
  - Asserting count == 1 (read the 4-byte count instead of skipping it) and magic == 42 keeps the
    fixture's meaning fixed.

No bugs or security issues found in the R/ changes themselves.

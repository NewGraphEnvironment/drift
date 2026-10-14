# Review: drift #99, round 2

Branch `99-gdalcubes-read-failures-after-open-mask`, diff vs merge base with origin/main (planning/ excluded),
with most attention on the round-1 fixes in a26b292.

## What was run

- `NOT_CRAN=true devtools::test(filter = "dft_stac_(cube|composite)")`:
  - On installed gdalcubes 0.7.5: `FAIL 0 | SKIP 9 | PASS 381`. The three gated tests skip with the drift#99 reason.
  - With `R_LIBS=<scratchpad>/lib` (patched build): `FAIL 0 | SKIP 6 | PASS 387`. The gated tests run.
- Mutation 1 was run in a copy of the repo against the patched build. The probe was made to answer FALSE
  (`answer <<- FALSE`). The ungated cross-check test failed (`test-dft_stac_cube.R:1228`), so a probe that wrongly
  says FALSE no longer turns into a silent skip.
- Mutation 2 was run in a copy of the repo on 0.7.5. The `drift_no_items` handler was put before
  `drift_no_mask_items` in `dft_stac_composite()`. The new composite test failed on both its warning assertions
  (`:183`, `:184`), so it exercises the real handler.

## Round-1 fixes: checked, no defect

- **tryCatch ordering.** Within one `tryCatch`, the first handler listed whose class the condition inherits wins.
  So `drift_no_mask_items` listed first is correct, and mutation 2 confirms it.
- **Callers and catchers.** There are only two callers of `stac_cube_items()`. `dft_stac_cube()` does not catch the
  class, so the new message propagates. `dft_stac_composite()` has the new handler. Nothing else in R/, data-raw/ or
  the vignettes catches `drift_no_items`. `dft_stac_fetch()` has its own plain `stop()`.
- **The cross-check cannot pass vacuously in the direction that matters.**
  - On 0.7.5 both sides are FALSE, which is the correct answer.
  - On the patched build both are TRUE.
  - For both sides to be FALSE on a fixed gdalcubes, the corruption would have to stop failing to decode. That is
    ruled out: 0xAB as a zlib CMF byte has CM=11 (not 8), so every zlib rejects it, and the ungated premise test
    checks it through terra.
- **Memoisation.** A forced value returns before the memo is read, so the memo only ever holds a real answer.
  `withr::local_envvar(X = NA)` unsets the variable. The loop of `local_envvar` calls in the forced-answer test
  restores LIFO to the original state.
- **Missing `chunk_status`.** On a gdalcubes without `chunk_status`, the probe gets `NA` and errors at
  `if (seen[1] != seen[2])`. That fails loudly (an error, not a skip), and production aborts on the same case.
  Acceptable.
- **`tif_corrupt_tile()` asserts.** The new asserts on magic 42 and on the TileOffsets count are correct for
  GDAL's LONG-typed field. Every fixture is a single 512-block tile.

## Findings

- **[fragile]** tests/testthat/test-dft_stac_cube.R:1146-1148: the assertion
  `expect_message(..., "1 item.*SCL.*b")` cannot check that the dropped item's id is named.
  - The trailing `.*b` is already satisfied by the `b` in "gdal**c**u**b**es" in the fixed text of the message.
  - Measured: `grepl("1 item.*SCL.*b", 'Dropped 1 item with no "SCL" mask asset, which gdalcubes would read unmasked: .')`
    is TRUE with no id at all.
  - So the part of the message the user needs most (which items were dropped) has no test. The drop itself is
    pinned by the `expect_equal` on the ids.
  - A distinctive id (e.g. `"no_scl_item"`) would make the assertion real.

No bugs or security issues found in the R/ changes.

/Users/airvine/Projects/repo/drift/planning/active/review-drift-round2.md

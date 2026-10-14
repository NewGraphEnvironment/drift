# Code-check round 3: drift changes for #99

Reviewed at e975940 (`99-gdalcubes-read-failures-after-open-mask`), diff against the merge base with origin/main, planning/ excluded. Both suites green at HEAD: unpatched 0.7.5 `[ FAIL 0 | SKIP 9 | PASS 381 ]`, patched (`R_LIBS=<scratchpad>/lib`) `[ FAIL 0 | SKIP 6 | PASS 387 ]`. Every mutation below ran in a `cp -r` copy under `scratchpad/r3/`. The repo was not edited.

## Mechanism

All four earlier findings share one shape. Each check encodes a belief about something outside the code: how gdalcubes runs, how a TIFF is laid out, which handler a condition reaches, what a message's fixed text contains. The check was then written from that same belief, so it agrees with itself and nothing makes it face the case where the belief is wrong:

- the probe's FALSE was never compared with a read the probe did not perform;
- the "no scenes" routing was never fed the new class;
- `tif_corrupt_tile()` assumed its input's layout instead of checking it;
- the regex `.*b` was never run against a message that lacked the id.

The fix in every case was to make the check answer to something independent of the belief. That same mechanism reaches two more places in this diff:

1. **`read_failures_recorded()` assumes `parallel = 1` reads in-process.** Its comparison of parallel 1 with parallel 2 is built on that assumption. gdalcubes' `.onLoad` and `gdalcubes_options()` both call `gc_set_process_execution()`, so every read at every `parallel` value, 1 included, runs in Rscript workers. The comparison therefore always measures the same library.
2. **The ungated "drift's read shape" test assumes `production_pixel` is drift's read shape.** It is the helper's copy of that shape. The test reads the copy, not `stac_cube_assemble()`, so it cannot see drift moving away from the shape.

## Assertions and guards (table)

How each check was tested:

- **M1 to M9:** a mutant run through `devtools::test(filter = ...)` in a temp copy.
- **P:** a direct probe script.
- **R:** reasoning only, for a check whose defect is unreachable or trivially covered.

| location | guards against | passes with the defect? | evidence |
|---|---|---|---|
| R/dft_stac_cube.R:570 `is.null(mask_asset) \|\| length==0` | NULL mask role / empty list erroring in `[[` | no | test :1147-1148; `list()[[NULL]]` errors without the guard (R) |
| R/dft_stac_cube.R:571 `[[mask_asset]]` exact | partial match of `SCL_20m` | no | M8 (`exact = FALSE`): :1154, :1155 FAIL |
| R/dft_stac_cube.R:572 `all(has_mask)` early return | a spurious message or copy when nothing is dropped | no | :1141-1142 (`expect_no_message`, `expect_identical`) |
| R/dft_stac_cube.R:530 drop placed before `is_pre` | `is_pre` misaligned with the read features | no | M3 (mask after `is_pre`): :1184 FAIL (plus :1191/1193/1194) |
| R/dft_stac_cube.R:531 all-dropped abort + `drift_no_mask_items` class | an all-no-mask listing reported as "no scenes" | no | M2 (class `drift_no_items` only): :1193 ERROR |
| R/dft_stac_composite.R:317 handler ordered before `drift_no_items` | the subclass caught by the "no scenes" handler | no | M1 (order swapped): composite :183 and :184 FAIL |
| test-composite :170 mocked condition class | stac_cube_items' real class drifting from the composite's handler | **yes on its own** (it builds its own class vector) | the routing is covered by cube :1193 through the real function (M2), so the pair holds. Not a finding |
| test-composite :173 `"the warnings say why"` | the old abort text | no | regex matches only the new text (R) |
| test-composite :183 / :184 | the wrong skip reason | no | M1 |
| test-cube :1133 regex `1 item.*SCL.*no_scl_item` | the id missing from the message | no | round-2 fix; the id is distinctive (R) |
| test-cube :1136, :1183, :1186 | the wrong features kept, or the items/features split diverging | no | M3; a copy-only mask would fail :1186 (R) |
| test-cube :1194 `"mask asset"` | the old "No STAC items" text | no | fixed text that only the new message has (R) |
| helper :53 `unlink(f)` (delete mode) | (no guard) a typo'd `break_asset`/date leaves the fixture clean, silently | would pass silently, **but** every delete-mode consumer expects an abort, so a clean fixture fails loud | R. Not a finding |
| helper :67 `stopifnot` `II` + 42 | BigTIFF / big-endian layout | no | P: a BigTIFF COG stops at the 42 check |
| helper :82 `stopifnot(count == 1L)` | a multi-tile file (offset array) | no | P: a 600x40 COG stops |
| helper :86 `stopifnot(!is.na(tile))` | a striped TIFF with no TileOffsets | no | P: a striped GTiff stops |
| helper :133-135 env override + validation | a typo'd override silently ignored | no | :1236-1244 (`"yes"` errors) |
| **helper :143 `seen[1] != seen[2]`** | **the session and workers loading different gdalcubes** | **yes: it cannot fire** | **P: patched session via `.libPaths()` with unpatched workers gives `FALSE` and no error (parallel 1 and 2 both report 0 of 279 failed); unpatched session with `R_LIBS=patched` workers gives `TRUE` and no error** |
| helper :155 `skip_if_no_read_failure_status()` | running gated tests on 0.7.5 | no | unpatched: :1248, :1274, composite :774 SKIP; patched: they run and pass |
| test-cube :1213 `file.exists(f)` | the `fixture_dir` attribute pointing elsewhere | no | R |
| test-cube :1215 premise `expect_error(values)` | the corruption not breaking the decode | no | M4 (write at tile+100000): :1215 FAIL |
| test-cube :1229 probe cross-check | the probe wrongly FALSE on a fixed gdalcubes | no (on the patched build) | M5 (probe view ends 07-10, before the broken scene): :1229 FAIL under the patched build. On 0.7.5 both sides are FALSE by design (accepted) |
| test-cube :1237/:1241/:1244 forced answer | the override broken | no | R; direct |
| test-cube :1253 band read-after-open | gdalcubes / `cube_check_chunks` missing it | no (patched); SKIP on 0.7.5, accepted | patched run |
| **test-cube :1267 "mask image that fails to open … in drift's read shape" (ungated)** | **drift's reads failing to record a deleted SCL on 0.7.5** | **yes** | **M9: added `select_bands(cube, band_assets)` before `pixel_fn` in `stac_cube_assemble()`. The suite stays `[ FAIL 0 \| PASS 256 ]` on 0.7.5. The same mutant through drift's real path (`composite_on_fixture(list("2021-07-13"), break_asset = "SCL", break_mode = "delete")`) FAILS: no `drift_incomplete_cube`, the scene is dropped silently. That real-path check passes at HEAD** |
| test-cube :1280 mask read-after-open | gdalcubes / `cube_check_chunks` missing it | no (patched); SKIP on 0.7.5 | patched run |
| test-cube :1289 clean control `expect_silent` | a false refusal | no | an abort would fail it (R) |
| test-composite :776 / :781 corrupt SCL, real path | a holed read cached | no (patched); SKIP on 0.7.5 | patched run; caching before the abort fails :781 (R) |

Also measured: the count path (`reduce_time("count(B04)")`) records a deleted SCL on 0.7.5, 9 of 279 chunks at parallel 1 and 4, so the roxygen claim also holds there. The composite fixture extent is 331 x 318 px, a single 512 tile, so the composite gated test is within `tif_corrupt_tile()`'s supported layout.

## Findings

### 1. `read_failures_recorded()`: the session-vs-worker guard can never fire (tests/testthat/helper-gdalcubes.R:124-147)

The comment says the probe runs "at parallel 1 and 2: worker processes load gdalcubes from R_LIBS, not from this session's .libPaths(), so the two can disagree, and that is an error rather than a skip". That rests on `parallel = 1` reading in-process, and it does not. gdalcubes calls `gc_set_process_execution(.pkgenv$parallel, ...)` in `.onLoad` with `parallel = 1` and again in every `gdalcubes_options()`, so both writes run in Rscript workers.

Measured with a patched session loaded through `.libPaths()` and no `R_LIBS`: `getNamespaceInfo("gdalcubes", "path")` is the patched lib, yet parallel 1 and parallel 2 both give `failed 0 / 279`, and the probe returns `FALSE` with no error. The reverse configuration (unpatched session, `R_LIBS` patched) returns `TRUE`, again with no error. The `stop()` at :143 is unreachable.

**Impact.** It is benign today, because drift's own reads also run in those workers, so the probe still reports the gdalcubes that actually does drift's reading. The cost is a promised protection that does not exist, a comment that misstates gdalcubes' execution model, and a wasted second fixture write.

**Fix.** Drop the parallel-1 write and the `seen` comparison. Say instead that every read runs in R_LIBS-loaded workers, so the probe measures the library drift's reads use. If a session/worker mismatch should be an error, compare something that actually differs: `find.package("gdalcubes")` in the session against one resolved in a subprocess carrying the same environment the workers get.

### 2. The ungated "drift's read shape" test reads the helper's copy of the shape, not drift's (tests/testthat/test-dft_stac_cube.R:1257-1269; helper :174)

The test, the `cube_check_chunks()` roxygen ("A deleted mask (SCL) image is caught the same way in drift's reads, because gdalcubes also reads the mask asset as a band there") and the notes table row all rest on drift never calling `select_bands()` before `pixel_fn`. The test pins that through `production_pixel`, a helper reconstruction, so it cannot see drift's real path change.

Measured (M9): inserting `gdalcubes::select_bands(cube, band_assets)` before `pixel_fn` in `stac_cube_assemble()` leaves the whole cube suite green on 0.7.5. Through drift's real path, the same deleted-SCL fixture then aborts nothing: the scene is dropped silently, the 0.7.5 behaviour the notes record for that shape.

**Fix.** Pin it through the real path instead of, or as well as, the helper shape. An ungated `composite_on_fixture(list("2021-07-13"), cache = cache, break_asset = "SCL", break_mode = "delete")` expecting `drift_incomplete_cube` plus an empty cache passes at HEAD on 0.7.5 and fails under M9.

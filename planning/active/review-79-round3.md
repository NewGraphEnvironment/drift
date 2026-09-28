# Review #79, round 3 (mechanism + enumeration)

Tree reviewed: `git archive HEAD` of `/Users/airvine/Projects/repo/drift-79` at 7266fe7. It was copied to `scratchpad/r3/tree`, and the worktree was not modified.
Stack: terra 1.9.50, GDAL 3.13.0, gdalcubes 0.7.5.

## Mechanism

R1 and R2 share one mechanism, the second framing: **the fixture was built from the properties the author set, not from what the upstream object carries**.

- The first framing (a writer serialises raster properties into a sidecar the publisher does not know about) describes the *symptom* in R1. It is now closed by enumeration:
  - Every publishing writer was measured on real gdalcubes output. None emits a sidecar (table A).
  - `cache_write_atomic()` handles both sidecar kinds.
- What turned R1 into R2 was the second framing. The R1 fix was verified against a `stac_cube_assemble` stub with no time. The failure lived in a property the real NetCDF reader supplies and the code never sets.

Round 3 finds a third instance of that same framing, below.

The discriminating instrument this round was to stop stubbing `stac_cube_assemble` altogether:
- `scratchpad/r3/col.R` builds a local 5-band gdalcubes image collection (B02/B03/B04/B08/SCL, distinct per-band DN levels).
- `scratchpad/r3/e2e3.R` mocks only `drift:::stac_cube_items` and `gdalcubes::stac_image_collection`.

So the real `stac_cube_assemble()` runs, along with `write_ncdf`, `terra::rast` of the multi-variable NetCDF, `mosaic_stacks`, `stac_cube_clip` and the COG publish, for:
- `dft_stac_composite()`: clip x tile, 4 arms, plus false colour.
- `dft_stac_cube()`: untiled and tiled.

## Findings

- **[test gap: medium]** tests/testthat/test-dft_stac_composite.R:260-289. The offline build test cannot detect the layer-order defect it models. Its `stac_cube_assemble` stub names the layers `blue, green, red` ("alphabetical, as terra reads it"), but every layer holds `vals = 0.05` (line 272). The name assertion `names(out[[1]]) == c("red","green","blue")` holds whatever the order, because `composite_finish()` renames unconditionally.
  - **Mutation, measured.** Deleting `stk <- composite_layers_order(stk, bands, label, w)` (R/dft_stac_composite.R:217) leaves the whole offline file green (`NOT_CRAN=true`, 0 failures; only the two network tests skip).
  - **Same mutant on the real NetCDF path.** It returns means `red 0.02, green 0.05, blue 0.04`, i.e. red and blue are swapped. The unmutated tree gives `0.04, 0.05, 0.02`, and the source DN levels make that correct.
  - **What still guards it.** The `composite_layers_order` unit test covers the helper, not that the build calls it. Only the network false-colour test covers the call, and it is opt-in.
  - **Fix (verified).** Give the stub distinct per-band values in alphabetical order, e.g. `cbind(0.02, 0.05, 0.1)` for `blue, green, red`, and assert `unname(unlist(terra::global(out[[1]], "max"))) == c(0.1, 0.05, 0.02)`. That kills the mutant (actual `0.02 0.05 0.1`) and passes on the unmutated tree.
  - **Stronger alternative.** Drop the `stac_cube_assemble` stub for a local-collection fixture like `r3/col.R`, which runs in seconds. That closes the whole stub boundary that produced R2 and this finding.

- **[test gap: low]** tests/testthat/test-dft_stac_composite.R:220-222. The network test lists the cache with `pattern = "^composite_.*\\.tif$"`, which cannot match a sidecar (`...tif.aux.json`). It is the only composite test that runs on a real gdalcubes object, and it ran green over the R1 defect:
  - `scratchpad/test79_composite_network2.log` is 07:55, `[ FAIL 0 | ... | PASS 64 ]`.
  - That run was on code that stamped the time before the COG write, which R1 then reproduced as an orphan.
  - The `expect_length(f, 1)` therefore passes whatever litter sits beside the COG.
  - Use `list.files(dir, all.files = TRUE, no.. = TRUE)` and expect exactly the one `.tif`, as the offline test now does.
  - The two cube network tests (test-dft_stac_cube.R:406, :445) use the same filtered listing. That is pre-existing, and the cube writer emits no sidecar today (table A).

No production-code defect found this round.

## Enumeration A: every raster/file write in R/ (grep writeRaster|write_ncdf|writeVector|st_write|file.copy|file.rename|filename=)

No `writeVector`, `st_write` or `file.copy` calls exist in R/. The only `file.rename` calls are the ones inside `cache_write_atomic()`.

| # | site | driver | properties the object carries at write (measured on the real path) | sidecar emitted (measured) | publish path |
|---|---|---|---|---|---|
| 1 | dft_stac_composite.R:227-233 | COG, FLT4S, via `cache_write_atomic` | Names are the bands. Time is stripped at :226. Untiled: varnames equal the band names. Tiled `merge`: varnames `""`. Units and longnames empty, scoff 1/0, NAflag NaN (`NoData Value=nan` declared, `LAYOUT=COG`). | **None**, in all 4 arms (clip F/T x tile NULL/500) and in false colour. Nothing new after a cache hit, and hit values are identical to miss values. | Moves `.aux.xml` and `.aux.json`, and unlinks both on exit. |
| 2 | dft_stac_cube.R:291-293 | GTiff (default FLT4S), via `cache_write_atomic` | Time is `month_times`, names are `rep(index)`, and varnames come from the NetCDF. | **None**, untiled or tiled. A GTiff probe with time, units, longnames, varnames and metags all set also wrote none. | Same as #1. |
| 3 | dft_stac_fetch.R:213-216 (`fetch_extent_to`, :618) | gdalcubes `write_ncdf` `.nc`, via `cache_write_atomic` | Time is yearly. Varnames are the asset names. | **None**: not after publish, not after `cache_hit_ok()`, and not after `mask(rast())` plus `global()`. | Same as #1. |
| 4 | dft_stac_fetch.R:227 (`mosaic_tiles`, :635) | GTiff `.tif`, via `cache_write_atomic` | `merge` of the tile NetCDFs: `has.time` TRUE, varnames, units and longnames empty. | **None** | Same as #1. |
| 5 | dft_stac_cube.R:497 (`build_stack`) | gdalcubes `write_ncdf` to `tempfile(".nc")` | A float64, uncompressed NetCDF. | None | Not published and never unlinked; lives in the session tempdir (see Notes). |
| 6 | dft_rast_break_class.R:194/200/222/237/248/255; dft_rast_break_category.R:131/140/146; dft_transition_artifact.R:310-319 | GTiff `tempfile(".tif")` intermediates, plus a user `filename` | Not changed by this diff. | GTiff emits no `.aux.json` (probe in #2). The `.aux.xml` RAT sidecar is unlinked alongside. | n/a (not a cache) |

**Canonical-stale-sidecar check.** `cache_write_atomic()` never removes a sidecar already sitting at the canonical name when the new write produces none. That is not reachable today:
- No writer above emits one.
- The R1-era orphans were always under the temp name, never the canonical one (checked in e100d63).

The only producer would be an outside reader, for example QGIS or `gdalinfo -stats` writing PAM stats. drift restamps names and time on read and never uses `minmax()` on a cache file, so a stale sidecar there changes no drift output. Not flagged.

## Enumeration B: test stubs and fixtures standing in for stac_cube_assemble / gdalcubes / rast(NetCDF) / STAC items

| test (file:line) | stands in for | omits vs real | code under test that depends on the omission? |
|---|---|---|---|
| composite "built composite leaves only its COG" (composite:260) | `stac_cube_items` (empty `features`), `stac_cube_assemble` (synthetic 3-layer) | **Distinct per-band values** (all 0.05). Multi-source structure (one source per NetCDF variable). The `yearmonths` time step (uses Date days). NA cells. varnames. | **Yes: band order.** Finding 1, mutant measured green. Time step: no, because `time<- NULL` strips either kind. NA and varnames: no (real path measured clean). |
| composite "empty year dropped" (composite:163) | `stac_cube_items` aborting `drift_no_items`; `stac_composite_cache_key`; a seeded GTiff (not COG) with no time and names `lyr.1..3` | COG layout, time, band names | No. The hit path (`stac_cube_cache_read`, then `composite_finish`) renames and stamps unconditionally. The call-site argument order was checked by reading: it matches the signature positionally. |
| composite "refuses a categorical source" (composite:108) | `rstac::stac` stopping | none needed | No (validation only). |
| composite `composite_layers_order` unit (composite:149) | `terra::rast` of the NetCDF (alphabetical names, distinct values) | Multi-source structure | No. It is a correct helper-level test, but it does not pin the call site (finding 1). |
| composite network x2 (composite:201, :239) | real | nothing | **Its listing filter hides sidecars** (finding 2). |
| cube `cube_seed_cache` / "healthy cache served" / "call site pinned" (cube:497, :590, :666) | cached GTiff with no time and distinct values; `rstac::stac` stop; `stac_cube_cache_key` mock | Time, varnames | No. The hit path sets time from `month_times` and names come from the file. The call-site test does not mock the key. |
| cube "publishes atomically" (cube:508) | `terra::writeRaster` writing 2 KB and dying | Sidecar emission mid-write | No. `on.exit` unlinks the tmp file and both tmp sidecars regardless. |
| cube "moves a terra .aux.json" (cube:696) | COG with a time | none | Reaches the failure on terra 1.9.50: the canonical `entry.tif.aux.json` is produced and moved (measured). It carries no premise assertion that the sidecar exists, so on a terra that emits none it would pass vacuously. Not flagged: it reaches the failure on the pinned stack. |
| cube `mosaic_stacks` / offset-cover / tile-gap tests (cube:270-360) | in-memory synthetic stacks | NetCDF-backed sources, time | No. `merge` is positional per layer, and real tiled arms were measured to give correct per-band means. |
| map `make_rgb()` (map_interactive) | `dft_stac_composite()` output | Time, NA cells, Float32 | No. A real-path composite (time set, 1,572 NA cells from clip) drives `dft_map_interactive(rgb = …)` to a leaflet widget with `addRasterImage`. `rgb_domain` filters with `is.finite`. |
| index `eval_expr` (index_expr) | tinyexpr in gdalcubes | Evaluator differences | No. The real gdalcubes NDWI on the local collection gave -0.678, against a hand value of (0.05-0.26)/0.31 = -0.677. |
| fetch STAC paging stubs (fetch:268-530) | `rstac` `get_request` / `items_fetch` / `items_sign` | Not touched by this diff | n/a |

## Notes (not findings)

- **`build_stack` tempfiles (pre-existing, moved code).** The per-build NetCDF is float64 and uncompressed (240,364 bytes for 100x100x3), and it is never unlinked until the session ends.
  - A floodplain-wide composite over the BULK bbox (~14,600 x 11,500 cells) is on the order of 4 GB of tempdir per year, before tile culling.
  - `dft_stac_cube()` has always done the same.
  - Worth watching in the running `floodplain` benchmark stage. Not a correctness defect.
- **Cube miss and hit differ (pre-existing, not in this diff).** `dft_stac_cube()` still returns the in-memory stack on a miss. Miss vs hit values differ by at most 2.98e-08 (measured), which is the Float32 round trip that 4d333a0 fixed for the composite. The composite is fine: miss and hit are identical in all arms.

## Evidence

Scripts in `scratchpad/r3/`:
- `col.R`: local collection.
- `e2e3.R`: real assemble, composite 4 arms, false colour, cube x2.
- `e2e3_mut.R` with `mut/`: ordering mutant.
- `fixok/`: strengthened fixture on the unmutated tree.
- `fetchw.R`: fetch writers.
- `nodata.R`: COG NoData and layout.
- `maprgb.R`: map with a real composite.
- `cubehit.R`: cube miss vs hit.

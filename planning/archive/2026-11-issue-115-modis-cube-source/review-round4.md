# Code-check round 4 (#115): the round-3 fix, and a sweep for assumptions MODIS breaks

## Checklist read

- `code-check.md`: 17 read. All 14 under Mechanisms (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice), plus Documentation Staleness; An assertion that matches an interpolated value cannot see the claim around it; A pluralisation marker takes the quantity of whatever was substituted last. 21 not read.
- `code-check-r.md`: 5 read (`glue()` trims common leading whitespace; Tests that silently do not run; `$` on a list partial-matches, so a longer sibling key answers for a missing one; `cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation; A fetcher's test helper must make the network fail, not just mock the reader). 116 not read.
- `code-check-shell.md`: 0 read (the diff has no shell). 71 not read.
- `code-check-spatial.md`: 4 read (Planetary Computer STAC: a floodplain-scale read hits three limits a reach never does; gdalcubes records only a failed image OPEN; check `chunk_status`, and know what it misses; `gdalcubes::cube_view()` reads an aggregation or resampling it does not know as a default, with no error; terra reads a multi-variable gdalcubes NetCDF with its variables in alphabetical order). 90 not read.

## Round-3 fix (99238cb)

- The hint renders as intended. Rendered through the real path (`stac_cube_items` mocked to raise `drift_no_items`): MODIS gives "try more `months`: "modis-13Q1-061" has no scene cloud cover, and its mask band does the cloud screening." `{.val {source}}` is not directly after a fold, so the cli fold trap does not apply, and `source` resolves in the caller frame. Sentinel-2 keeps the `cloud_cover_max` advice.
- The branch predicate `identical(cfg$cloud_cover, FALSE)` is the same one `stac_cloud_cover_resolve()` uses. The advice and the refusal therefore cannot disagree about which source refuses.
- Mutation test, run in a copy: replacing the predicate with `FALSE` turns exactly one test red ("an all-skipped MODIS composite does not advise a cloud filter it refuses (#115)"). Restored, the composite, config and index_expr files pass 140/50/32 (composite: 3 skipped, all network/live) with `NOT_CRAN=true`.
- The fix changes only the message, so no cache key moves.

## Sweep: what every cube source used to share and MODIS does not

I enumerated every `cli_abort`/`cli_warn`/`cli_inform`/`stop`/`warning`/`message`/`rlang::abort` by parsing R/ (229 calls). The cube-family ones are reviewed below.

| assumption | places checked | holds for MODIS? |
|---|---|---|
| `eo:cloud_cover` | `stac_cube_items()` filter (gated on NULL); `stac_cloud_cover_resolve()` refusal and remedy ("leave unset, or pass NULL", which can be followed); composite all-skipped hint (round 3); cube and composite `@param cloud_cover_max`; cube description l.21-23; `stac_cube_items` roxygen; `drift-package.R` globalVariables comment; CLAUDE.md MODIS paragraph; vignette MODIS chunk (passes no `cloud_cover_max`) | yes |
| `eo:cloud_cover`, wording only | composite count section l.33 "only scenes passing `cloud_cover_max` are counted"; notes l.284 "refuses an explicit `cloud_cover_max`" | wording only, see notes below |
| green / swir16 band | `stac_index_roles_check()` (before any query, lists the roles it has); `index_resolve_expr()`; `composite_band_assets()` ("Unknown band role green. Available roles: red, nir, blue" on the default `bands`); composite `@param source`/`bands`; cube Sources section and `@param source`; vignette; CLAUDE.md; config comment l.97-98; `dft_map_interactive` rgb (any three bands, drawn by position, so a MODIS false colour draws as the caller ordered it) | yes |
| `datetime` per item | every `properties$datetime` reader in R/ (cube.R l.549, 559, 587, 646), all after `stac_items_datetime()` except the `window_only` probe, which runs before it on purpose; gdalcubes 0.7.5 `stac_image_collection()` takes `properties$datetime` first (read in the installed source), so its lubridate branch is never reached; `dft_stac_fetch` refuses cube sources; `$datetime` cannot partial-match, because no PC property starts with `datetime` | yes |
| `offset_boundary` | `stac_cube_items` `is_pre` (gated on `!is.null`); `composite_offset_check` (unreachable without a boundary); composite description, Windows section and count section all say "Sentinel-2"; cube `@return` says "(Sentinel-2)"; `dft_index_expr` offset note names Landsat and S2 | yes |
| 10 m resolution | `res` resolved by `missing()` before `tile_size_check()` and both cache keys; `tile_size` snap and its "smaller than res" refusal (the numbers are right for 250); `month_times()` against gdalcubes' t0 (measured: `cube_view(t0 = "2000-02-18", dt = "P1M")` extends to `2000-02-01`, which agrees with `month_times`); `dft_rast_break`/`dft_rast_trend` (cadence-generic, no resolution or source wording); tile_size and parallel benchmarks (labelled "packaged AOI") | yes |
| `proj:epsg` | no drift code reads `proj:*` (grep) | yes |
| S2 wording presented as general | `cube_check_nonempty` remedies; `cube_check_chunks` remedies ("Re-running signs the request again", "an asset may be missing", both generic); `drift_no_mask_items`; `stac_features_masked` inform; `cube_parallel_check`; `mask_values` docs ("e.g. Sentinel-2 SCL", "for Sentinel-2 that is"); composite count section l.29-35; `dft_stac_config` description and `@return` l.12-13, 26-27; `inst/notes` MODIS section; `vignettes/articles/floodplain-change-dating.Rmd` (S2 by title); `land-cover-change.Rmd` | yes, except the count-section sentence noted below |

## Below the bar: checked and not reported as findings

None of these leads a MODIS user into a call that fails or a result that differs from what the code computes. Listed so the caller can promote any of them.

1. `R/dft_stac_composite.R:31-32`, count section: "Clear means not in `mask_values` (by default cloud, cloud shadow, cirrus **and snow** ...)". That is the Sentinel-2 SCL default, stated as the default. MODIS's default is `pixel_reliability` 2/3/255 (snow/ice, cloudy, fill), and 1 (marginal) is kept. There is no cloud-shadow or cirrus class, so a MODIS clear count includes marginal composites. The code does what the cube's Sources section says ("snow/ice and cloudy"); only this sentence describes the S2 default as the general one. A one-clause fix ("for Sentinel-2, ...").
2. `inst/notes/gdalcubes-pc-gotchas.md:284`: "refuses an explicit `cloud_cover_max`". Round 3 corrected the same claim in CLAUDE.md ("a `cloud_cover_max` value is refused (`NULL` is fine)") but not its twin here. An explicit `NULL` is accepted. The error runs toward over-refusal only: a reader avoids passing `NULL`, which costs nothing.
3. `R/dft_stac_config.R:12-13, 26-27`: says cube sources carry a role map of red/green/blue/nir/swir16/mask. MODIS carries four of the six. `cfg$roles$green` is `NULL`, and every drift caller refuses an absent role by name before any query.
4. The BULK MODIS scale run (scratchpad `bulk115.log`, line 10) ended with "There were 50 or more warnings" that were never printed. It finished, and its output was plausible (40 of 120 layers with data, matching 10 years x 4 months; kNDVI 0.0001-0.708). Which warnings they were is unknown. No network here, so not re-run.

## Clean

No issues found.

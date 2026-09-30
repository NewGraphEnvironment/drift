# Review p345 round 2: #92 docs, network test, BULK count benchmark, NEWS

Snapshot: scratchpad/p345snap (staged index). Read-only review. Nothing under the repo was edited
except this file.

## Findings

- **[low: false claim] NEWS.md:5, "drift refuses both, because ... every caller would scale the result as reflectance".**
  This is false for `dft_stac_fetch()`, one of the three callers the same bullet names. Fetch
  applies no scale: `grep scale R/dft_stac_fetch.R` finds only prose, and the sources it serves
  are categorical. There, a `count_values` result would be read as **class codes** by
  `dft_rast_classify()`, not scaled as reflectance. The policy is still right, but the reason given
  does not hold for fetch. The same sentence also appears in committed text outside this diff:
  `inst/notes/gdalcubes-pc-gotchas.md:219` ("every drift caller would scale the result as
  reflectance") and the comment at `R/dft_stac_cube.R:306-308` ("a reflectance scale or an index
  expression"). Suggested wording: "every caller would read the result as reflectance, an index
  or a class code". Fix it in all three places, not only NEWS. This is round 1's mechanism: a
  reason recalled from the composite/cube path and applied to every caller without reading fetch.

- **[low: false claim] NEWS.md:12, "every genuine composite key is unchanged (pinned in the tests)".**
  This holds only when `aggregation` is lower case. `aggregation_check()` now returns
  `tolower(aggregation)`, and that lowered value is the one hashed. I computed this against the
  v0.19.2 tree (`git archive v0.19.2`, `pkgload::load_all`, and the test file's own `key_args()`):
  - Default: `03ee8ecc66b832a8`, which matches the pin.
  - `aggregation = "count"`: `08e0c5510e8ae297`, which matches the test.
  - `aggregation = "Median"`: **`150c8ca5003bbe78`**. The same call now keys as
    `03ee8ecc66b832a8`.

  So a composite cached under a mixed-case value moves key and is rebuilt. The old file becomes an
  orphan inside `v2`, where `dft_cache_clear(scheme = "superseded")` cannot reclaim it.
  `stac_cube_cache_key()` (R/dft_stac_cube.R:224-225) and `stac_cache_key()` (fetch) also hash
  `aggregation`, so a mixed-case `dft_stac_cube()` caller silently re-streams what the code calls a
  "multi-hour Sentinel-2 stream". The test pins only the lower-case default, so it cannot see this.
  Mixed-case callers are rare, and sharing a key afterwards is the right behaviour. The fault is
  the unqualified claim. Suggested wording: "every composite key for a lower-case `aggregation` is
  unchanged; a mixed-case value (`"Median"`) now keys as its lower-case form, so a cube or
  composite cached under one is rebuilt once". Add this near "Case is ignored" on line 5.

## Round-1 fixes: verified

- **The remedy path is exact.** `cache_scheme_dir(cache_dir, source)` is
  `file.path(dft_cache_path(cache_dir), "v2", source)` (R/dft_cache.R:98-106). `dft_stac_composite()`
  writes to `cache_scheme_dir(cache_dir, source)` (line 210), and the only `cube = TRUE` source in
  `dft_stac_config()` is `sentinel-2-l2a`, so every composite is under
  `<dft_cache_path()>/v2/sentinel-2-l2a/`. The scheme was already `v2` at v0.18.0
  (`git show v0.18.0:R/dft_cache.R`:106).
- **Deleting `composite_*.tif` spares `cube_*.tif` and `count_*.tif`.** The cube writes
  `paste0("cube_", key, ".tif")` (R/dft_stac_cube.R:230). The count writes
  `paste0(family, "_", key, ".tif")` with family `"count"`. v0.18.0 already stripped `time` before
  the write (line 226), so no `.aux.json` sidecars are left behind the glob. The local cache holds
  only `composite_*.tif`.
- **"0.18.0-0.19.2" is correct.** v0.17.0 has no `R/dft_stac_composite.R`. v0.18.0, v0.19.0 and
  v0.19.2 all pass `aggregation` straight through (line 212) and write `composite_<key>.tif`
  (line 194). The pinned stale key `08e0c5510e8ae297` is what v0.19.2 computes for
  `aggregation = "count"` (computed above).
- **"superseded does not reclaim them" / "current would delete cubes too" is correct.**
  `superseded` = `setdiff(list.dirs(base), <base>/v2)`, and `current` unlinks all of `<base>/v2`.
- **"refused by policy" is correct.** The NEWS wording no longer says gdalcubes cannot honour
  `count_*`. The error message and the three `@param` texts say "reads a value it does not know as
  no aggregation", which is true.
- **The per-chip max, the committed RSS evidence and the softened causal claim are all fixed.**

## Claim enumeration: NEWS entry

| # | Claim | Source | OK |
|---|---|---|---|
| 1 | `aggregation` went straight into `cube_view()` | v0.18.0-v0.19.2 line 212 | yes |
| 2 | Unknown value read as no aggregation, no error, copies every scene; masked can overwrite clear | gotchas.md:217-218 (round trip measured). "Copies incl. NaN" is from the C++ reading, hedged "could" | yes |
| 3 | Looked like red reflectance 0.008-0.18 | findings.md:21 (0.0077-0.1835) | yes |
| 4 | Three functions refuse all but the six | aggregation_check() at fetch:105, cube:169, composite:186 | yes |
| 5 | Each of the six round-trips; `?cube_view` omits `last` | test-dft_stac_cube.R:778-; findings Errors row | yes |
| 6 | gdalcubes honours `count_values`/`count_images` | gotchas.md:218, round 1 re-probe | yes |
| 7 | They count items; **every caller would scale as reflectance** | fetch applies no scale | **no (finding 1)** |
| 8 | Case ignored, as gdalcubes ignores it | gotchas.md:217; aggregation_check | yes |
| 9 | Check runs before any network call | first statements after check_gdalcubes/config in all three | yes |
| 10 | `resampling` falls back to `near`, #96 | round 1 probe, #96 title | yes |
| 11 | count = distinct clear days per pixel | P1D + first + reduce_time count; offline probe findings:59 | yes |
| 12 | Overlapping tiles count once | findings:88, fixture test 371- | yes |
| 13 | 20 items/12 dates -> 5-9; 6 items/4 dates -> 4 everywhere | findings live table (cc_max 100 / 20 rows) | yes (the conditions that separate the two runs are not stated, but nothing in the sentence is false) |
| 14 | Integer, no scale/offset, INT2U COG `count_<key>.tif` | composite writeRaster datatype, cache_file | yes |
| 15 | NA never 0; 0/NA follows chunking/`parallel`; failed chunk NA | count_zero_na doc (measured 12,544 / 4,352+8,192); gotchas.md:206 | yes |
| 16 | Year with no clear day dropped with warning | count_zero_na before cube_check_nonempty -> drift_empty_cube -> composite_skip; test at ~555 | yes |
| 17 | Count spans the offset change without refusal | `is_pre[] <- FALSE`, no composite_offset_check | yes |
| 18 | Default mask includes snow + cloud/shadow/cirrus | dft_stac_config.R:71 `c(3,8,9,10,11)` | yes |
| 19 | Since 0.18.0 cached reflectance as `composite_<key>.tif` | v0.18.0 tree | yes |
| 20 | Count keys under own tag + prefix; nothing reads old files | family tag in key, `count_` prefix, is_count forces family | yes |
| 21 | **Every genuine composite key unchanged** | lower-casing moves mixed-case keys | **no (finding 2)** |
| 22 | In `v2`, superseded does not reclaim | dft_cache.R | yes |
| 23 | Remedy path, spares cubes; `current` deletes cubes | above | yes |
| 24 | 20 chips, 300 m, Jul-Aug 2023, red | benchmark script chips-count stage | yes |
| 25 | 9.6 min, median 24.7 s, 0.46 GiB | recomputed: 575.06 s loop / 577.48 s real; 24.696; 489,013,248 B = 0.455 GiB | yes |
| 26 | Each chip's highest count 5-9, no NA | CSV count_max 5..9, count_na all 0 | yes |
| 27 | Same 20 as #79: 17.5 min, median 44.4 s | chips_per_chip.csv rows 1-20: 1,051.6 s, 44.37 | yes |
| 28 | #79 0.48 GiB over 100 chips, sampled every 2 s | rss_chips.txt max 503,296 KiB; run.sh `sleep 2` | yes |
| 29 | Count reads one band vs three | chips stage default bands = RGB; count bands = "red" | yes |
| 30 | Runs two days apart | wallclock_chips.txt 2026-09-28, time_chips_count.txt 2026-09-30 | yes |
| 31 | Evidence in `*count*` | three committed files hold claims 24-26. Claims 27-28 are in chips_per_chip.csv / rss_chips.txt (committed, not matched by the glob) | acceptable |

## Claim enumeration: new roxygen (and man/, which matches it)

| Claim | Source | OK |
|---|---|---|
| One day per time step; overlapping tiles once; masked tile does not hide a clear same-day one | findings:59 probe (first/max/median skip NaN); fixture test | yes |
| Snow in default mask; `cloud_cover_max` applies | config:71; stac_cube_items filter | yes |
| Whole numbers, no scale/offset, integers, one layer per band | pixel_fn, INT2U | yes |
| Mask shared, so bands count alike | image_mask applies to every band. Band-level nodata could differ at edges, but that is marginal and `bands = "red"` advice is sound | yes |
| NA never 0, because failed chunk = NaN | count_zero_na doc; gotchas:206 | yes |
| Partial read failure -> uncounted -> lower bound; stderr only | inference from gotchas:206 (failed chunks written NA, reported on stderr). The NA day is skipped by count() | yes (inferred, not measured, and stated as a consequence) |
| Not refused across 2022-01-25 | code | yes |
| `count_<key>.tif`, keyed apart | code | yes |
| @param: the six or count; else refused; 0.18.0-0.19.2 behaviour | code, tags | yes |
| @param mask_values: SCL cloud, shadow, cirrus, snow | config:71 | yes |
| @return: integer counts; no clear day anywhere -> dropped | code | yes |
| Example: `aoi` defined earlier in the same `\dontrun` block; valid call | examples | yes |
| cube/fetch @param: six, else refused | aggregation_check | yes |

## Notes (not findings)

- **The test title at `tests/testthat/test-dft_stac_composite.R:299` still reads "refuses an aggregation gdalcubes would not honour".**
  This is the round-1 wording, left in committed code outside this diff. It is not user-facing,
  but the same `grep` that found round 1 finds it.
- **"which rebuild on their next call" is true, but says nothing of the cost.**
  A floodplain-wide composite is hours, and with #88 open a BULK-size one does not complete. In
  practice nobody is likely to hold such a cache, so this is not a false claim.
- **The network test mirrors drift's own query:** the same `stac_search(intersects = sfg)`,
  `ext_filter`, `limit = 500` and `items_fetch()`. `aoi_pkg()` exists at test file line 3.

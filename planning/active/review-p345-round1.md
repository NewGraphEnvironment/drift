# Review p345 round 1: #92 docs, network test, BULK count benchmark, NEWS

Snapshot: scratchpad/p345snap (staged index). Offline suite on the snapshot:
`test-dft_stac_composite.R` [ FAIL 0 | WARN 0 | SKIP 3 | PASS 99 ].

## Findings

- **[bug: false claim] NEWS.md:5, R/dft_stac_composite.R:92-94, R/dft_stac_cube.R:39-41, R/dft_stac_fetch.R:51-53 (and the three man/*.Rd).**
  NEWS says drift now refuses any `aggregation` "outside the six gdalcubes actually honours". The three
  `@param aggregation` docs say anything else is refused "because gdalcubes would silently read it as no
  aggregation". Both are false for `count_values` and `count_images`. gdalcubes 0.7.5 honours both
  (re-probed here: `cube_view(..., aggregation = "count_values")$aggregation` returns `"count_values"`,
  and `"count_images"` returns `"count_images"`). drift refuses them **by policy**, as its own comment
  at R/dft_stac_cube.R:305-308 says. Phase 1 round 3 reworded the error message to fix exactly this
  claim (findings.md, Errors Encountered, "claimed gdalcubes would not honour values it does honour"),
  and the docs and NEWS now bring it back. Suggested fix: "the six drift passes to gdalcubes (it also
  honours `count_values`/`count_images`, which count items and are held back)", and in the params:
  "anything else is refused; an unknown value would be read by gdalcubes as no aggregation".

- **[bug: false claim, understates scope] NEWS.md:12 ("Cached 'count' files from 0.19.x"), R/dft_stac_composite.R:94 ("how `"count"` behaved in drift 0.19.x"), tests/testthat/test-dft_stac_composite.R:~573 comment ("0.19.x wrote reflectance under this key").**
  The defect and its stale cache files date from **0.18.0**, not 0.19.x. `dft_stac_composite()` was
  introduced in 0.18.0 (#79, NEWS.md:41). In `git show v0.18.0:R/dft_stac_composite.R`, `aggregation`
  already goes straight to `stac_cube_assemble()` (line 212), and the file is already written as
  `composite_<key>.tif` (line 194). The file has no key or aggregation diff between v0.18.0 and
  v0.19.2, and the cache scheme has been `v2` since 0.12.0. A reader on 0.18.0, which is where the
  floodplains#93 work started, would read the entry as not applying to them, both for the wrong
  values and for the cache files. It should say "0.18.0-0.19.2".

- **[fragile: remedy over-deletes / is not actionable] NEWS.md:12, "clear the current scheme or delete them by hand".**
  The `superseded` part is correct. `superseded` = `setdiff(list.dirs(base), <base>/v2)` (R/dft_cache.R),
  and these files are in `v2`, so it does not reclaim them.
  - **"Clear the current scheme"** means `dft_cache_clear(scheme = "current")`. That deletes every
    current entry for every source, including `dft_stac_cube()`'s `cube_*.tif`. The code calls those a
    "multi-hour Sentinel-2 stream" (R/dft_stac_cube.R:291). Even with `source = "sentinel-2-l2a"`,
    `unlink()` removes the whole directory, cubes included.
  - **"Delete them by hand"** gives no way to find them, and the same sentence says they "cannot be
    told from real composites".
  - **A remedy that works and spares cubes:** delete `composite_*.tif` under
    `<cache>/v2/sentinel-2-l2a/` (composites rebuild cheaply; `cube_*` and the new `count_*` are
    untouched).

- **[bug: false claim] NEWS.md:13, "Every chip counted 5-9 clear days, with no `NA` cells".**
  `chips_count_per_chip.csv` records only `count_max` per chip (range 5-9, recomputed). It does not
  record a per-pixel minimum. The true statement is "each chip's **maximum** count was 5-9". As
  written, it reads as every pixel having at least 5 clear days, and that is exactly the number a
  reader uses to choose a window. The live 2 km square had a minimum of 4-5, and nothing bounds the
  BULK chips' minimum. The "no NA cells" half is correct: `count_na` is 0 in all 20 rows.

- **[fragile: evidence not committed] NEWS.md:13, "0.46 GiB peak (`/usr/bin/time -l`) ... Evidence is in `data-raw/logs/benchmark_composite_bulk/*count*`".**
  The committed `*count*` files are `chips_count_per_chip.csv` and `timings_chips-count.csv`, and
  neither holds the peak. The 489,013,248 B maximum resident set size and the 577.48 s real are only
  in `run_chips_count.log`. That file exists in the working tree and is gitignored
  (`data-raw/logs/**/*.log`). So on any other checkout the glob does not contain the evidence for the
  memory figure. #79's 0.48 GiB, by contrast, has `rss_chips.txt` committed. The gitignore rule is
  accepted, so the claim is the issue: commit the `/usr/bin/time` block as, for example,
  `time_chips-count.txt`, or drop "Evidence is in" for the peak.

- **[low: unmeasured causal claim] NEWS.md:13, "The count reads daily steps but only one band, so it is the cheaper of the two."**
  That the count was cheaper (17.5 vs 9.6 min on the same 20 chips) is measured. The reason given
  is inferred. No one-band median control was run, the two runs were two days apart (2026-09-28 vs
  09-30), and the count run was network-bound (44.5 s user of 577 s real). The 0.46 vs 0.48 GiB
  comparison also sets a true peak (`time -l`) against a 2 s sampler, which reads low (CLAUDE.md).
  NEWS does not claim the count uses less memory, so this is only a caution. Either soften the
  wording to "likely because" or drop the clause.

## Verified correct (recomputed from the artifacts)

- **Count timings** (`chips_count_per_chip.csv` / `timings_chips-count.csv`):
  - 9.6 min: loop 575.06 s = 9.58 min, or `time -l` real 577.48 s = 9.62 min.
  - Median 24.7 s (24.696), max 59.6 s.
  - Count max 5-9, 0 NA cells, 3,660 cells a chip.
  - 0.46 GiB = 489,013,248 B / 2^30 = 0.455, from the local log.
- **The #79 median chips** (`chips_per_chip.csv`):
  - Rows 1-20 sum to 1,051.62 s = 17.5 min, median 44.37 s.
  - The 100-chip peak is 503,296 KiB = 0.48 GiB (`rss_chips.txt` max).
  - The same seed-79 draw, so chip i is the same geometry, cells 3,660.
- **Live numbers match findings.md:** 20 items / 12 dates / 5-9, and 6 items / 4 dates / 4 everywhere.
  The issue's reflectance was 0.0077-0.1835, which NEWS gives as 0.008-0.18.
- **`?cube_view` (0.7.5) omits `last`:** Rd lists "min", "max", "mean", "median", or "first". `last`
  round-trips.
- **Case:** `Median` becomes `median`.
- **`resampling`:** "foo" becomes `near`, and #96's title matches.
- **SCL default `c(3, 8, 9, 10, 11)`:** 11 is snow/ice (R/dft_stac_config.R:67-71).
- **The code matches every count-behaviour claim in the docs:**
  - INT2U, and the `count_` prefix.
  - 0 becomes NA (`count_zero_na`) before `cube_check_nonempty`.
  - No offset split (`is_pre[] <- FALSE`).
  - A P1D read with `first`, and NEAREST overviews.
  - An empty year is dropped with "no clear pixels".
  - The composite key is pinned.
- **Network test** (tests/testthat/test-dft_stac_composite.R:580-617): it would fail on reflectance.
  - Values of about 0.03 fail the whole-number check, `min >= 1` and `median >= 1`.
  - Reflectance truncated to 0 by INT2U fails `min >= 1`.
  - An all-NA raster fails `expect_gte(median(numeric(0)), 1)`. Checked: an NA comparison is an
    expectation failure in testthat 3.3.2.
  - The bound `max <= distinct dates` is sound, because drift reads only items from the same
    intersects/cloud-cover/datetime query.
  - `rstac` is in Imports and `withr` in Suggests.
- **Benchmark stage `chips-count`** (data-raw/benchmark_composite_bulk.R:82-114) runs as written:
  - It uses the same `set.seed(79)` / `st_sample` draw, then `[1:20, ]`.
  - It writes both CSVs, and the shared tail writes `timings_<stage>.csv` and "ALL STAGES DONE".
  - The local log confirms a completed run.
  - Cosmetic only: `benchmark_composite_bulk-run.sh`'s usage line and summary grep do not know
    `chips-count`, but the header routes that stage through `/usr/bin/time -l` instead.

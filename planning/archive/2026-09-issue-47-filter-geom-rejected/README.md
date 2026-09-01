# Issue #47 — `filter_geom` evaluated and rejected on measurement

## Outcome

#47 proposed adopting `gdalcubes::filter_geom()` now that the segfault blocking it
was fixed in `NewGraphEnvironment/gdalcubes@newgraph`, claiming ~10× from the AOI's
0.102 area-to-bbox ratio. The fork claim was correct — it clears the upstream
reproducer, so adoption never depended on `appelmar/gdalcubes#111` merging. **The
rest did not survive measurement**, and the plan's decision gate is the reason that
was found before the code was written rather than after.

The area ratio is the wrong bound. `filter_geom` skips whole **chunks**, and
`gdalcubes:::.default_chunk_size()` targets `2 * parallel` spatial chunks with the
edge clamped to `[64, 1024]` px — a 2 × 2 grid on a 3.3 km reach, which a corridor
intersects entirely. Forcing chunks finer does skip ground and costs more than it
saves, because Sentinel-2 COGs are `Block=512x512` and a sub-block chunk refetches
the same bytes. **Chunk arithmetic predicted 339 requests; the wire said 693.**

Worse, the central proposal — "drop the now-redundant output-side `terra::mask()`"
— was not a redundancy removal. `terra::mask()` defaults to `touches = TRUE` while
`filter_geom` clips at cell centre, so it would have silently shrunk every reported
footprint by 15.5%, disguised as an optimisation.

The benchmark then surfaced what actually mattered: **drift had never called
`gdalcubes_options()` anywhere in `R/`**, so every cube read since the function
existed had run single-threaded. That shipped instead, ~2× for one argument, with
byte-identical output and no cache invalidation.

Two live defects were found along the way, both independent of #47: drift's only
end-to-end cube test **passed on an all-NA cube** (every assertion in it, including
the coverage one, is satisfied by a cube containing no data — the exact mode #32
exists to prevent), and `stac_cube_clip()` documented the wrong clip rule.

Three adversarial review rounds found five further defects, **two of them
introduced by this work**: a post-condition that would have aborted the packaged
`months = 6:9` vignette call after a full 20-minute stream, and a `NEWS.md` entry
that published the pre-fix behaviour as the fix. A third round caught that the
all-NA guard covered only the write path, so a poisoned cache was still served
permanently. The recurring lesson is the one `code-check.md` already records: a fix
written under a wrong assumption reproduces the defect, and the second and third
passes are where the value concentrates.

## Measurement

Packaged Neexdzii AOI (3.3 km reach, area/bbox 0.1019), 4-month monthly kNDVI cube,
Sentinel-2 L2A. One subprocess per arm, `CPL_CURL_VERBOSE=YES`, stderr to its own
file — so cost is an **observed** count of HTTP range requests, not chunk arithmetic.

| arm | wall clock | requests | vs A | non-NA cells |
|---|---|---|---|---|
| A — bbox + `terra::mask()` (the shipped path) | 236.8 s | 462 | 1.00× | 49,244 |
| B — `filter_geom`, default chunking | 236.9 s | 462 | 1.00× | 41,608 |
| C — `filter_geom`, 64 px chunking | 348.2 s | 693 | 1.50× | 41,608 |
| C — `filter_geom`, 128 px chunking | 343.7 s | 693 | 1.50× | 41,608 |
| D — `tile_size = 640` | 1263.6 s | 3213 | 6.96× | 49,244 |
| **E — `parallel = 4`** | **115.8 s** | 1134 | 2.45× | 49,244 |
| **E — `parallel = 8`** | **96.0 s** | 1386 | 3.00× | 49,244 |

**What changed because of these numbers:**

- `dft_stac_cube()` gained `parallel` (default `min(4, cores - 1)`) — ~2× for every
  caller, output byte-identical (correlation 1.000, max abs diff 0, same grid, same
  49,244 non-NA cells), so it stays out of the cache key and orphans nothing.
- `filter_geom` was **not** adopted: no fork dependency, no capability probe, no
  cache-key change. All of that was downstream of a gate that failed.
- `tile_size`'s documentation was corrected — it is the **slowest** option measured,
  5.3× the baseline, not a speed optimisation. Prior docs implied otherwise, and it
  was recommended to the user before it was measured.
- The 15.5% footprint difference (49,244 → 41,608) turned "drop the redundant mask"
  from a refactor into a methodology change nobody had priced.

**Wrong turns, kept deliberately:**

- Predicted `filter_geom` would skip nothing at default chunking (correct: 462 vs
  462) and give ~1.4× at 64 px (**wrong**: it was 1.5× *worse*). The prediction was
  recorded before the arms returned, which is what made the gap legible.
- Claimed `parallel = 1` "cost twice over" via coarse chunking. Contradicted by this
  branch's own arms — at `parallel = 1`, finer chunking measured 45% slower and 50%
  more requests. The speedup is concurrency alone.
- Told the user `tile_size = 640` was the lever available today. It is the worst arm
  in the table. Retracted once measured.
- Read `E_par8`'s request count mid-run (1004) and wrote it into the notes; the
  final count is 1386.

## Evidence

- `data-raw/logs/benchmark_filter_geom/summary.csv`, `equivalence.csv` — the arms
- `data-raw/benchmark_filter_geom.R` — the harness (per-arm subprocess, request counting)
- `data-raw/benchmark_filter_geom_compare.R` — equivalence, bilinear-aligned
- `data-raw/benchmark_filter_geom_chunkskip.R` — the *prediction* the wire contradicts
- `review-round{1,2,3}.md` — the three adversarial passes

Closed by: PR #49 (commits 8d21bd3, f5a6182, e9932a6, a2bba0d, 011f015).
Spawned #48 — both frozen cache-key goldens fail on `main`, so the key moved and
silently orphaned every cached cube and fetch.

# Code-check round 3: branch 101-promote-esri-wayback-capture-index-chip vs main

Reviewer: subagent, 2026-10-14. I ran the tests and probes in a scratchpad copy
(`$TMPDIR/.../scratchpad/drift_review_r3`), not in this tree. Offline wayback tests with
`NOT_CRAN=true`: captures 52 pass, fetch 38, pick 23, releases 9, with 0 fail and 0 error. Probes
ran live against the Wayback metadata services and Esri's own client source (`Esri/wayback-core`).
The environment was sf 1.1.2, GEOS 3.13.0 and GDAL 3.8.5. Probe scripts are in the scratchpad:
`gc3.R`, `gc4.R`, `gc5.R`, `gc6.R`, `do.R`, `do2.R` and `big.R`.

## The mechanism

All four earlier findings have one shape. **The code, its comments and its fixtures were all
written from the same belief about an external answer**, and nothing checked that belief against the
real answer:

- (1) "a date that does not parse is a base layer";
- (2) "the cached object's shape is fixed";
- (3) "only chips are cached";
- (4) "`st_make_valid()` sorts rings by parity".

Each fixture was built to that belief, for example two disjoint squares in (4). So the tests
confirmed the model rather than the service or the library. This is "verification that reads its
own output" combined with "a fixture that cannot reach the failure mode". Below is every place in
this diff where a belief about a library default or a service representation carries weight, and
what a real answer showed for each.

| # | Belief the code rests on | Checked against | Verdict |
|---|---|---|---|
| a | `valid_linework` returns polygonal footprints (the round-2 fix) | real metadata: 2014_r08 layer 6 and 2024_r10 layer 4 over BC | **Not true, and harmless here.** With `geos_keep_collapsed = TRUE` (the default), 26 of 771 footprints come back as GEOMETRYCOLLECTION, LINESTRING or MULTILINESTRING. The pure-line ones are zero-area rings (`Too few points`, or a self-intersection with signed area 0), and `valid_structure` also gives them 0 area, so no area is lost. `wayback_join()` ran on 150 polygons and 150 points placed at those footprints with no error, and the covers summed to at most 1. GEOS 3.9 (PostGIS container) also accepts a mixed-dimension collection in `ST_Difference`. No finding. |
| b | `valid_linework` gives the true footprint, including when outer rings overlap (parity would turn an overlap into a hole) | union of the clockwise rings minus the counter-clockwise rings, for every multi-ring footprint in both layers | 0 footprints differ by more than 0.001 km². No finding. |
| c | the highest DrawOrder is drawn on top, then the finer SRC_RES, then OBJECTID | real overlaps | DrawOrder is **constant** within a layer (always 80 in 2014_r08 L6; 80 or 100 in 2024_r10 L4), so it never breaks a tie in practice. But overlapping footprints only touch along slivers: no pair with a different capture overlaps by more than 1 ha with the same DrawOrder and SRC_RES. So the unverified OBJECTID tiebreak decides nothing measurable. No finding. Esri's own client takes `features[0]` and does not use DrawOrder, so it cannot confirm the semantics either. |
| d | layer `L` ↔ zoom `23 - L`, and zoom 10 stands for every zoom at or below 10 | `Esri/wayback-core` `src/metadata/index.ts` `getLayerId()` | It is exactly `MAX_ZOOM(23) - zoom`, capped at layer 13. Matches. |
| e | paging, `exceededTransferLimit`, JSON error with HTTP 200 | round 1 and round 2 (live); a BULK-scale bbox (-127.6,54,-125.6,55.6) on 2024_r10 layers 5 and 6 | Sound: 450 and 453 footprints, no error. (A 10° x 8° box fails with "Error performing query operation", and the code aborts loudly as it should.) |
| f | JSON null and numeric attributes survive the cache | `wayback_meta_compact()` | Null becomes NA, never dropped; numbers are written without an exponent. Sound. |
| g | 404/204 tiles read as zeros; redirects followed; `-ovr NONE` | round 1 (live fetch tests) | Sound. |
| h | the query bbox (4326 vertex bbox) contains every feature as joined | geometry argument | It holds. The bbox maps to an axis-aligned rectangle in 3857, and `feat_3857` has straight 3857 edges between its vertices, so it lies inside that rectangle. |
| i | `st_make_valid(geos_method =)` exists | sf NEWS | The argument first appears in **sf 1.0-8**. See the finding below. |

## Findings

- **[fragile] DESCRIPTION:Imports `sf` (no version floor), used at R/dft_wayback_captures.R:447-448**:
  the round-2 fix passes `geos_method = "valid_linework"` to `sf::st_make_valid()`. That argument
  was added in sf 1.0-8 (sf NEWS: "add new algorithm and drop option to `st_make_valid()`", #1655).
  `Imports:` lists `sf` with no floor. On an install with an older sf, every
  `dft_wayback_captures()` call that reaches the parse stops with "unused argument
  (geos_method = ...)". This is the same mechanism once more: the call was written against the
  installed library, not the declared one. Fix: `sf (>= 1.0-8)`. On sf 1.0-8 or later with GEOS
  below 3.10.1, sf ignores the method and calls `GEOSMakeValid`, which is the linework algorithm,
  so the parse is correct there too.

No other issue found. The round-2 fix (raw cache under the `wayback-meta-v2 raw` salt, parse after
every read, `valid_linework`) is sound on real metadata. The checks are rows a, b and f above.

## Round-2 fix re-checked

- `wayback_meta_cached()` keys on the new salt, so old sf-object entries cannot be served. A
  corrupt RDS is re-fetched (`tryCatch(readRDS)`). The write is a temp file plus rename.
- `wayback_meta_parse()` handles empty `rings`. A ring with fewer than 4 points (it occurs live)
  parses to a line rather than erroring.
- The new tests ("outer rings that share an edge", "a hole in a footprint's second part", "a point
  in a footprint's hole") pass, and the shared-edge fixture now reaches the `valid_structure`
  failure.

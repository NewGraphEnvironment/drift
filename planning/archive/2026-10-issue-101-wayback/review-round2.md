# Code-check round 2: branch 101-promote-esri-wayback-capture-index-chip vs main

Reviewer: subagent, 2026-10-14. I ran the tests and probes in a scratchpad copy
(`$TMPDIR/.../scratchpad/drift_review_r2`), not in this tree. Offline wayback tests: captures 50
pass, fetch 38, pick 23, releases 9, with 0 fail and 0 error. Probes ran live against the
Wayback config and metadata services. The environment was sf 1.1.2, GEOS 3.13.0 and GDAL 3.8.5.

## Findings

- **[bug] R/dft_wayback_captures.R:534 (`wayback_meta_parse`), with its doc at :500-503**:
  `sf::st_make_valid(sf::st_sfc(rings, crs = 3857))` runs sf's **default** method. In sf 1.1.2
  the default is `geos_method = "valid_structure"`, not the linework method the comment
  describes. `valid_structure` takes ring 1 as the shell and every later ring as a hole. So when
  a multi-part Esri footprint has parts that touch, it throws away every part after the first,
  and it ignores holes that belong to any part after the first.

  Measured on real metadata: release `World_Imagery_Metadata_2014_r08`, layer 6 (zoom 17), bbox
  -130,50,-120,58. That returned 589 footprints, 101 of them with more than one ring. For 17 of
  those 101, the area from the default method differs from `valid_linework`:
  - Three footprints made of touching outer rings (`OO`, `OO`, `OOOO`) lose almost all their
    area. `wayback_meta_parse()` returns 9.31 / 0.54 / 39.05 km² where the union of their outer
    rings is 107.25 / 1024.41 / 309.86 km².
  - Footprints with holes in later parts come out with the holes filled. For example
    2947.33 km² against 2891.20 km² (`OOhhhO`).

  Direct check: a point inside ring 2 of the 2007-08-19 footprint (at -124.924, 50.882) does
  **not** intersect the parsed footprint. Its two rings touch, and both are valid on their own.

  Why it matters: at such points `dft_wayback_captures()` misses the capture or reports the wrong
  one. A dropped part also stops hiding the footprints ranked below it, so a lower capture is
  reported as "drawn on top" and polygon `cover` is wrong. Filled holes credit a capture where
  the tiles show another. No error is raised, and the cache then keeps the wrong parse.

  The existing test "a footprint with two outer rings matches in either" uses two disjoint
  squares, which `valid_structure` keeps, so that fixture cannot reach this case.

  Fix: pass `geos_method = "valid_linework"`. That is what the comment already claims. On the
  three touching cases it gives exactly the union of the outer rings, and it subtracts holes.
  Then bump the salt from `parse-v1` to `parse-v2`. Entries already cached under `parse-v1`
  hold the broken geometry, and this is the exact case the round-1 salt fix exists for. A
  regression fixture needs two outer rings that **share an edge** (and ideally a hole in ring 2).

  Repro script: `$TMPDIR/.../scratchpad/rings.R`.

## Round-1 fixes re-checked (sound)

- **`wayback_captures_finish`**: only NA counts as a base layer. Any non-NA value that is not a
  real YYYYMMDD aborts and names the release. Live probe: base layers come back as JSON `null`
  (layer 13 in 2018_r07 and 2026_r09), and every dated value is an 8-digit int, from 1999 to 2024.
  Epoch-ms values pass through `format(scientific = FALSE)` and abort, as do impossible dates.
  The fix does not drop or misread a real row in any case I found.
- **Salt `parse-v1`**: the doc on `wayback_meta_parse()` points at it. The finding above is the
  first change that has to bump it.
- **CLAUDE.md cache line**: accurate.

## Checked, no finding

- **Field renames fail loud.** An unknown `outFields` name answers
  `{"error":{"code":400,...}}`, which `wayback_meta_page()` retries and then aborts. So a
  DrawOrder or SRC_RES rename cannot silently become `-Inf` or NA. DrawOrder was never null in
  any layer probed.
- **Release config.** All 197 releases share one `itemURL` template, which matches
  `.wayback_tile_url/<id>/{z}/{y}/{x}`. The metadata URLs and release dates are unique. Old
  (2014-02-20) and current layers carry the same fields.
- **Zoom mapping.** `MinMapLevel`/`MaxMapLevel` per layer agree with zoom = 23 - L (layer 5 is
  12-18, layer 6 is 12-17/18, layer 13 is 0-11).

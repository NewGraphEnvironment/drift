# Code-check round 1: branch 101-promote-esri-wayback-capture-index-chip vs main

Reviewer: subagent, 2026-10-14. All wayback tests were run in a scratchpad copy of the repo, not in
this tree. Offline: captures 48 pass, fetch 38, pick 23, releases 9. With
`DRIFT_TEST_NETWORK=true`, the live captures and fetch tests also pass (0 fail, 0 error, 0 skip).
Live probes: the config parses to 197 releases. Releases 10, 17216 and 63116 all list the same 14
metadata layers (0 = 1.9 cm through 13 = 150 m), so `23 - L` holds across releases. Every layer
sampled (0, 5 and 13 on releases 10 and 63116) reports supportsPagination and supportsOrderBy,
with maxRecordCount 1000. SRC_DATE arrives as YYYYMMDD in old releases (2009, 2014) and new ones
(2020).

## Findings

- **[fragile] R/dft_wayback_captures.R:161-168 (`wayback_captures_finish`)**: the
  date-format guard fires only when NO hit parses. Any non-NA SRC_DATE that is not 8 digits is
  dropped as if it were a base layer. But base layers have a **null** SRC_DATE (the source script,
  floodplains `wayback_index-capture.R:137`, says so), so a non-null value that does not parse is
  a format change, not a base layer. If Esri changes the format in some releases only (say the new
  ones, or a switch to epoch ms), those releases' captures vanish without a warning, as long as
  any older release still parses. Reproduced: R1 with `SRC_DATE = 20150101` and R2 with
  `SRC_DATE = 1546300800000` give one row (R1) and no warning or error; R2 reads as "no imagery".
  This is the "guard that fails toward pass" shape. Treat only `is.na(src_date)` as a base layer,
  and abort (or at least warn) on any non-NA value that does not match `^[0-9]{8}$`.

- **[fragile] R/dft_wayback_captures.R:303-306, 309-310 (`wayback_meta_cached`)**: the cache
  stores the **parsed** `sf` object (`wayback_meta_parse()` output: `source` pasted from
  NICE_DESC + SRC_DESC, `draw_order` with NA set to -Inf, geometry after `st_make_valid()`). But
  the key's salt names only the query choices. The comment says "The salt names the fixed query
  choices". A later change to the parse (another column, a different `source` string, different
  NA handling) would keep serving old-shaped objects from every existing entry. `force` is the
  only way out, and the docs tell users it is needed only for a re-read. That is the "written data
  outlives the fix" mechanism. Either cache the raw feature list and parse after the read, or
  state in the salt comment that a change to `wayback_meta_parse()` must bump `wayback-meta-v1`.
  Nothing is stale today: it is a trap for the next edit.

- **[fragile, doc] CLAUDE.md (new Wayback block, last line)**: "Only chips are cached." is
  wrong. `dft_wayback_captures()` caches every release-layer metadata response under
  `<cache>/v2/esri-wayback/meta/` (and its own roxygen says so). The sentence was meant to say
  tiles are not cached. Read literally, it tells a future session that metadata is always live,
  so `force = TRUE` would never come to mind after a stale or bad entry. Suggested wording: "Tiles
  are not cached; chips and metadata responses are."

Checked and found sound (no finding):
- the `rbind(p, g)` column mismatch when one side is zero-row (rbind.data.frame drops
  zero-row arguments, and the all-empty case returns NULL);
- the polygon visible-cover arithmetic (both sides in 3857, so the ratio holds);
- the paging loop's offset and dedup;
- `cache_key_hash` parts (all scalar or typed; the WKB list branch);
- `cache_write_atomic` and the COG sidecar check;
- `sf::gdal_utils("warp")` returns TRUE on success, so `isTRUE(ok)` is right;
- the warning handler records and muffles, then aborts after the call;
- the mocks take `...` on top of real signatures that match the calls;
- the `-te` order and `-tap` / `-ovr NONE`;
- the INT1U / `NAflag = 0` write, with 0 raised to 1;
- curl and jsonlite are declared in Imports.

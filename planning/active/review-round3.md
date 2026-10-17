# Code-check round 3: branch 105-readme-describe-accuracy-assessment-brea (2026-10-17)

Reviewer: subagent, read-only on the repo. Numbers recomputed with `pkgload::load_all()` on the
bundled reach (`dft_rast_transition(classified, "2017", "2023")`), and patches counted per map group
with `terra::patches(directions = 8)`. Viewed `man/figures/readme-change.png`.

## Mechanism behind round 1 finding 1

A number is computed over the set one artefact defines, and the text puts it beside a different
artefact, so the reader takes the denominator (or the comparison base) from the wrong set. In round 1
the 123 ha came from `dft_rast_transition()$summary` (cells valid in both years, which is the
`touches = TRUE` footprint of the AOI) and sat under a white line labelled "Floodplain" (the 103.5 ha
polygon). The same mechanism is reached wherever a count or comparison is computed at one grain
(cells, summary rows, map groups) and read at another (outline, change set, single transitions).

## Findings

- **[false-claim, minor]** README.md:13 (caption): "'Other change' lumps 1.2 ha of smaller
  transitions." The comparison base is defined by one artefact and read against another. "Smaller"
  holds for map **groups**, which the script asserts (data-raw/readme_figure.R:32-33:
  21.11 / 9.98 / 1.73 / 1.21 ha). It does not hold for **transitions**, the word the caption uses
  (drift's own term for a from/to pair, one row of `$summary`). The largest lumped transition,
  Rangeland to Trees (0.85 ha, 85 cells), is larger than Rangeland to Water (0.75 ha, 75 cells),
  which is named, inside "Became water". It is also 70% of the 1.2 ha "Other" total. A reader who
  takes "smaller transitions" literally would conclude no lumped transition exceeds a named one, and
  that is false. Fix in wording, e.g. "lumps 1.2 ha of six other transitions" or "of the remaining
  transitions".

- **[false-claim, minor; comment only]** data-raw/readme_figure.R:22: "Group the transitions so the
  map carries four colours, not fourteen." This is the same mechanism with a count. 14 is the row
  count of `result$summary`, which includes the 4 unchanged pairs (Trees/Trees, Rangeland/Rangeland,
  Water/Water, Built Area/Built Area). The script drops those on line 26 (`s[s$from_class != s$to_class, ]`), and they are drawn
  transparent, not coloured. Without grouping the map would carry **10** colours (measured:
  `sum(from_class != to_class)` = 10). Harmless to the output; the comment states a false count.

No bugs or security issues.

## Mechanism enumeration

Every number, unit, area, count or quantifier in the branch's text, with the artefact that defines
it and the one it is read against.

| Where | Claim | Defined by | Read against | Verdict |
|---|---|---|---|---|
| README caption | "between 2017 and 2023" | `from`/`to` layers in the script | legend title, map | True |
| README caption | "34 of the 123 ha mapped" | 34.03 = sum of change rows; 123.11 = all `$summary` rows = 12,311 cells valid in both years (both years have 12,311 non-NA, so "mapped" is unambiguous) | "mapped", not the outline | True (round 1 fix holds) |
| README caption | "changed class" | `from_class != to_class` | same | True |
| README caption | "'Other change' lumps 1.2 ha" | 1.21 = six transitions (0.85 + 0.28 + 0.03 + 0.02 + 0.02 + 0.01) | legend key "Other change" | True |
| README caption | "of smaller transitions" | group totals (script assertion) | single transitions | **False at transition grain** (Finding 1) |
| README caption | "a reach of Neexdzii Kwa (Upper Bulkley River), BC" | bundled extdata | — | True |
| Alt text | "large orange areas where trees became rangeland" | trees_rangeland, 57 patches, 21.11 ha, largest 799 cells | PNG | True |
| Alt text | "a yellow field" (singular) | crops_rangeland: 2 patches, 996 + 2 cells | PNG | True (the 2-cell patch is not visible) |
| Alt text | "thin blue edges where land became water" | to_water: 10 patches, largest 59 cells, at the east edge | PNG | True |
| Alt text | "a few small pink patches of other change" | other: 18 patches, 121 cells total, largest 35; about 3 visible at 1050 px | PNG | True as drawn |
| Alt text | "outlined in white" | `readme_floodplain` stroke #ffffff | PNG | True |
| Legend title | "Land cover change, 2017 to 2023" | script | caption | True |
| Legend | four keys, one per group | `grp_levels`, CSV class order (asserted line 52) | map fills | True |
| Legend | "Floodplain" | `example_aoi.gpkg` (103.5 ha) | white line only; no area attached to it any more | True |
| Scale bar | 0 / 250 / 500 m | `tm_scalebar(breaks)` on a projected CRS | AOI bbox 3.26 x 3.13 km | Plausible against the frame |
| README example | `n_cells`, `area`, `pct` rows 1-6 | `head(change$summary, 6)` | printed output | Reproduces (round 1); recomputed values match |
| README example | "`area` is hectares" | `unit = "ha"` default, R/dft_rast_transition.R:66 | `area` column | True |
| README example | "head(..., 6)" / "A tibble: 6 x 5" | `head()` | printed header | True |
| README Installation | "The functions that read STAC or Sentinel-2 imagery need gdalcubes" | `check_gdalcubes()` callers: `dft_stac_fetch`, `dft_stac_cube`, `dft_stac_composite`, `dft_index_expr` | every STAC reader | True; `dft_stac_classes()` parses items it is given and reads nothing, and Wayback is not STAC |
| README Installation | "Trajectory break detection also needs bfast" | `dft_rast_break()` only | — | True |
| README opening / DESCRIPTION | "across every year of a series" | `dft_rast_break_class()` reads all `names(classified)` | — | True |
| README opening / DESCRIPTION | "free global land-cover maps" (IO LULC, ESA WorldCover) | `dft_stac_config()` | — | True |
| README opening / DESCRIPTION | "between two dates" | `dft_rast_transition(from, to)` | — | True |
| DESCRIPTION | "from a stratified reference sample" | `dft_accuracy_sample()` | — | True |
| README Data and methods | "default to kNDVI" | `dft_stac_cube(index = "kndvi")` | — | True |
| README Data and methods | "sub-metre imagery" (Wayback) | zoom 10-22 | — | True at the zooms used |
| README Ecosystem | "2017-2023, by watershed group" | flooded's README, verbatim | — | Accepted (not re-flagged) |
| Script comment, line 22 | "four colours, not fourteen" | 14 = all `$summary` rows | change set (10) | **False** (Finding 2) |
| Script comment, lines 23-24 | "The named groups are the three largest kinds of change ... the assertion fails if the data no longer says so" | `by_group` sorted group totals, `stopifnot` line 33 | groups | True at group grain, which the comment names ("kinds of change") |
| Script comment, line 8 | "Unchanged ground is left transparent" | `classify(others = NA)` over change ids only | PNG | True |
| Script comment, line 53 | "one fill opacity for every class" | `stopifnot(length(fill_opacity) == 1)`; CSV 0.5 x 4 | — | True |
| Script comment, line 59 | "Canvas 7 x 6 in" | `fig_w`, `fig_h`; PNG 1050 x 900 at 150 dpi | — | True |
| Script comment, lines 4-5 | change layer "needs nothing else" (no network) | bundled extdata | — | True (network sense; tmap/gq are packages, not data) |
| CSV | `fill_opacity` 0.5 on all four classes | drift_readme.csv | script assertion | True |
| _pkgdown.yml | each export in one section | `check_pkgdown()` clean (round 1) | — | True |

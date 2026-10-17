## Outcome

Rewrote the README to describe what drift does today, machinery first and in plain language: fetch land cover,
compare it between two dates and across the annual series, and turn the change into maps, tables and polygons,
with one sentence on checking change against Sentinel-2 and Esri Wayback imagery, accuracy sampling and overlay
tags. Added a README map (`data-raw/readme_figure.R` → `man/figures/readme-change.png`) of 2017→2023 change on the
bundled Neexdzii Kwa reach, a bundled-data example with real output, all four articles, the ecosystem table, and
data and methods. The docs URL moved to `www.newgraphenvironment.com/drift/` (github.io redirects there), the
DESCRIPTION Description matches the opening, the CITATION.cff workflow keeps New Graph Environment Ltd. as an
author, and the pkgdown reference index is grouped into eight sections. Learned: the user wants the README to be
about the machinery, not the QA story; and the published stac_floodplains_bc transition scheme (destination-class
colours at 50%) nearly vanishes over imagery, so the README map keeps its own grouped colours at 50%.

## Measurement

- Bundled reach, IO LULC 2017→2023: 34.03 of 123.11 ha mapped changed class (12,311 valid cells; the AOI polygon
  is 104 ha, the rest is cells its outline touches). Groups: Trees→Rangeland 21.11, Crops→Rangeland 9.98,
  to water 1.73, other 1.21 ha (10 change transitions of 14 summary rows).
- README 269 → 727 words (`wc -w`); the prose stays short, growth is the ecosystem table, example and alt text.
- Tests `[ FAIL 0 | WARN 0 | SKIP 19 | PASS 1709 ]`. 24 README links 200. 33 exports, one reference section each.
- `/code-check branch`: 4 rounds (2, 0, 2, 0 findings), all fixed; none inside an earlier fix. Wrong turns kept in
  `review-round*.md`: the caption's "of 123 ha" read as the floodplain area, then "smaller transitions" was false
  at the transition grain.

Closed by: PR for #105 (see `git log`); follow-up soul#446 (404 vignette link in the shared cartography convention).

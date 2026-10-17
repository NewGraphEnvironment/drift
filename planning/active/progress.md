# Progress — README rewrite (#105)

## Session 2026-10-17

- Plan-mode exploration — phases approved by user (map: bundled reach, what changed to what)
- Created branch `105-readme-describe-accuracy-assessment-brea` off main
- Scaffolded PWF baseline from issue #105 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) landed; condensed to `review-1.md`. Folded in: machinery-first opening, attribute
  wording (tags, not causes), gdalcubes note covers composite/index too, Title kept and tagline/About match it,
  Ecosystem table with verbatim roles, mapaccuracy/Planetary Computer/kNDVI in Data and methods, caption names
  what "Other change" lumps, URL commit pairing, `gh repo edit` after merge, export-to-section table.
- Phase 1: `data-raw/readme_figure.R` → `man/figures/readme-change.png` (1050x900, RGB, no alpha). Groups:
  Trees→Rangeland 21.11 ha, Crops→Rangeland 9.98, to water 1.73, other 1.21 (34.0 of 123.1 ha changed).
  Colours from `inst/cartography/drift_readme.csv`. Two placement passes: legend moved from top-left
  (it hid a floodplain arm) to bottom-right, credits moved to the caption, legend type 1.0→0.9 to clear an edge.
- Phase 2: README rewritten in readme.md order. Opening three sentences, machinery first; checks (Sentinel-2,
  Wayback, accuracy, overlay tags) in one sentence. Example on bundled data with real output (head of summary).
  Ecosystem table copied verbatim from flooded's. All 24 links 200 (curl). wc -w 269 → 725; prose is short,
  the growth is the ecosystem table, code + output, and alt text.

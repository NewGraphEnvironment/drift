# Code-check round 2 — branch 105-readme-describe-accuracy-assessment-brea (2026-10-17)

Reviewer: subagent, read-only on the repo (figure re-run in a scratchpad `git archive HEAD` copy).
Focus: commit f6431b9 (50% fill opacity read from the registry CSV, caption "34 of the 123 ha
mapped"), plus a re-check of alt text and caption against the half-opacity render.

## Clean

No bugs, security issues or false claims found.

## Verification done

- **Opacity read from gq's registry is correct.** `gq::gq_reg_custom()` (gq 0.16.0) parses
  `drift_readme.csv` into `layers$readme_change$classification$classes$<value>$opacity` (num 0.5 for
  all four classes), which is exactly the path `data-raw/readme_figure.R` walks.
  `gq_tmap_classes()` returns only field/values/labels (no opacity), so reading the classes directly
  is necessary, not a bypass. A missing opacity would make `vapply(..., numeric(1))` error, and
  mixed opacities trip `stopifnot(length(fill_opacity) == 1)`: both fail loudly. The floodplain
  layer parses to `stroke = list(color = "#ffffff", width = 2, opacity = 1)`; the script ignores
  stroke opacity, which is harmless at 1.
- **The committed PNG is made by the committed script.** Re-ran `Rscript data-raw/readme_figure.R`
  from a `git archive HEAD` copy (51.5 s wall): group areas 21.11 / 9.98 / 1.73 / 1.21, output
  1050 x 900, `cmp` against `man/figures/readme-change.png` is byte-identical (1,451,952 bytes).
- **Caption.** `sum(summary$area)` = 123.11 ha, changed = 34.03 ha; both years have 12,311 valid
  cells, so "34 of the 123 ha mapped changed class" is true and no longer implies the 103.5 ha
  outlined floodplain is the denominator (round 1 finding 1 resolved). "Other change" = 1.21 ha, true.
- **Alt text against the half-opacity render** (viewed the PNG): white outline, large orange-brown
  trees-to-rangeland areas (largest in the south-west lobe), one yellow crops-to-rangeland field
  (centre north), thin blue strips at the east edge, a few small pink patches (north centre and
  beside the legend). Each element named in the alt text is present and in that colour family at
  50% over imagery.
- f6431b9 touched only README.md (caption), the script, the CSV and the PNG; DESCRIPTION,
  `_pkgdown.yml`, the Rd and the workflow are unchanged since round 1, whose checks stand.

## Observation, not a finding

The legend swatches are drawn at the same 50% alpha over the `grey15` legend box, so they render
darker than the same fills over the imagery (most visibly "Became water": dark slate in the key,
pale blue on the map). Hues still match one-to-one, so the legend is not wrong; noted only in case
the user wants opaque keys.

# Code-check round 1 — branch 105-readme-describe-accuracy-assessment-brea (2026-10-17)

Reviewer: subagent, read-only on the repo (runs done in scratchpad copies via `git archive HEAD`).

## Findings

- **[false-claim, minor]** README.md:14 (caption) — "34 of 123 ha changed class" sits under a map whose
  white outline is labelled "Floodplain", so 123 ha reads as the floodplain's area. It is not. The
  bundled AOI (`inst/extdata/example_aoi.gpkg`) is **103.5 ha**; the 123.1 ha is the 12,311 cells
  valid in both years, which equals exactly the `rasterize(touches = TRUE)` footprint of the AOI
  (measured: touches-mask cells = 12,311; cells whose centre is inside the AOI = 10,397). So 19.6 ha
  (16%) of the stated area, and 5.25 of the 34.0 ha of change (2,878 of 3,403 changed cells have
  centres inside), lie in the boundary ring of cells that only touch the outline. Visible on the map
  as orange patches beyond the white line. The numbers are what `dft_rast_transition()` returns; it
  is the implied denominator that is off. Fix in wording, e.g. "34 of the 123 ha mapped (cells
  touching the floodplain) changed class", or drop the denominator.

- **[fragile, low]** .github/workflows/update-citation-cff.yaml:30 vs inst/CITATION — README.md:85
  offers `citation("drift")` and CITATION.cff as interchangeable. After this branch merges, the
  workflow (run in a scratch copy, cffr 1.4.2, output valid) writes authors *Irvine A; New Graph
  Environment Ltd.* and `url: https://www.newgraphenvironment.com/drift/`, while `inst/CITATION`
  still renders *Irvine A (2026) ... New Graph Environment Ltd. ... <https://github.com/...>*
  (authors filtered to role "aut"; first URL). Two citations of one package with different author
  lists. Intentional per plan (company as cff author), so only flagging that the two now disagree;
  not blocking.

No bugs or security issues found in `data-raw/readme_figure.R`, `inst/cartography/drift_readme.csv`,
`_pkgdown.yml`, DESCRIPTION, or the Rd.

## Verification done

- README example reproduced exactly (`pkgload::load_all()`; tibble 6 x 5, every value and the
  `0.8` row identical). `area` is ha: `dft_rast_transition(unit = "ha")` default, R/dft_rast_transition.R:66.
- `data-raw/readme_figure.R` re-run from a `git archive HEAD` copy: 73 s, prints group areas
  21.11 / 9.98 / 1.73 / 1.21, writes a PNG of **identical byte size** (1,436,503) and dims 1050 x 900,
  colour type 2 (RGB, no alpha) — the committed figure is made by the committed script.
- `pkgdown::check_pkgdown()`: no problems; 33 exports, each listed once.
- `url:` at a `/drift/` path writes no CNAME (`pkgdown:::cname_url` returns NULL for non-root
  paths, pkgdown 2.2.0); deploy uses `clean: true`. `https://www.newgraphenvironment.com/drift/pkgdown.yml`
  is 200, so downlit autolinking from sibling sites via the new DESCRIPTION URL still resolves.
- All README links 200: site root, 4 articles, reference, news, LICENSE.html, CITATION.cff on
  GitHub, 8 ecosystem sites, gq repo (public), bfast and mapaccuracy CRAN pages (bfast 1.7.2,
  mapaccuracy 0.1.2 current, not archived).
- Ecosystem table matches flooded's README verbatim except the swapped bold/this-package row and the
  added gq row.
- `inst/cartography/drift_readme.csv` header identical to `drift_temporal.csv`; `gq_reg_custom()`
  parses it, class order equals `grp_levels`, stroke list well-formed.
- inst/CITATION takes the first DESCRIPTION URL (GitHub), unchanged.

## Claim enumeration

### README opening / tagline

| Claim | Verdict | Evidence |
|---|---|---|
| "fetches free global land-cover maps" (IO LULC, ESA WorldCover) | True | R/dft_stac_config.R:39-50 (Planetary Computer, free, global products) |
| "or your own classified rasters" | True (via any STAC collection, or a local SpatRaster passed to classify) | R/dft_stac_fetch.R:4-6, 97-99 (`stac_url`/`collection`/`asset` override) |
| "for a floodplain" | True (any sf polygon AOI) | R/dft_stac_fetch.R:36 |
| "compares them between two dates" | True | R/dft_rast_transition.R:59 |
| "and across every year of a series" | True | `dft_rast_break_class()` reads `names(classified)` as the series |
| "turns the change into maps, tables and change polygons" | True | `dft_map_interactive()`, `$summary`, `dft_transition_vectors()` |
| "fetches dated Sentinel-2 ... imagery" | True | `dft_stac_composite()` per-year composites |
| "and Esri Wayback imagery" | True | `dft_wayback_fetch()` |
| "supports accuracy assessment" | True | `dft_accuracy_sample/estimate/size/labels` |
| "tags change areas with records you supply, such as fire perimeters or cutblocks" | True; tags, does not attribute cause | R/dft_transition_attribute.R:4, 16-17 |
| "shows where streamside forest, fields and channels have changed" | Value statement; consistent with IO LULC classes (Trees, Crops, Water) | — |

### Figure caption and alt text

| Claim | Verdict | Evidence |
|---|---|---|
| change 2017 to 2023, Neexdzii Kwa reach, bundled data | True | data-raw/readme_figure.R:16-20 |
| "34 of 123 ha changed class" | Numbers true (34.03 / 123.11); **denominator is the touches-mask cell area, not the 103.5 ha floodplain outlined** | Finding 1 |
| "Other change" lumps 1.2 ha | True (1.21: Rangeland->Trees 0.85, Built->Rangeland 0.28, Water->Trees 0.03, Flooded veg->Rangeland 0.02, Snow/Ice->Rangeland 0.02, Built->Trees 0.01) | summary, rerun |
| "Became water" group | True: Trees->Water 0.98 + Rangeland->Water 0.75 = 1.73 | rerun |
| three named groups are the three largest | True, asserted in script | readme_figure.R:33 |
| alt: orange trees->rangeland large, yellow crops field, thin blue water edges, few small pink other, white outline, aerial imagery | True against the PNG (#d55e00, #f0e442, #56b4e9, #cc79a7; white #ffffff stroke) | PNG, drift_readme.csv |
| Land cover: Esri / Impact Observatory IO LULC; Imagery: Esri World Imagery | True | readme_figure.R:59 `Esri.WorldImagery` |

### Installation

| Claim | Verdict | Evidence |
|---|---|---|
| "functions that read STAC or Sentinel-2 imagery need gdalcubes" | True: `dft_stac_fetch`, `dft_stac_cube`, `dft_stac_composite`, `dft_index_expr` (cube) call `check_gdalcubes()`; Wayback and `dft_stac_classes` do not | R/dft_stac_fetch.R:109, dft_stac_cube.R:173, dft_stac_composite.R:182, dft_index_expr.R:53 |
| gdalcubes "archived on CRAN" | True | R/dft_stac_fetch.R:920-933 |
| fork "reports failed reads" | Consistent with #87 notes / CLAUDE.md | — |
| "Trajectory break detection also needs bfast" | True; only `dft_rast_break()` | R/dft_rast_break.R:65 |
| pin `@vX.Y.Z` | Tags are `v`-prefixed (v0.24.2) | git tag |

(Not a false claim, noted only: `dft_map_interactive()` also needs leaflet + leaflet.extras (+ leafem for RGB), Suggests not named in Installation; `rlang::check_installed()` offers the install, R/dft_map_interactive.R:115, 399.)

### Example

| Claim | Verdict | Evidence |
|---|---|---|
| pasted output | Reproduces exactly | rerun |
| "`area` is hectares" | True (default `unit = "ha"`) | R/dft_rast_transition.R:66 |
| "`dft_stac_fetch()` fetches the land cover for a polygon" | True | R/dft_stac_fetch.R:36 |

### Learn more

| Claim | Verdict | Evidence |
|---|---|---|
| four article titles and URLs | Titles match YAML; all 200 | vignettes/*.Rmd, vignettes/articles/*.Rmd |
| floodplain-change-dating: "dating mapped change with Sentinel-2 and Esri Wayback imagery" | Matches article title | vignettes/articles/floodplain-change-dating.Rmd |

### Data and methods

| Claim | Verdict | Evidence |
|---|---|---|
| IO LULC, ESA WorldCover, Sentinel-2 L2A from Microsoft Planetary Computer STAC through gdalcubes | True | R/dft_stac_config.R:41,47,54 |
| Wayback sub-metre dated imagery | True | R/dft_wayback_*.R |
| "Vegetation trajectories default to kNDVI" | True | R/dft_stac_cube.R:157 |
| abrupt breaks from BFAST Monitor | True | R/dft_rast_break.R:4 |
| gradual trends Theil-Sen + Mann-Kendall | True | R/dft_rast_trend.R:9-12, 92-95 |
| accuracy/area follow Olofsson 2014, Stehman 2014 through mapaccuracy | True | R/dft_accuracy_estimate.R:38, 182 |

### DESCRIPTION Description (and drift-package.Rd)

Same claims as the opening, plus "estimate accuracy and error-adjusted area from a stratified
reference sample" (True, `dft_accuracy_sample()` stratified, `dft_accuracy_estimate()` returns
`$area` with CIs) and "Under active development" (True; lifecycle experimental). Rd regenerated
from DESCRIPTION (author line now carries affiliation and "Ltd.", which DESCRIPTION already had).

### Citation and license

| Claim | Verdict | Evidence |
|---|---|---|
| `citation("drift")` | Works (inst/CITATION) | rendered |
| CITATION.cff link | 200 on main | curl |
| MIT, LICENSE.html | True, 200 | DESCRIPTION, curl |
| the two citations equivalent (implied) | Author lists and URL differ after merge | Finding 2 |

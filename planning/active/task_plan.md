# Task: README: describe accuracy assessment, break detection and change attribution, not just fetch-classify-summarize (#105)

The README (47 lines) describes drift at about v0.1: fetch, classify, summarize. The package does far more, and that is what makes it credible for monitoring. User direction (2026-10-17): plain language, not much detail, one strong map that is easy to read — bundled Neexdzii Kwa reach coloured by what changed to what.

## Phase 1: README map
- [x] `data-raw/readme_figure.R` (loads source tree): classify the bundled 2017 and 2023 rasters,
      `dft_rast_transition()` 2017→2023, keep the 3–4 largest transitions by area, lump the rest as
      "Other change", unchanged cells muted; floodplain AOI outline
- [x] Colours from a new `inst/cartography/drift_readme.csv` via `gq_reg_custom()` (no hex in the
      script), drawn with tmap v4; legend, scale bar, no title; faded imagery basemap only if it
      passes cartography check 11
- [x] Write opaque `man/figures/readme-change.png`; self-review all 12 cartography checks at ~700 px

## Phase 2: README rewrite (soul `readme.md` order)
- [x] Title + hex (alt text), lifecycle badge, tagline
- [x] Opening, 2–3 plain sentences: measures land-cover change in floodplains from free satellite
      maps, separates lasting change from map noise, checks accuracy, ties change to causes such as
      fire and harvest; screening tool that informs restoration planning and monitoring
- [x] Figure with alt text and one-line caption
- [x] Installation: `pak`, the gdalcubes fork note (shortened), dev-status line with
      `@vX.Y.Z` pin placeholder
- [x] Short example on bundled data with its real printed output (no network)
- [x] Short "what it does" list by stage (fetch, change, check, attribute, map) — high level,
      no function names — folded into the opening instead (user: little detail; review #16)
- [x] Learn more: one line per vignette/article (all four), then the reference
- [x] Ecosystem (flooded, gq), Data and methods (IO LULC, ESA WorldCover, Sentinel-2, Esri
      Wayback, Olofsson et al. 2014 / Stehman 2014, BFAST), Citation, License
- [x] Docs URL → `https://www.newgraphenvironment.com/drift/` everywhere it is set

## Phase 3: Matching texts
- [x] DESCRIPTION `Description` in step with the opening, "Under active development.", URL → www;
      `_pkgdown.yml` url → www; `devtools::document()` (refreshes `drift-package.Rd`)
- [x] CITATION.cff workflow: `cff_create(authors_roles = c("aut", "cre", "cph"))`
- [ ] GitHub About + homepage via `gh repo edit` to match the tagline — after merge (review #14), command in the PR body

## Phase 4: pkgdown reference index
- [ ] `reference:` sections by purpose: Fetch imagery and land cover; Classify and summarize;
      Change between two dates; Change across the annual series; Spectral trajectories; Accuracy
      and area; Maps; Sources, classes and cache
- [ ] `pkgdown::check_pkgdown()` clean

## Validation

- [ ] Every function the README names is exported; every link resolves (curl)
- [ ] Example output pasted from a real run; word count before (269) / after reported
- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch, with every README claim enumerated against code)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

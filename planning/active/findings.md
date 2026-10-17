# Findings — README rewrite (#105)

## Issue context

## Problem

The README (47 lines) describes drift at about v0.1: fetch, classify, summarize. The package is at v0.23.0 and does far more, and that is what makes it credible for monitoring.

## Findings

**Shipped but not in the README (underselling)**
- Accuracy assessment and error-adjusted area estimates (Olofsson et al. 2014): `dft_accuracy_*` (v0.19.0)
- Change-over-time (break) detection: `dft_rast_break_class()` (v0.14.0), `dft_break_category()`, `dft_break_strength()` (v0.16.0)
- Misregistration tagging, `dft_transition_artifact()` (v0.13.0)
- Change patches attributed to overlays such as fire and harvest, `dft_transition_attribute()` (v0.8.0)
- Change patches as polygons, `dft_transition_vectors()` (v0.2.0)
- Sentinel-2 index cubes (NDVI, NDMI), `dft_stac_cube()`, `dft_index_*` (v0.3.0)
- Dated cloud-masked composites and clear-day counts, `dft_stac_composite()` (v0.18.0, v0.20.0)
- `dft_map_interactive()`
- Two of the three vignettes, including "Trajectories as a Check on Land-Cover Change"

**Stale**
- README.md:47 links `www.newgraphenvironment.com/drift/`, while DESCRIPTION and `_pkgdown.yml` use `newgraphenvironment.github.io/drift/`. Pick one.

## Tasks

- [ ] Rewrite the opening: measure land-cover change in floodplains, separate real change from noise, attribute it to causes
- [ ] Add a "what it does" section by workflow stage (fetch, change, check accuracy, attribute, map)
- [ ] List all three vignettes
- [ ] Make the docs URL consistent
- [ ] Group the `_pkgdown.yml` reference index by purpose. It has no `reference:` sections today, so the docs site shows a flat alphabetical list.

## Context

Audited 2026-10-14 against `origin/main` @ `54ac6cb`, from README, DESCRIPTION, NEWS, NAMESPACE and vignettes. Verify each item against the code before acting. Versions cited are where a capability landed.

The New Graph website will describe this package from its README (NewGraphEnvironment/newgraphenvironment.github.io#53), so the README is the source of truth for the public one-liner. Plain language in the opening paragraph: what it does today, and what restoration planning, implementation or monitoring decision it informs.


## Exploration (2026-10-17)

- Docs URL: `newgraphenvironment.github.io/drift/` redirects to `www.newgraphenvironment.com/drift/`
  (curl, both end 200 at www). So **www is canonical**; DESCRIPTION and `_pkgdown.yml` use github.io.
- Four documents, not three: vignettes `land-cover-change`, `trajectory-break-detection`; articles
  `temporal-composition`, `floodplain-change-dating`.
- `_pkgdown.yml` has no `reference:` sections (33 exports, flat list).
- Bundled data: `inst/extdata/example_2017..2023.tif` + `example_aoi.gpkg`, 10 m, EPSG:32609,
  ~123 ha. 2017→2023 top transitions: Trees→Rangeland, Crops→Rangeland, plus water/trees stable.
- `man/drift-package.Rd` is stale (says "New Graph Environment", DESCRIPTION has "Ltd.").
- CITATION.cff workflow calls `cffr::cff_create()` without `authors_roles = c("aut","cre","cph")`,
  so the company is not an author in CITATION.cff.
- GitHub About: "R package for change analysis - …", homepage `http://www.newgraphenvironment.com/drift`.
- tmap, gq, maptiles installed; `inst/cartography/` holds gq custom CSVs (carry every column).


## Errors Encountered

| Error | Resolution |
|-------|------------|

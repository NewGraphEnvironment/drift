# Task: Article redo: dating detected floodplain change with Sentinel-2 and Esri Wayback (#108)

The first article (`wayback-change.Rmd`, PR #109) was about Wayback mechanics and was built on the
superseded `bulk_co_ff04` item. The user asked for a redo about our use case: fetch the latest floodplain
product from STAC, use drift to date the detected change, show each change with the best imagery available,
keep numbers to one table, fold all code.

## Phase 1: data-raw script
- [ ] `data-raw/floodplain_change_dating.R`: STAC item `bulk_all_ff04` via rstac (record processing date,
      drift version); floodplain `all_ff04`; annual classified 2017-2023 cropped to the box
- [ ] `dft_rast_break_class()` + `dft_rast_break_category()`: per-pixel change year for clean switches;
      change areas = connected clean-switch pixels of one year, with from/to class and size
- [ ] Sentinel-2 composites 2017-2023 on one shared stretch; Wayback captures/picks/chips as before
- [ ] Wayback before/after chips for the change areas Wayback brackets; cutblock start year per area as
      corroboration
- [ ] `## ----` sections for every block the article shows; deterministic writes; warm rerun byte-identical

## Phase 2: article
- [ ] `vignettes/articles/floodplain-change-dating.Rmd`: folded code via a source hook; fetch code read from
      the script
- [ ] Sections: what changed and when (lead map) -> what drift gives us (one table) -> the changes Wayback
      can show -> the changes only Sentinel-2 can show -> why (Esri has released nothing newer than 2020
      here) -> the numbers (one table) -> limits
- [ ] Remove `wayback-change.Rmd`, its data dir, `data-raw/wayback_change.R`; update `.gitignore`,
      `data-raw/README.md`, `research/esri-wayback.md` references

## Phase 3: verify
- [ ] `pkgdown::build_article()` offline; figures read at page width; code folds
- [ ] `pkgdown::check_pkgdown()`; no footnotes
- [ ] `/code-check branch`

## Validation
- [ ] Tests pass (no `R/` changes)
- [ ] `/code-check` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion (into the existing #108 archive)

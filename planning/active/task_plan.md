# Task: Article redo: dating detected floodplain change with Sentinel-2 and Esri Wayback (#108)

The first article (`wayback-change.Rmd`, PR #109) was about Wayback mechanics and was built on the
superseded `bulk_co_ff04` item. The user asked for a redo about our use case: fetch the latest floodplain
product from STAC, use drift to date the detected change, show each change with the best imagery available,
keep numbers to one table, fold all code.

## Phase 1: data-raw script
- [x] `data-raw/floodplain_change_dating.R`: STAC item `bulk_all_ff04` via rstac (record processing date,
      drift version); floodplain `all_ff04`; annual classified 2017-2023 cropped to the box
- [x] `dft_rast_break_class()` + `dft_rast_break_category()`: per-pixel change year for clean switches;
      change areas = connected clean-switch pixels of one year, with from/to class and size
- [x] Sentinel-2 composites 2017-2023 on one shared stretch; Wayback captures/picks/chips as before
- [x] Wayback before/after chips for the change areas Wayback brackets; cutblock start year per area as
      corroboration
- [x] `## ----` sections for every block the article shows; deterministic writes; warm rerun byte-identical

## Phase 2: article
- [x] `vignettes/articles/floodplain-change-dating.Rmd`: folded code via a source hook; fetch code read from
      the script
- [x] Sections: what changed and when (lead map) -> what drift gives us (one table) -> the changes Wayback
      can show -> the changes only Sentinel-2 can show -> why (Esri has released nothing newer than 2020
      here) -> the numbers (one table) -> limits
- [x] Remove `wayback-change.Rmd`, its data dir, `data-raw/wayback_change.R`; update `.gitignore`,
      `data-raw/README.md`, `research/esri-wayback.md` references
      (data-raw/README.md never named the old script; nothing to change there)

## Phase 3: verify
- [x] `pkgdown::build_article()` offline; figures read at page width; code folds
- [x] `pkgdown::check_pkgdown()`; no footnotes
- [ ] `/code-check branch`

## Validation
- [x] Tests pass (no `R/` changes)
- [ ] `/code-check` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion (into the existing #108 archive)

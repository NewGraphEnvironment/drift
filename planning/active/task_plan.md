# Task: pkgdown article: temporal composition of published land-cover change (Bulkley worked example) (#66)

A published floodplain land-cover change layer compares two epochs (2017 vs 2023). #62 measured
what sits inside that comparison across the four watershed groups with a complete 2017-2023 IO
LULC series: only 19.7-31.0% of endpoint-changed area is a sustained switch, 29.4-36.4% turns on
a single endpoint year, and 39.6-48.5% never settles. A further 3.2-9.9% of floodplain area
flickers while reading identical at both endpoints.

Those results live in `inst/notes/temporal-qa-groups.md` and `data-raw/logs/break_class_groups/`,
both of which assume familiarity with the package. This issue produces a short pkgdown **article**
stating the method and the result for someone who consumes the published products and does not use
drift — so that a quoted hectare figure is read with the right error bar.

## Decisions taken at the plan gate

| decision | choice |
|---|---|
| Tree loss | Shares headline; both totals (2,050.4 ha pixel-level, 1,565.1 ha published) footnoted with the definition each is computed under |
| Class set | Include Trees -> Water in the headline shares; the table carries the excluding-Water column |
| Figure 2 | Locator panel plus zoomed reach |
| Figures 3 + 4 | Combined into one faceted figure — three figures total |

## Phase 1: Colour registry and build scaffolding

- [x] `inst/cartography/drift_temporal.csv` in `gq_reg_custom()` schema, four categories, sourced palette
- [x] Spike `gq_reg_merge(gq_reg_main(), gq_reg_custom(path))`; record the working accessor in findings.md
- [x] Add `^vignettes/articles$` to `.Rbuildignore`

## Phase 2: Extend the `summarize` stage

- [x] Record baseline md5 of the three summarize outputs in findings.md
- [x] `temporal_category(status, break_year)` helper — one definition, both tables
- [x] Emit `inst/extdata/temporal-composition/summary_class_temporal.csv` (unrounded area_ha)
- [x] Emit `summary_treeloss_temporal.csv` with `class_set` named in the data
- [x] Emit article copy of `summary_groups.csv` as a column subset of the existing `out` object
- [x] Five-part guard before any write, incl. positive control that perturbs the rollup
- [x] `inst/extdata/temporal-composition/README.md`; update the logs README
- [x] Run `summarize`; assert baseline hashes unchanged and only new `inst/` files appear
- [x] Cross-check tree-loss table against the independent derivation

## Phase 3: New `article-bulk` stage and the `inst/` artifact

- [ ] Self-check: reproduce committed BULK `summary_change.csv` cell-for-cell before deriving
- [ ] Deterministic patch selection with printed filter counts and a hard stop on an empty set
- [ ] Shared `terra::ext()` crops + `compareGeom()` assertion
- [ ] `bulk_grid_1km.csv` with the `valid == 0` drop (T4) and row-count assertion
- [ ] `bulk_window.csv` provenance incl. the selection rule as a literal sentence
- [ ] `bulk_window.rds` with round-trip assertion and a < 500 KB size guard
- [ ] Re-verify baseline hashes unchanged

## Phase 4: The article

- [ ] `vignettes/articles/temporal-composition.Rmd`, `bookdown::html_document2`
- [ ] Load chunk reads only `inst/extdata/temporal-composition/` + `dft_class_table()`
- [ ] Figure 1: 7 year panels laid 4 x 2, patch outline on each
- [ ] Figure 2: 1 km locator with detail box + native-resolution reach
- [ ] Figure 3: category shares by group, faceted (all change vs tree loss)
- [ ] Exact-values table; approximate values in prose
- [ ] All four limitations stated
- [ ] Word-count guard chunk (message the count, stop above 1000)

## Phase 5: Render and cartographic self-review

- [ ] `pkgdown::build_article()`; no network
- [ ] Walk all 12 cartography checklist points at the delivered width; record point by point
- [ ] `pkgdown::check_pkgdown()`
- [ ] `R CMD build` + `tar tzf`: no `vignettes/articles/`, `inst/` data present

## Phase 6: Cross-links, bookkeeping, PR

- [ ] Link from `inst/notes/temporal-qa-groups.md` above line 81
- [ ] Link from #64, #46, stac_floodplains_bc#67
- [ ] Reconcile issue #66 body (#67 closed; 2,050.4 ha confirmed derivable)
- [ ] `NEWS.md`; `DESCRIPTION` -> 0.15.0 as the final commit
- [ ] `/planning-archive`; `/gh-pr-push`

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

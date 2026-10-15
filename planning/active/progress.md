# Progress — Article: watching forest change with Esri Wayback and Sentinel-2 composites (#108)

## Session 2026-10-15

- Probed Wayback captures over the box before filing (182 releases since 2015, 16 min): three captures, 2014/2016/2020
- Filed #108 with decisions (pkgdown article, S2 key years only, overview + window, static panels)
- Plan-mode exploration — phases approved by user
- Created branch `108-article-watching-forest-change-with-esri` off main
- Scaffolded PWF baseline from issue #108 with approved phases
- Next: start Phase 1
- Plan review 1 (Plan agent) → `review-1.md`. Folded in before Phase 1 landed: cover 0.5 + own-capture
  assertion (B1), fixed release end date (B2), window-cover check (G1), time stripped and no gpkg (G2),
  .gitignore for article sidecars (G3), fetch retry (G4), zoom 16:18 (A1), s2.csv haze check (A2), one
  5 m overview (S1), NAflag 0 (S2). Dropped the inst/extdata fallback (O1, verified in pkgdown/rmarkdown
  source by the reviewer) and the data-raw/README row (G5). First fetch run killed after 25 releases to
  pick up these changes.
- Phases 1-2: `data-raw/wayback_change.R` written and run (fetch 22:08Z cold, reruns ~1 min warm). Two fixes found
  by looking (findings "Errors Encountered"): best-cover picks, and one stretch across bands. Window chosen from
  previews. Artifacts 3.6 MB, rerun byte-identical.

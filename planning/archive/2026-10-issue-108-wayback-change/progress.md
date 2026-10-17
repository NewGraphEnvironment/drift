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
- User asked (mid-run) for the ff04 floodplain on the maps. Taken from the published stac-floodplains-bc item, not
  rebuilt with flooded: of the two items whose bbox holds the box, `bulk_co_ff04` covers 359.7 ha of it and
  `fran_ch_ff04` none. Written as WKT in `floodplain.csv` (a gpkg would churn); outline colour from gq's
  `floodplains` style with a white halo.
- Phase 3: `vignettes/articles/wayback-change.Rmd` written and rendered with `pkgdown::build_article()`.
  Figures read at page width; fixed a black (transparent) background and clipped panel labels. Claims checked
  against the cached metadata: all 54 releases from 2022-05-18 show 2020-09-18; the 2016 releases draw 2014 on
  the other 19%; warm captures 32 s. The hand-typed 57% now comes from `captures.csv` (`cover_last`).
  Body prose 1,030 words, file 290 lines.
- Phase 4: `pkgdown::check_pkgdown()` no problems; `devtools::test()` FAIL 0 | PASS 1709 | SKIP 19; 0 footnote-ref,
  0 `\@ref`; the 4 printed code blocks are the eval = FALSE workflow chunks, so the render needs no network.
- `/code-check branch`: 4 rounds (+1 plan review = 5 reviewer agents). r1 6 findings fixed; r2 clean; r3 2 findings
  (display chunks echoed hidden-helper code; clipped floodplain drawn along the box frame), neither inside an
  earlier fix, fixed; r4 clean. Loop ended on a clean round with no inside-a-fix finding.

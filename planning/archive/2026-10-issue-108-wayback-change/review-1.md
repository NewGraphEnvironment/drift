# Plan review 1 (#108) — Plan agent, 2026-10-15

Returned as reply text (Plan agents cannot write); recorded here. Disposition in progress.md.

- B1 cover 0.8 is 2 points under 2016's 82%, measured on the lon/lat box, not the UTM rectangle the script uses → cover >= 0.5 and assert each own-year pick returns its own capture.
- B2 dft_wayback_releases() is uncached (R/dft_wayback_releases.R:34-37); open-ended release range moves meta/captures/picks and the 2020 chip's release_id each new release → end-date literal.
- G1 window could overlap the 18% of the 2016 release that shows 2014 → check captures over the window, require cover 1.
- G2 composites carry time() → writeRaster emits .aux.json; window.gpkg stores a timestamp → time(r) <- NULL; window as numbers in meta.csv.
- G3 .gitignore covers only inst/extdata/*.aux.xml → add the article dir.
- G4 deep-zoom box fetch is thousands of tiles, one failed tile aborts, tiles uncached → retry wrapper; cap zoom.
- G5 data-raw/README.md has no script table → drop that checkbox or add a section.
- A1 zoom kept is the deepest covering the box; fetching 0.5 m from 0.17 m tiles wastes ~8x → zoom 16:18.
- A2 a hazy 2023 skews the pooled stretch → record per-year median red, inspect.
- A3 Jun-Jul composites date a change as between July Y-1 and July Y → state so in prose.
- A4 a 600 m window in a 1x3 row is ~2.5 m/px on the page → layout choice.
- O1 pkgdown knits from the Rmd dir (rmarkdown::render setwd) → relative path works; drop inst/extdata fallback.
- O2 2022 Jun-Jul composite is post-boundary; crs matches auto zone; clip FALSE default.
- S1 overviews for every capture at 2.5 m blow the 5 MB budget → one overview at ~5 m.
- S2 NAflag = NA writes no nodata → check edges.
- C1 writing.md: "capture" used before defined; statement headings → questions; 2x2 for S2 panels.
- C2 counts by code definition: releases searched (2015 on), sub-metre captures, cover = max share drawn on top.
- C3 plan says mid-July, script uses 07-01; add grep for \@ref.

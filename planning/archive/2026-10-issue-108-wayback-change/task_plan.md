# Task: Article: watching forest change with Esri Wayback and Sentinel-2 composites (#108)

## Problem

drift has two dated-imagery read paths, and no article shows either one being used to look at change:

- `dft_wayback_*` (#101) fetches sub-metre Esri Wayback captures. It appears only on its reference pages.
- `dft_stac_composite()` (#79) builds yearly Sentinel-2 true-colour composites. It also appears only on its reference page. `dft_stac_cube()` is in `trajectory-break-detection`, but only as input to break detection.

A reader who wants to see what happened on the ground between two years has no worked example.

## Context from planning

## What exploration changed

- **Cover filter before the pick.** `dft_wayback_pick()` ranks days → res → *later release*; cover is only a
  tiebreak (`R/dft_wayback_pick.R`). Over a polygon, the 2014 capture is also served (at ~18% cover) by
  releases from 2020 on, so an unfiltered 2014 pick would fetch a release that mostly shows 2016. Filter
  `cover >= 0.8` first, as the function doc prescribes.
- **One stretch for the S2 panels.** `dft_stac_composite()` returns float reflectance, a named list per
  year (`R/dft_stac_composite.R` @return). Reuse the internal `rgb_domain()` / `rgb_stretch()`
  (`R/dft_map_interactive.R:349-370`) in the data-raw script (it runs under `pkgload::load_all()`), so the
  four years share one per-band stretch and a brightness difference is real. Wayback chips are already
  8-bit display bytes; no stretch.
- **Artifacts outside the tarball.** `^vignettes/articles$` is in `.Rbuildignore`. `temporal-composition`
  reads `inst/extdata/` (ships); these rasters need not ship, so they go in
  `vignettes/articles/wayback-change/` and the article reads them by relative path (review 1, O1:
  `rmarkdown::render()` setwd()s to the Rmd's directory, and pkgdown passes no `knit_root_dir`).
- CI (`.github/workflows/pkgdown.yaml`) installs `local::.` and renders articles, so every evaluated chunk
  must run from committed files with no network.

## Phase 1: data-raw script — fetch

- [x] `data-raw/wayback_change.R` (header in the `break_class_groups.R` style: purpose, usage, outputs);
      bbox literal from the post; `pkgload::load_all(".")`
- [x] `dft_wayback_releases()` → releases 2015-01-01 to 2026-10-15 (fixed end, review 1 B2) →
      `dft_wayback_captures(aoi, zoom = 16:18)` (zoom 18 is 0.35 m, finer than the grid; review 1 A1);
      write `captures.csv` (one row per distinct capture: date, sensor, res, max cover, releases serving it,
      first release) and the release count
- [x] `dft_wayback_pick()` on `cover >= 0.5` captures (review 1 B1: 2016 was 82% on a smaller box) at each
      capture's own year (2014, 2016, 2020) and at the key years 2018/2020/2022/2023 (07-01 targets);
      assert each own-year pick is its own capture; write `picks.csv` with `days_from_date`
- [x] `dft_wayback_fetch()` for the three captures over the box, `crs = "EPSG:32609"`, `res = 0.5`
- [x] `dft_stac_composite(aoi, years = c(2018, 2020, 2022, 2023), months = 6:7, crs = "EPSG:32609")`;
      check all four years came back (a dropped year only warns); write per-year medians to `s2.csv`
      to check for haze before trusting the pooled stretch (review 1 A2)

## Phase 2: data-raw script — panel artifacts

- [x] Choose the zoom window by eye from the fetched captures and composites (cut blocks visible in both
      eras); record it as a bbox literal and in `meta.csv` (no gpkg: it stores a timestamp, review 1 G2);
      assert each capture is drawn over the whole window in its release (review 1 G1)
- [x] S2: pooled `rgb_domain()` over the four years → `rgb_stretch()` → 8-bit; write one small GeoTIFF per
      year
- [x] Wayback: per capture, the window at 0.5 m; one overview of the newest capture at 5 m (review 1 S1);
      JPEG-compressed 8-bit GeoTIFFs, `time` stripped and `varnames` set so reruns don't churn
- [x] Record committed size (target ≤ 5 MB total for `vignettes/articles/wayback-change/`); rerun the
      script from a warm cache and confirm `git status` shows no binary churn

## Phase 3: article

- [x] `vignettes/articles/wayback-change.Rmd`, `bookdown::html_document2`, setup like
      `temporal-composition.Rmd`; API calls shown as `eval = FALSE` chunks; evaluated chunks only read
      the artifacts and plot (`terra::plotRGB`, no title, scale bar, capture date as label)
- [x] Sections per #108, headings as the reader's questions and "capture" defined before the lead figure
      uses it (review 1 C1): what changed (lead figure: three captures over the window) → a release is not a
      capture (own section, this box's counts) → which captures image this area (captures table) →
      picking a capture per year (picks table; 2018/2022/2023 have none of their own) → fetching on one
      grid (overview of one capture with the window outlined) → the years Wayback doesn't have (four S2
      panels, window outlined) → limits (one sentence each)
- [x] Every date, count and share in the prose computed from `captures.csv` / `picks.csv` inline
- [x] No footnotes and no `\@ref()` (pkgdown drops both); S2 composites date a change as between July of
      Y-1 and July of Y, and the prose says so (review 1 A3)

## Phase 4: verify

- [x] `pkgdown::build_article("articles/wayback-change")` renders; read every figure at delivered width
      against `writing.md` (one-sentence, look-alike) and `cartography.md` "Does it communicate?"
- [x] Render with network off (or confirm no evaluated chunk calls a `dft_` fetch) — what CI will do
- [x] `pkgdown::check_pkgdown()`; `grep -c footnote-ref` = 0 in the built HTML
- [x] Body-prose word count recorded for the PR (`data-raw/README.md` documents only the quotes, so the
      script's header is its documentation; review 1 G5)

## Validation

- [x] Tests pass
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

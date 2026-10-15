# Findings — Article: watching forest change with Esri Wayback and Sentinel-2 composites (#108)

## Issue context

## Problem

drift has two dated-imagery read paths, and no article shows either one being used to look at change:

- `dft_wayback_*` (#101) fetches sub-metre Esri Wayback captures. It appears only on its reference pages.
- `dft_stac_composite()` (#79) builds yearly Sentinel-2 true-colour composites. It also appears only on its reference page. `dft_stac_cube()` is in `trajectory-break-detection`, but only as input to break detection.

A reader who wants to see what happened on the ground between two years has no worked example.

## The area

The ~3 x 3 km box from the new_graphiti post [Sentinel-2 Ortho Mosaics with STAC and gdalcubes](https://github.com/NewGraphEnvironment/new_graphiti/tree/main/posts/2026-01-08-stac-ortho-mosaics) (lon -126.1755 to -126.1262, lat 54.3616 to 54.3891). From manual review, the main forest-cover changes there fall in **2018, 2020, 2022 and 2023**.

## What Wayback holds here (measured 2026-10-15)

`dft_wayback_captures()` over the box, zoom 16:19, all 182 releases from 2015 on (16 min):

| capture | sensor | res | share of box | first release serving it |
|---|---|---|---|---|
| 2014-06-01 | WorldView-2 | 0.50 m | 100% | 2017-06-27 |
| 2016-09-11 | WorldView-3 | 0.31 m | 82% | 2020-04-29 |
| 2020-09-18 | GeoEye-1 | 0.46 m | 100% | 2022-05-18 (still current) |

There is also a 2009 SPOT 5 base at 2.5 m. **No capture images the box in 2018, 2022 or 2023, and none after 2020.** So Wayback shows the change up to 2020 at sub-metre resolution, and only Sentinel-2 can date the 2022 and 2023 change.

## Proposal

A pkgdown article, `vignettes/articles/wayback-change.Rmd`, which `.Rbuildignore` already keeps out of the tarball.

- `data-raw/wayback_change.R` runs the network calls and writes the small panel images (and the captures/pick tables as CSV) that the article reads when it renders. This is the same pattern as `temporal-composition`. The calls appear in the article as code that isn't run (`eval = FALSE`).
- Sub-metre chips for the whole box are hundreds of MB, so they are not committed. Only the rendered panels are.

### Sections (reader's questions in order, limits last, per soul `writing.md`)

1. **What changed here between 2014 and 2020.** One paragraph and the lead figure: the three Wayback captures side by side over the zoom window.
2. **A release is not a capture.** The term gets its own section before first use: the rule, why it matters, and this box's numbers (182 releases, three captures).
3. **Which captures image this area.** `dft_wayback_releases()` and `dft_wayback_captures()`, with the table above.
4. **Picking a capture for each year.** `dft_wayback_pick()` at each key year. `days_from_date` shows that 2018 has no capture of its own (the nearest is 2016-09-11, 658 days before mid-2018), and neither do 2022 or 2023.
5. **Fetching them on one grid.** `dft_wayback_fetch()` at each pick's zoom, with one shared `crs` and `res` so the panels line up. An overview of the whole box, then a ~1 km zoom window on the cut blocks.
6. **The years Wayback doesn't have.** `dft_stac_composite()` for **2018, 2020, 2022, 2023**, as four panels over the whole box at 10 m.
7. **Limits**, one sentence each: captures here are years apart and the newest is 2020; a box fetch can mosaic several captures (2016 covers 82%); the June and September captures differ in leaf-out and shadow; the sensors are not co-registered.

### Decided

- pkgdown article, not a shipped vignette.
- Sentinel-2 panels for the four key years only.
- Wayback shown as an overview plus a zoomed window.
- Static panels only: no GIF, no interactive map (sub-metre chips make the page heavy), and no change-area numbers.

### Defaults (picked, not asked)

- Sentinel-2 window: `months = 6:7`, matching the post.
- Wayback `res = 0.5` m in the box's UTM zone (EPSG:32609), the coarsest capture's native resolution. The zoom window is chosen by eye from the panels and recorded as a bbox literal in the data-raw script.
- The box is a bbox literal in the data-raw script. No new gpkg in `inst/extdata`.

## Acceptance

- [ ] `data-raw/wayback_change.R` regenerates every artifact the article reads, from a clean cache.
- [ ] The article renders under `pkgdown::build_article()` with no network access.
- [ ] Every figure passes `writing.md`'s one-sentence and look-alike tests, and `cartography.md`'s "Does it communicate?" checks at page width.
- [ ] Every date, count and share quoted in the prose is read from the committed CSVs, not typed.
- [ ] The article appears on the built site (`_pkgdown.yml` has no `articles:` index today, so pkgdown lists it automatically), and `pkgdown::check_pkgdown()` passes.
- [ ] Body prose word count recorded in the PR.



## Sentinel-2 check on the post's composites (2026-10-15)

A crude year-over-year test on the new_graphiti post's own Sentinel-2 composites (share of cells whose red rises > 300 DN)
cannot place the forest change: after removing the 2022-01-25 +1000 DN offset by hand, 2019, 2023 and 2025 brighten across
the whole scene (median red 576 in 2019 vs ~290 either side), which is haze or compositing, not cut blocks.
`dft_stac_composite()` corrects that offset itself.

## Errors Encountered

| Error | Resolution |
|-------|------------|

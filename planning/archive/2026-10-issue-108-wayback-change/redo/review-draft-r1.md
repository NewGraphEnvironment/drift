# Review: draft commits on #108 (git diff 28cea67 HEAD), round 1

Reviewer checked the diff against the checklist, rendered the article in a copy of the repo
(scratchpad, `bookdown::html_document2`, exit 0, 17 s), read the knitted markdown and the
rendered PNGs, and checked the committed CSVs with sf.

## Findings

- **[severity: bug — unsupported claim]** vignettes/articles/floodplain-change-dating.Rmd:266 —
  "Most of the mapped change is not change on the ground." The article's own verdicts don't
  support it. By count, 4 of the 10 areas are `Class error` (A, B, D, E), and 5 are `Change` or
  `Likely change` (C, F, H, I, J). By area, the class errors hold 21.80 ha, against 25.82 ha for
  Change plus Likely change (5.79 + 20.03) and 1.81 ha Unclear. Taking the 68.31 ha "Changed
  once, and stayed" in summary.csv as the denominator, the class errors are 32% of it. The
  claim holds only for the five areas that have before and after Wayback images: 4 of 5 by
  count, 21.8 of 27.6 ha. This is the paragraph's lead sentence, sitting under the overview
  figure, so a reader takes it as the article's headline result. Fix: restrict it to the areas
  the sharp images can judge (for example "Of the five areas the sharp images can judge, four
  are not change on the ground"), or drop "most".

- **[severity: fragile — caption incomplete]** vignettes/articles/floodplain-change-dating.Rmd:421 —
  the table caption defines the `On the ground` column as "a change or a class error where
  Wayback has sharp images from before and after, and a likely change where only Sentinel-2
  does". G is one of the Sentinel-2-only areas, and its verdict is `Unclear`, which the caption
  never names. As written, the caption says every Sentinel-2-only area is a likely change, and
  the table's row for G contradicts it.

- **[severity: fragile — reproducibility statement]** data-raw/floodplain_change_dating.R:8-13 —
  the header now lists the watershed group and the topographic tiles as read live, but the
  next sentence still says "A warm rerun must leave the committed files unchanged unless the
  published item or the cutblock layer changed". maptiles caches only in `tempdir()`, so every
  run downloads the Esri World Topographic tiles again, and an Esri basemap update rewrites
  `topo_bulk.tif`. The same goes for an FWA edit and `context.csv` (bulk, bulk_bc). The
  exception list should name both sources, or the churn will read as an unexplained change.

## Checked and fine

- `results = "asis"` rows under the fold hook: the knitted markdown has the folded code, then
  for each area its `**X** · year · from to to · verdict · [Google Maps](...)` line followed by
  that row's image. That holds for 5 images in fig-seen and 5 in fig-s2only (13 PNGs in all, as
  expected). Each row is one 1 x N panel image (fig-seen-1 checked by eye), and nothing is
  dropped or out of order. The rendered HTML has 10 `target="_blank"` links, with `&` escaped
  correctly.
- Google Maps URL: `center=lat,lon` (ll[,2], ll[,1]) is the documented Maps URLs order, and the
  latitudes come out at about 54.36-54.39 and the longitudes at about -126.14 to -126.17.
  Every `lab_x`/`lab_y` point falls inside its own area polygon (st_intersects TRUE for all 10).
- Mercator scale bar: in terra 1.9.50, `sbar(type = "bar", divs = 2)` labels the bar
  `d / scaleby` = (20000/k)/(1000/k) = 20. The bar length 20000/cos(lat) in map units is 20 km
  true at the box's latitude. On the rendered map, Houston to Smithers measures about 56 km,
  which is plausible.
- Dimming: `erase(frame_v, bulk_v)` whitens only the ground outside the group, as it renders.
  The box lies within the group (st_within TRUE).
- "the 2020 capture covers the whole box": `sharp` keeps only releases at a capture's maximum
  cover, so the picked release for 2020-09-18 is one with cover 1. The `cover_max >= 0.999`
  stop before `wb_box` is written is therefore equivalent to a check on the release that was
  fetched, and the rendered overview has no gaps.
- `bc` vs `bc_outline`: there's no clash. `simple`, `context`, `ov`, `topo`, `bulk` and
  `around` are not reused in a way that breaks a later block. The `ov` in the cutblock loop
  runs earlier and is overwritten after it.
- Verdict sentence: the counts and the lists computed from `by_ground()` match `s2_only` and
  `seen` (5 + 5), and the key guard ties the verdicts to the areas.
- Note, not a defect: the simplified `floodplain` WKT in context.csv is invalid geometry
  (st_simplify without preserveTopology). It is used only as a display fill and renders cleanly.

/Users/airvine/Projects/repo/drift/planning/archive/2026-10-issue-108-wayback-change/redo/review-draft-r1.md

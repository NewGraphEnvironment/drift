# Code-check, article redo round 1 (#108)

Scope: `git diff 448874591b80703e81840d455879968c7fc7b5b9...HEAD`, the files named in the brief.
Measured against the committed outputs in `vignettes/articles/floodplain-change-dating/` with
terra/sf, the rendered page and its three figures, each `wb_*.tif` rendered at full resolution with
its area outlined, the Wayback metadata recomputed from the warm cache, and two small live BC WFS
reads (FWA streams in the box).

## Findings

- **[claim]** `vignettes/articles/floodplain-change-dating.Rmd:80` (G's verdict "Forest in 2020; ..."),
  `:264` ("it shows each of them as forest") and `:271` ("as forest does when it opens"). **G was not
  forest in the 2020 image.** At full size, `wb_G_2020-09-18.tif` with G's outline shows an open,
  smooth strip (a wet meadow or sedge strip with a red-brown channel down it and a few shrubs at its
  east end), with conifer forest on both sides. Measured on the chip's grey mean: inside G 77.3 against
  70.6 in a 60 m ring around it, and texture (focal 9x9 sd) 3.7 against 4.0. G is the only one of
  F-J that is brighter than its ring: F 72.0 against 77.3, H 73.5 against 79.1, I 71.6 against 79.6,
  J 75.7 against 81.7. F, H, I and J do look like forest. The map's Trees label for G is a 10 m map
  calling a ~60 m-wide open strip inside forest Trees. So the verdict, the "each of them" sentence and
  the "forest opens" reading are wrong for G, and G is a second instance of the article's own point
  that the map labels unchanged ground (this time on the from side). `planning/active/findings.md`
  ("F-J (2021-2023) are forest in the 2020 image") repeats the same mistake.

- **[claim]** `floodplain-change-dating.Rmd:220` ("A cloud-free Sentinel-2 image of every summer") and
  `:228-229` ("The panels share one display stretch, so a panel that looks brighter is brighter on the
  ground"). The 2019 composite is not cloud-free, and in it a brighter panel is not brighter ground.
  Box means of the 8-bit composites: 2017 76.7, 2018 78.0, **2019 140.5**, 2020 62.9, 2021 72.9,
  2022 68.8, 2023 98.7. Rendered, 2019 carries blocky cyan haze patches over most of the west and
  centre of the box, while the field in the north-east looks like the other years. So "pale across the
  whole box" (`:315`) also overstates it: the haze is patchy. The article contradicts itself: Limits
  says haze makes 2019 pale, and the tools section says brightness is ground. It matters on the page
  because three of the five "seen" rows (C, D, E) show 2019 as one of their Sentinel-2 panels, and C's
  "brightens more than the box" is measured on that year (C +128.7 against the box's +62.5). The shared
  stretch makes years comparable as composites, not as ground.

- **[claim]** `floodplain-change-dating.Rmd:207` ("Grey is the land-cover map flickering between
  classes, and this article sets it aside") with the lead figure (`:187-203`). Grey is only
  `unsettled` (code 1 in change.tif: 5,269 cells, 52.7 ha). The 63.6 ha that flickered and came back
  (`stable_flicker`, code 2: 6,360 cells) is drawn uncoloured, the same as the 209.0 ha of stable
  ground, and neither the legend nor the caption says what uncoloured floodplain means. A reader takes
  grey to be all of the flicker, which is the pooling CLAUDE.md warns against. The numbers table
  caption names both, but the map and its prose do not. That is cartography check 8: uncoloured
  floodplain is the largest class on the map, and it is not in the legend.

- **[claim]** `floodplain-change-dating.Rmd:253` ("A, D and E are the same open field in both images")
  against `:307-308` ("as it moved three fields here from Crops to Rangeland"), and E's verdict at
  `:74`/`:82` ("The same open field before and after"). The two sentences disagree on whether there is
  one field or three. The areas are contiguous: `st_distance()` A-D 0 m, A-E 0 m, D-E 10 m. They are
  three patches, from 2018 and 2020, of one meadow. Separately, at full size the north and west half of
  E (`wb_E_2016-09-11.tif`, `wb_E_2020-09-18.tif`) is farmyard: buildings, garden plots, a road and
  scattered trees south of the railway, not open field. "Unchanged" still holds for E, but "open field"
  is not what it shows.

- **[claim]** `floodplain-change-dating.Rmd:168-169` ("one 3.3 x 3.2 km box of the Bulkley River
  floodplain"). The item is the Bulkley watershed group's floodplain of all streams (`all_ff04`), and
  the change areas lie on its tributaries. FWA streams in the box (live WFS read): Maxan Creek
  6.1 km, Crow Creek 3.2 km, Bulkley River 1.9 km, Wiggins Creek 0.9 km. C, F, I and J intersect
  Maxan Creek; B and G intersect unnamed order 1-2 tributaries; D and E are nearest Crow Creek (171 m
  and 85 m); the nearest Bulkley River line to any area is 89 m (E), and 242 m for A. This is a
  claim written from the item's name. "the Bulkley watershed group's floodplain, where Maxan and Crow
  creeks meet the Bulkley River" would match what is drawn. The script header (`data-raw/...R:4`)
  already says "the Bulkley watershed group's floodplain".

- **[fragile]** `floodplain-change-dating.Rmd:272-273`, `:106-107`. "Part of I lies in a cutblock ...
  harvested from `r areas$cutblock_year[areas$id == "I"]`" rests on the cutblock layer, which the
  script reads live (`data-raw/...R:274`). The `seen_by_eye` key guard covers id, year and classes but
  not the cutblock columns, and the `stopifnot` asserts that the others are under 10% but not that I is
  at least 10%. A rerun after the layer changes could print "harvested from NA", or keep the sentence
  while the numbers table drops I's cutblock cell (it is shown only at >= 0.1), and nothing would stop
  the build. Add `areas$cutblock_share[areas$id == "I"] >= 0.1` to the `stopifnot`.

- **[claim, comment only]** `data-raw/floodplain_change_dating.R:4-5` ("taken as a rectangle in UTM
  zone 9 so every raster is a full rectangle on one grid"). The rasters are not on one grid.
  `change.tif` is 318 x 333 cells, xmin 683390.08, ymax 6030614.40 (the published land-cover grid).
  Every `s2_*.tif` is 319 x 333, xmin 683390.5, ymax 6030621 (the composite's own grid). They are
  offset 0.4 m in x and 6.6 m in y, and have one more row. That is invisible in the figures, and
  `extract()` by polygon does not depend on it, but the comment states it as the reason for the design.

## Checked and found correct (no action)

- Summary hectares match `change.tif` exactly (0: 209.02, 1: 52.69, 2: 63.60, years: 68.31; the
  per-year rows sum to 68.31). Category codes 0-4 match `break_category_code()`. 2018 and 2023 are
  exactly the endpoint breaks.
- Box 3.33 x 3.18 km. The lead caption's 2023 background, dimming, blue edge (gq `#1f78b4`) and
  500 m bar are as drawn.
- Wayback, from the warm cache: 197 releases, the newest 2026-09-24. All 54 releases from 2022-05-18
  draw 2020-09-18 at cover 1 (zoom 17 and 18), so "every release from 2022-05-18 to 2026-09-24, the
  latest" holds. The latest release has no capture at zoom 19-21 over the box, so "nothing sharper"
  holds there. 2016-09-11 peaks at 0.811 cover. In every release serving 2016-09-11, 2014-06-01 is
  drawn on the rest: 2014 covers 0.57 in the late releases, where 2016 covers 0.43. That agrees with
  `research/esri-wayback.md`.
- Brightening: every `stopifnot` claim holds (A +64.1 against the box's +1.3; F +85.5 against +10;
  G +47.2 against -4; H +76.2 against -4; I +109.7 against +29.8; J +101.6 against +29.8).
- C at full size: dense conifer forest in 2016, cleared with new tracks by 2020. It intersects Maxan
  Creek, so "creekside" is fair. D 2016 is visibly mown in swaths, and grassed in 2020. B is the same
  treed strip in both (a 2016 cloud touches only its north-east corner). H, I, J and F are forest in 2020.
- No footnotes and no `\@ref` in the rendered HTML. Evaluated chunks read only committed files.

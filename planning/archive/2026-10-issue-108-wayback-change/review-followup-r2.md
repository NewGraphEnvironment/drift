## Findings

- **[severity: claim]** vignettes/articles/wayback-change.Rmd:364-365 — "In the box the layer has 71.3 ha of tree loss, all of it on the floodplain." Not true against the floodplain the article draws. Method: downloaded bulk_co_ff04/transition_vector.gpkg and floodplain.gpkg (layer co_ff04), used the same filter as the script (Trees -> not Trees, intersecting the box), clipped to the box, and took st_difference with the co_ff04 union. Result: 2.47 of 71.27 ha (3.5%) lies outside the polygon. It is spread over 14 of the 21 patches as a ring of edge cells: 7028 0.54 ha, 7017 0.43, 6964 0.32, 7029 0.29, 7003 0.25, 6759 0.24, 6493 0.23, and so on. For all change in the box it is 2.97 of 107.1 ha. These are 10 m cells that straddle the polygon edge. The number in the sentence is right; the quantifier "all of it" is not. Either drop "all of it on the floodplain", or say it is the floodplain's 10 m cells, a few of which lie partly outside the drawn edge. Line 329 ("The layer covers only the floodplain") and the limits bullet at line 393 are fine as approximations, but "all of it" is a checkable claim, and it fails.

- **[severity: claim]** vignettes/articles/wayback-change.Rmd:327-329, 366-367, 394-395 — `in_harvest` is described as "touches a cutblock" (and the patches as tagged with "the provincial fire and harvest it touches"). In floodplains, `fp_disturbance_tag()` windows each source to the change interval (config/disturbance.yml: harvest = consolidated cutblocks, `harvest_start_year_calendar` within 2017-2023; fire likewise). So `in_harvest` means the patch touches a cutblock whose harvest started 2017-2023, not any cutblock. Two consequences:
  1. A reader who checks a patch tagged FALSE (e.g. 7029, 5.7 ha) against the full cutblock layer can find it touching an older block.
  2. "only 13.9 ha of the tree loss lies inside one" is correct only because `cutblock_ha` is measured against the same 2017-2023 set (data-raw/wayback_change.R:274, 320). The sentence reads "inside one" as inside any cutblock.

  Add "whose harvest started 2017–2023" once, in the paragraph at 327-329 or in the limits bullet.

- **[severity: fragile]** vignettes/articles/wayback-change.Rmd:63-67, 295-297 (fig-s2, cartography) — the cutblock year labels are white bold text at cex 0.7 with no halo, drawn on top of the white halo of the outlines. The window rectangle is drawn after them. In the rendered 2018 panel:
  - The rectangle's right edge runs through the "2023" label of block 80362 (label at x = 684790, rectangle edge at 684850).
  - "2020" for 23043 and both "2020" labels for 23046/23047 sit on their own white-haloed outlines and are hard to read.
  - "2019" for 510624 is pushed inward by the clamp, so it sits on the open ground west of its block rather than on the block.

  These labels are the only key to which outline is which year, and the prose (lines 279, 305-313) relies on them. Possible fixes: give the labels a halo (`halo = TRUE, hc = "black"`, or a dark text colour with a white halo, as `draw_treeloss()` does), draw the rectangle before the labels, and move the 80362 label or nudge it off the rectangle edge.

- **[severity: fragile]** data-raw/wayback_change.R:274-276, 294-299 — `sf::st_intersection(sfc, sfc)` drops non-intersecting pairs. The script then builds `cutblocks` by binding `cb$...` (length nrow(cb)) to `cb_in`-derived columns (`area_ha`, `fp_ha`, `lab`) by position. The WFS query intersects with the box reprojected to BC Albers as a 4-vertex polygon, while the clip is in UTM. A block that touches the box edge within that reprojection error, or touches it only along a line or at a point, is returned by the WFS but gives either no row in `cb_in` or a zero-area LINESTRING/POINT.
  - With a missing row, the misaligned lengths usually make `data.frame()` error. At an exact multiple (2 vs 1) it recycles silently, and every block after the gap gets another block's area and label.
  - A zero-area touch gives `cb_edge` a POINT or empty geometry. `st_collection_extract("LINESTRING")` then yields an empty WKT, which `vect()` in the article may refuse.

  Not hit by the current 9 rows, all of which have area > 0. A guard would drop blocks with zero area in the box before computing `cb_in`, `cb_edge` and labels. Simplest: filter `cb` by `as.numeric(st_area(st_intersection(...))) > 0` per row, or use `st_intersection(cb, aoi)` on the sf, which carries attributes.

Checked and found correct:
- Every number in the changed prose matches the committed CSVs and the render: 9 blocks, 52.9 ha, 14.2 ha in floodplain, 8 from satellite, 2023 blocks 26.8 ha, 71.3 / 55.6 / 13.9 ha, largest patch 6964.
- "pale only in the 2023 composite" for patch 6964 holds. Mean RGB over the patch against the box mean, from the committed s2 rasters: 2018 68.7/108.6/58.7 vs 68.8/113.5/56.5; 2020 40.3/84.8/26.4 vs 55.9/101.8/36.6; 2022 47.3/89.4/34.5 vs 62.4/105.4/43.9; 2023 159.9/164.5/104.2 vs 99.6/126.3/73.9.
- "most of it is outside the 2023 cutblocks it touches" holds: 7.1 of 25.15 ha lies inside any 2017-2023 block.
- Window directions and cutblock placement match fig-window and fig-s2:
  - 23045 lies between the arms, with fp_ha 0.
  - 23043 sits in the south-west of the window, mostly on the floodplain.
  - 80122 is the largest and runs east, with fp_ha 0.14.
  - 80362 and 80367 are on the valley floor.
  - 80884 is in the north-west.
- The description of the floodplains pipeline matches 03_lulc_classify.R and fp_disturbance.R: `patch_area_min = 10000`, a class-agnostic 1 ha sieve, `st_intersects` for `in_*`, and the dominant overlap (largest intersection area) for the carried year.
- The article rendered from a copy into a temp dir with no network reads.

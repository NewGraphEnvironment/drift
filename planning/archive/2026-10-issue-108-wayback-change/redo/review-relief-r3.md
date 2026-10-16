# Review: relief basemap and fig-box removal, round 3

Diff: `git diff f28feea HEAD` (58ed8ca, fd658f5, f7cb977, f115867), excluding planning/. f115867
changes only the script header, so the figure code is the code r2 rendered; it was not re-rendered.
Live probes were read-only: one bcdata query of the full-resolution BULK watershed group.

## Enumeration

| # | Where | Claim | Verdict | Evidence |
|---|---|---|---|---|
| 1 | script:8-12 | everything else is cached; the STAC item, rasters, release list, cutblocks, watershed group, river, town names, basemap tiles and their attribution are read live; bcmaps caches the BC outline | holds | r2 walked every network call; f115867 now names the river itself |
| 2 | script:13-16 | a warm rerun leaves the committed files unchanged unless a named live source changed | holds | river sorted by LINEAR_FEATURE_ID, towns by name (r1/r2 measured byte-identical WKT on shuffle); credit built from a fixed two-element vector |
| 3 | script:40-41 | relief_bulk.tif is the light grey base shaded with World Hillshade, zoom 10, Web Mercator, 8-bit | holds | `terra::rast()`: EPSG:3857, 152.874 m cells (zoom 10 at 256 px), 3 bands INT1U, 150-255 |
| 4 | script:40 | "over the Bulkley watershed group" | holds | extent is the group's bbox + 4 km, which covers the group |
| 5 | script:42-44 | context.csv holds the group, its floodplain, the Bulkley River, "its municipalities (named)", the box, BC | **fails for "its municipalities"** | see finding 1: Granisle and Hazelton are outside the group |
| 6 | script:45 | relief_credit.txt is the attribution "as each Esri service gives it" | holds | r2 matched live `copyrightText`; only the Hillshade "Sources: " prefix is stripped |
| 7 | script:81-82 | the group over the grey base shaded with World Hillshade, "with its river and towns drawn on top" | river holds; **"its towns" fails** | river query filters `WATERSHED_GROUP_CODE == "BULK"`; towns: finding 1 |
| 8 | script:89-91 | maptiles `Esri.WorldGrayCanvas` is the Light Gray Base the credit is read from | holds | r1: the provider URL is `Canvas/World_Light_Gray_Base` |
| 9 | script:100 | bcdata cannot translate a call inside `filter()` | holds | r2: `INTERSECTS(st_transform(...))` errors "No known SQL translation" |
| 10 | script:101 | the four FEATURE_TYPEs are the municipal types | holds | r2: province-wide census, 161 rows; the 3 types left out are not in the frame |
| 11 | script:393 | the WFS returns segments in no fixed order, and a union keeps input order | holds | r1 measured both |
| 12 | Rmd:220 caption | blue is the group's floodplain | holds | `fp_col` fill at 0.75 |
| 13 | Rmd:220 caption | "the darker line the Bulkley River" | holds as "the darker blue line" | river #1F4E79 over the lighter floodplain blue, labelled by name on the map. The grey20 group boundary is darker still (CIE L* 21 vs 33), but it is not blue and has its own legend entry. Accepted in r1/r2 |
| 14 | Rmd:220 caption | ground outside the group is dimmed; the inset shows the group in the province; scale bar 20 km at the box's latitude | holds | unchanged code; r1/r2 read the render |
| 15 | Rmd:220 caption | "Basemap: <relief_credit>" | holds | caption reads the committed file |
| 16 | Rmd:224 | "outside the watershed group is dimmed" | holds | `erase(frame_v, bulk_v)` at white 0.5 |
| 17 | Rmd:235-236 | the river is labelled on its reach between Smithers and New Hazelton, clear of the study area | holds | r2 read the render: the label sits by Moricetown, about 120 km from the box |
| 18 | Rmd:254 legend | group, floodplain, study area | holds | river and towns are labelled directly on the map |
| 19 | Removed figure | nothing still describes fig-box or the topographic basemap | holds | `git grep` for wb_box, fig-box, topo_, topograph, WorldTopo, "figure above/below", "gold outline" outside planning/: no hits in this article or script |
| 20 | Removed figure | prose that relied on fig-box still reads | **fails** | see finding 2 |

## Findings

- **[severity: fragile, claim]** data-raw/floodplain_change_dating.R:44 ("its municipalities (named)")
  and :82 ("with its river and towns drawn on top"). The towns come from
  `INTERSECTS(around_3005)`, which is the group's bbox buffered by 4 km, not the group. Measured
  against the full-resolution BULK polygon (live bcdata):
  - **Granisle is 26.3 km outside the group**, on Babine Lake.
  - **Hazelton is 0.31 km outside it**, at the Skeena.
  - Houston, New Hazelton, Smithers and Telkwa are inside.

  So 2 of the 6 are not the group's municipalities. The figure is right: it draws all six, two of
  them in the dimmed exterior, and the caption makes no claim about towns. Only the two comments are
  wrong. Fix: "the municipalities in the map frame".

- **[severity: fragile, prose]** vignettes/articles/floodplain-change-dating.Rmd:266-273. The summary
  paragraph after fig-context counts "`length(seen)` of the `nrow(areas)` areas" and names them by
  letter (C a change; A, D, E class errors; F, H, I, J likely change; G unclear). It used to follow
  fig-box, whose caption defined the term ("the N areas of 1 ha or more where neighbouring cells
  switched in the same year and stayed") and whose map put the letters on the ground.

  With fig-box gone, nothing before this paragraph defines an "area" or shows where any letter lies.
  The only figure ahead of it is the context map, which shows neither. The first definition and the
  first lettered map are now fig-lead, at line 294 ("Letters name the change areas of 1 ha or more").
  Even there, the "switched in the same year and stayed" half of the definition survives only as the
  cell-level wording.

  This breaks the convention's "define a term in its own place, before it is used". A reader meets
  ten undefined letters in the article's summary. Fix: move the definition into the summary
  paragraph, or say there that fig-lead (below) names the areas.

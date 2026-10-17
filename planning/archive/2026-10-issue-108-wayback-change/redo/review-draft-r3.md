# Review: draft commits on #108 (git diff 28cea67 HEAD), round 3

Method: I copied the repo to the scratchpad and rendered the article there
(`bookdown::html_document2`, keep_md, exit 0, 2026-10-16 20:42:47-20:43:01 UTC). I read
the knitted md and the HTML, and looked at fig-context, fig-box and fig-seen-4 by eye. I
checked context.csv, topo_bulk.tif, wb_box_2020-09-18.tif, captures.csv and areas.csv with
sf and terra. I recounted change patches from change.tif, and read the installed
`bcmaps::bc_bound()` and `maptiles::get_tiles()` to see how they cache.

## Mechanism

Each earlier finding is a sentence that describes a set (the 10 areas, the imagery that
shows an area, the layers drawn in a figure, the live sources a script reads) the way the
author pictured it while writing. Nobody enumerated the set's members against the
sentence. So the claim's scope is the subset the author had in mind:

- "most" was true of the five judged areas, not the ten.
- "only Sentinel-2" was true of the view after the change, not of every image of those areas.
- "current" is a property Google never states.
- A caption named some of the drawn layers and missed the dimming.
- A header listed some of the live reads.

The fixes follow the same pattern. Each one landed on the sentence the reviewer quoted, not
on every place the same claim lives. The "now" claim survives in a code comment that the
article publishes, and fig-box got the dimming sentence while fig-context, its new sibling
figure, did not.

## Enumeration

Every claim the diff adds or changes, one row each.

| # | Where | Claim | Verdict | Evidence |
|---|---|---|---|---|
| 1 | Rmd:72 comment | ground outside the floodplain is dimmed, so the floodplain reads as the subject | holds | fig-box and fig-lead render the dimming |
| 2 | Rmd:93-94 `ground` | A, B, D, E Class error; C Change; F, H, I, J Likely change; G Unclear | holds, except D (Finding 4) | `shows` column; fig-seen and fig-s2only rows |
| 3 | Rmd:103-104 comment | "Google does not say when its image was taken, so it is a look at the ground now" | **fails** | "now" is the r2 #2 claim. It is published in the read-saved code fold (HTML line 374). Finding 1 |
| 4 | Rmd:105-108 URL | `center=lat,lon` at a point inside each area | holds | lat 54.364-54.385, lon -126.141 to -126.170. Point-on-surface (r1) |
| 5 | Rmd:136-137 guards | verdict groups equal `seen` and `s2_only` | holds | they pass on the committed data |
| 6 | Rmd:185-186 comment | each row is headed by its Google Maps link | holds | md lines 427-494: a header line then that row's image, 5 + 5 |
| 7 | fig-context cap | "The box in the Bulkley River watershed group, northern British Columbia" | holds | box bbox inside the bulk bbox; inset |
| 8 | fig-context cap | "Blue is the watershed group's floodplain" | holds | item bulk_all_ff04 / all_ff04. It spans the group in the render |
| 9 | fig-context cap | "the inset shows the group in the province" | holds | bulk_bc drawn red on bc |
| 10 | fig-context cap | "The scale bar is 20 km at the box's latitude" | holds | cos(lat) correction (r1) |
| 11 | fig-context cap | "Basemap: " + credit | holds | topo_credit.txt |
| 12 | fig-context (caption as a whole) | describes what is drawn | **fails (omission)** | Ground outside the group is overlaid with white at alpha 0.5 (Rmd:227), clearly visible. The caption does not say so. This is r2 #3 on the sibling figure. Finding 2 |
| 13 | Rmd:225 comment | outside the watershed group is dimmed | holds | render |
| 14 | Rmd:230 comment | the box is a few pixels at this scale, so it is ringed | holds (loose) | 19.3 topo cells, about 28 px in the 1050 px render. The ringing rationale stands |
| 15 | Rmd:238 comment | Web Mercator stretches distance by 1/cos(lat) | holds | — |
| 16 | fig-context legend | group line, floodplain, study area | holds | Every prominent drawn feature is listed. The study-area square is a symbol, smaller than the box's footprint |
| 17 | fig-box cap | "The box, in the sharp Esri Wayback image of 2020-09-18" | holds | wb_box at 2 m, 0 NA cells; cover_max 1 in captures.csv |
| 18 | fig-box cap | "The blue line is the edge of the floodplain" | holds | render |
| 19 | fig-box cap | "the gold outlines are the 10 areas of 1 ha or more whose land cover switched once and stayed" | **fails (definition)** | The code takes same-year 8-connected patches, and there are 10. Taken as worded (no year condition), there are **9** patches of 1 ha or more (60.16 ha), because A touches D and E. Finding 3 |
| 20 | fig-box cap | "Ground outside the floodplain is dimmed." "The scale bar is 500 m." | holds | Rmd:258; `sbar(500)` in UTM |
| 21 | Rmd:268 inline | "Sharp images from before and after reach 5 of the 10 areas" | holds | `length(seen)` = 5 |
| 22 | Rmd:269 inline | "show only C as a change" | holds | `by_ground("Change")` = C |
| 23 | Rmd:270-271 | "A, B, D, E are class errors, where the land-cover map gave the same ground a different class" | B, A, E hold. **D is contestable** | Rmd:371 says the D ground went from mown in 2016 to grassed by 2020, "a change of use at most", and fig-seen-4 shows that. Finding 4 |
| 24 | Rmd:272-273 | "The 5 areas dated after 2020" | holds | s2_only years 2021, 2022, 2022, 2023, 2023. Unguarded (r2) |
| 25 | Rmd:273 | "have no sharp image after their change, only Sentinel-2" | holds | wb_after NA for F-J; newest capture 2020-09-18 |
| 26 | Rmd:274 | "F, H, I, J look like forest opening up" | holds | `shows`; Rmd:390 |
| 27 | Rmd:275 | "and G is unclear" | holds | `ground` |
| 28 | Rmd:359-362 | row contents; outline in its year's colour; the link opens Google's satellite image, "which Google does not date" | holds | `area_rows` panels; `draw_area` |
| 29 | Rmd:382-383 | the last sharp Wayback image (2020-09-18), then two Sentinel-2 panels | holds | guard `wb_before[s2_only] == newest` |
| 30 | `area_rows` header line | id · year · from to to · verdict | holds | md 427-494 |
| 31 | Table caption | "class errors first" | holds | rows A, B, D, E, then C, then F, H, I, J, then G |
| 32 | Table caption | change/class error where Wayback has before and after; likely change/unclear "where only Sentinel-2 does" | holds | guards 136-137 |
| 33 | data-raw:8-11 | "Every call goes to the network the first time and to drift's cache after it ... except [the live reads]" | **fails (minor)** | `bcmaps::bc_bound()` is in neither group: it caches under bcmaps' own cache (`~/Library/Caches/org.R-project.R/R/bcmaps`). Finding 5 |
| 34 | data-raw:12-14 | the committed files change only if the item, the cutblocks, the watershed group or Esri's topo map changed | holds | The Wayback release list is live, but it is filtered to release_date <= 2026-10-15, so new releases cannot churn captures.csv. maptiles' default cache is the session tempdir |
| 35 | data-raw:38 | wb_box: newest sub-metre capture over the whole box, 2 m, 8-bit | holds | res 2 m |
| 36 | data-raw:39-40 | topo_bulk: zoom 9, Web Mercator, 8-bit | holds | res 305.748 m = z9; EPSG:3857 |
| 37 | data-raw:41-42 | context.csv: simplified WKT with CRS, for the group, floodplain, box and BC | holds | 5 rows (bulk_bc is the group in 3005) |
| 38 | data-raw:43 | topo_credit.txt is the basemap attribution | holds | — |
| 39 | data-raw:79 comment | where the box lies: the Bulkley group over Esri's topo map | holds | — |
| 40 | data-raw:366-367 comment | overview is the newest sharp capture over the whole box, at 2 m, so it must cover the box | holds | stop on cover_max < 0.999; picks come from `sharp`, where cover >= best - 0.001 |
| 41 | data-raw:375 comment | outlines simplified for drawing at the watershed-group scale | holds | — |

Quantifiers checked against their whole sets:

- "only C" (row 22): holds.
- "only Sentinel-2" (row 25): holds.
- "the 5 areas dated after" (row 24): holds.
- "the 10 areas" (row 19): fails as worded.
- "Every call ... except" (row 33): misses bc_bound.
- "which Google does not date" (row 28): holds. The comment at row 3 contradicts it.

Earlier fixes:

- r1 lead sentence: holds.
- r1 table caption: holds.
- r1 header: holds, except bc_bound (row 33).
- r2 #1 (seen only in Sentinel-2): holds.
- r2 #2 ("current"): **incomplete** (row 3).
- r2 #3 (fig-box dimming): holds for fig-box, **not carried to fig-context** (row 12).

## Findings

- **[severity: fragile, unsupported claim, published]** vignettes/articles/floodplain-change-dating.Rmd:103-104.
  The comment reads "Google does not say when its image was taken, so it is a look at the
  ground now, not a date". This is the "current" claim from r2 #2. The r2 finding named this
  comment, but the fix changed only the prose at 361-362. The comment sits in the `data`
  chunk, which the `read-saved` chunk shows to readers (`ref.label = "data"`), so it is
  published (HTML line 374). Google's undated image may be older than the 2020-09-18 Wayback
  capture. Suggested wording: "...so it is an undated look at the ground, not a date."

- **[severity: fragile, caption omits what the figure shows]** vignettes/articles/floodplain-change-dating.Rmd:221 (draw at 227).
  fig-context lays white at alpha 0.5 over everything outside the watershed group, and the
  render shows it clearly. The caption does not say so. r2 #3 fixed the same omission on
  fig-box. Add "Ground outside the watershed group is dimmed."

- **[severity: fragile, count depends on an unstated definition]** vignettes/articles/floodplain-change-dating.Rmd:255.
  "the gold outlines are the 10 areas of 1 ha or more whose land cover switched once and
  stayed". The code takes 8-connected cells that switched **in the same year**
  (data-raw:160-161), and there are 10 of them. Read as worded, with no year condition, the
  clean-switch cells form **9** patches of 1 ha or more (60.16 ha; measured from change.tif):
  A (2018) touches D and E (2020) and merges with them. This is the first place the article
  says how its areas are formed, and the outlines do not show the years. Fix: "...whose land
  cover switched once, in the same year, and stayed".

- **[severity: fragile, verdict stated more firmly than the article's own reading]** vignettes/articles/floodplain-change-dating.Rmd:270-271 (verdict at 93).
  "A, B, D, E are class errors, where the land-cover map gave the same ground a different
  class." For D the article itself says otherwise (371). The whole of D was mown in 2016 and
  is grassed over by 2020, "a change of use at most", and fig-seen-4 shows that: windrowed
  hay on 2016-09-11, standing green grass on 2020-09-18, two September dates on either side
  of the 2020 switch. The IO LULC Crops class includes planted grasses, so a hay meadow left
  unmown is arguably what Crops to Rangeland describes. The images are consistent with a
  class error and with a real change of use, so "the same ground" does not follow from them
  for D. The Limits line "moves unchanged ground" (432) has the same problem, but it predates
  this diff. The call is the author's to make. The new sentence and the table now state it
  without the hedge the body text carries. Options: give D its own verdict (for example
  "Change of use"), or qualify the class-error definition for the meadow areas.

- **[severity: fragile, minor, comment]** data-raw/floodplain_change_dating.R:8-11.
  "Every call goes to the network the first time and to drift's cache after it ... except"
  the listed live reads. `bcmaps::bc_bound()` (added at 86) is in neither group: it downloads
  through bcdata once and then caches in bcmaps' own user cache, not drift's. This has no
  effect on the warm-rerun guarantee, but the list r1 asked to complete is still not
  complete. Name it ("BC's outline, cached by bcmaps").

/Users/airvine/Projects/repo/drift/planning/archive/2026-10-issue-108-wayback-change/redo/review-draft-r3.md

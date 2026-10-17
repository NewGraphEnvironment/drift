# Review round 3: #108 article redo (branch diff 4488745...HEAD, fixes 227a793 and 7f3a4bf)

Reviewer worked in a copy of `vignettes/articles/floodplain-change-dating/` in the scratchpad. The repo
was not modified apart from this file. There were no network calls, and the data-raw script was not run.
What was measured: the Sentinel-2 rise matrix for every area and year, recomputed from the committed
`s2_*.tif` with the article's own method; `freq()` of `change.tif`; the Wayback views at full 0.5 m
(`wb_C_*`, `wb_E_2016`, `wb_G_2020`, `wb_H_2020`), and an E crop for 2016 against 2020 with the A, D and E
outlines; the area of E inside the 2016 mown field; and the rendered HTML text and figures against the
source. The rendered page (09:54:12) matches the Rmd at 7f3a4bf, word for word in its prose.

## 1. Mechanism

The prior findings share one assumption. **A sentence is taken as true because it fits the
member the author had in mind, and its check is then picked to agree with it. Nobody walked the set
the sentence quantifies over.**

- Many of the claims were written from the representative member rather than the set. "Mown in 2016" was
  written from D, then extended to A when A was pointed out, and E was never looked at. The before date
  was taken from `seen[1]`. "Bulkley River" came from the item's name. "Forest" came from the thumbnails,
  and "trails" from a glance.
- The guard then tests a proxy that the sentence already satisfies, not the property. Examples are the
  sign of a rise and not its rank, a key on id/year/class but not on the `wb_*` columns each sentence
  reads, and "the shown code is what ran", checked only for the data-raw blocks.
- The fixes have repaired the instance named and not walked the set again. So the same shape turns up one
  member further on: E after A, and the figure chunks after the fetch blocks.

Two consequences carry into this round:
- The check that shown code is defined on the page was applied to the `## ----` blocks of the data-raw
  script. It was never applied to the figure chunks, which the fold hook also shows.
- Each verdict about the mown strip was written for the area someone flagged. The meadow's third patch, E,
  was never re-read.

## 2. Enumeration

Backing: **inline** = computed from the files at knit time; **guard** = pinned by `stopifnot`/key check;
**measured** = measured by me now (or by r2, where I cite it and did not repeat it); **unbacked** = nothing checks it.

| line | claim | backing | verdict |
|---|---|---|---|
| 175 | drift finds where land cover changed, and dates it | package scope | holds |
| 176-177 | one 3.3 × 3.2 km box | inline (`change` extent: 3330 × 3180 m) | holds |
| 177 | floodplain in the Bulkley River watershed group | item `bulk_all_ff04` (BULK) | holds |
| 177 | northern British Columbia | 54.37 N, -126.15; regional usage | holds (loosely) |
| 178 | most of the change lies along Maxan and Crow creeks | accepted (live FWA query) | accepted |
| 179-180 | looks at **each** change with two imagery tools | all 10 areas get S2 panels, and a Wayback panel each | holds |
| 181 | sharp images stop in 2020 | inline `newest` = 2020-09-18 | holds |
| 182 | later changes seen only in Sentinel-2 | F-J have no `wb_after` | holds |
| 186-188 | item id, processed 2026-10-14, drift 0.20.0, flooded 0.7.0 | inline item.csv | holds |
| 188-189 | Impact Observatory 10 m land cover, every year 2017-2023, clipped | item.csv `landcover = io-lulc`; script reads `classified_2017..2023` | holds |
| 189-191 | break_class finds the switch year; break_category says if it held | `R/dft_break_category.R` codes 0-4 | holds |
| 196 cap | cells by year they switched **and stayed** | codes 1/2 = `n_flips == 1` (`break_category_code`) | holds |
| 196 cap | over the 2023 Sentinel-2 image | inline `years[length(years)]`, `s2[[7]]` | holds |
| 196 cap | grey = changed, never settled on one class | code 1 = `unsettled` | holds |
| 196 cap | uncoloured = kept class or flickered back | codes 0 and 2 → NA in `yr_layer` | holds |
| 196 cap | ground outside floodplain dimmed | `ifel(is.na(change))` | holds |
| 196 cap | letters name the change areas of 1 ha or more | areas.csv = every ≥1 ha clean-switch patch | holds |
| 196 cap | blue line = floodplain edge; scale bar 500 m | gq `#1f78b4` (r1); `sbar(500)` | holds |
| 199 (shown comment) | ground outside the floodplain is dimmed | code below it | holds |
| 202-203 (shown comment) | change.tif: year less 2000, 1 never settled, 0/2 no lasting change, NA outside | measured `freq()`: 0, 1, 2, 18-23 | holds |
| 196-213 (shown code) | runs on its own | measured: uses `change`, 8-bit `s2`, `areas`, `yr_set`, `yr_col`, `grey_col`, `draw_fp`, `crs`, none defined in a shown block | **wrong** (finding 2) |
| 216-217 | grey = change that never settled; flicker-and-back set aside too | category codes | holds |
| 217 | coloured cells switched **once** and stayed | `n_flips == 1` | holds |
| 225-228 tbl | break tools: the year each cell switched, and whether it held | as above | holds |
| 229 tbl | composite: a Sentinel-2 image of every summer, at 10 m | `res = 10` default, `years = 2017:2023` | holds |
| 230 tbl | Wayback tools give sharp (under 1 m) images | captures.csv: 2009-01-15 SPOT 5 is 2.5 m, served by 47 releases over this box | **wrong** (finding 5) |
| 230 tbl | only from the days Esri's providers imaged the place | capture-date model | holds |
| 235 | composite reads from Microsoft's Planetary Computer | `sign_fn = rstac::sign_planetary_computer()` | holds |
| 236 | takes **the** June and July scenes | `months = 6:7`, but `cloud_cover_max = 20` drops scenes over 20% | **wrong (minor)** (finding 6) |
| 236 | masks cloud and snow | SCL mask default incl. snow | holds |
| 237 | keeps the median of each band | `aggregation = "median"` | holds |
| 237-238 | panels share one display stretch | script 327-337 pooled `dom` | holds |
| 239-240 | a composite can carry pale patches; 2019 is the palest of the seven | guard `which.max(box_mean) == "2019"`; measured 140.5 against 62.9-98.7 | holds |
| 245 | Wayback keeps **every** past version of World Imagery | archive begins at its first release (2014); the article reads 2015+ | unbacked (finding 7) |
| 245-246 | each release is a mosaic of captures from many days | captures.csv, research doc | holds |
| 247-248 | drift reads captures per release, then picks and fetches by capture | shown `wayback` block | holds |
| script 56 (shown) | the box's UTM rectangle, so rasters are full rectangles | code | holds |
| script 204-206 (shown) | pick prefers the later release among equally near captures; cover only breaks ties | `R/dft_wayback_pick.R` ranks days, then res_m, then release_date, then cover | holds (res_m sits between; immaterial here) |
| fetch blocks (shown) | run top to bottom on their own | checked: `aoi`, `crs`, `href`, `years`, `landcover`, `picks` are all defined in earlier shown blocks | holds |
| 255-257 | **5** areas dated 2018 to 2020 | inline `seen` | holds |
| 257 | sharp image from before the change (2016-09-11) | guard (all `wb_before[seen]` equal) | holds |
| 257 | and from **after** it (2020-09-18) | guard (`wb_after[seen] == newest`). For D and E (dated 2020) the capture is in the change year, and it falls after their "summer of the change" S2 panel | **wrong (minor)** (finding 8) |
| 259 cap | Wayback before/after, then S2 summer before and summer of change; outline in its year's colour | code | holds, but "after" (finding 8) |
| 260 (shown code) | runs on its own | uses `area_rows`, `wb_panel`, `s2_panel`, `seen`, which are hidden | **wrong** (finding 2) |
| 263 | **Only** C is a change on the ground | looked, all five at full size (r2, and C again now) | holds |
| 263-264 | forest along Maxan Creek opened up by 2020 | measured `wb_C_*` at full size; C ∩ Maxan accepted | holds |
| 264-265 | A, D and E are parts of one open meadow, moved Crops→Rangeland | areas.csv classes; A touches D and E (`relate`) | holds |
| 265-266 | mown in 2016 "across D and the western arm of A" | measured 2016/2020 crop: E's southern lobe also lies on the striped field, about 0.5-0.7 ha of its 3.9 ha | **wrong** (finding 1) |
| 266 | grassed over by 2020, a change of use at most | looked | holds |
| 266 | B is the same stand of trees in both | looked (2016 cloud on its NE corner, r2) | holds |
| 267-268 | in its year A brightens more than the box | guard `brightens[A]`; measured +62.8 | holds |
| 74 verdict A | part of one meadow; western arm crosses the 2016 mown strip | looked (r2, and crop now) | holds |
| 75 verdict B | the same stand of trees before and after | looked | holds |
| 76 verdict C | creekside forest opened up | looked | holds |
| 77 verdict D | part of the same meadow; mown 2016, grassed 2020 | looked | holds |
| 78 verdict E | part of the meadow, running into a farmyard; **the same before and after** | measured crop: south lobe striped/mown in 2016, uniform green in 2020 | **wrong** (finding 1) |
| 79 verdict F | forest in 2020, then brightens in 2021 | looked; rise 2021 +75.6 | holds |
| 80 verdict G | open wet meadow along a channel in 2020, brightens over 2021 and 2022 | looked full size; rises +31.8, +51.2 | holds |
| 81 verdict H | forest in 2020, then brightens in 2022 | looked full size; +80.2 | holds |
| 82-83 verdict I, J | forest in 2020, then opens to **bare ground** in 2023 | 10 m true colour shows tan/pink patches. That fits bare soil, slash, or dry or dead vegetation alike | unbacked (finding 10) |
| 272-273 | **5** areas dated 2021 to 2023 | inline `s2_only` | holds |
| 273-274 | their last sharp image is 2020-09-18 | inline `newest`, but the panels draw `wb_before`. No guard ties `wb_before[s2_only]` to `newest` | holds, unguarded (finding 3) |
| 274-275 | F, H, I and J as forest; G as open wet meadow along a channel | looked | holds |
| 277 cap | last sharp Wayback image (2020-09-18), then S2 before and summer of change | as 273 | holds, unguarded (finding 3) |
| 278 (shown code) | runs on its own | `area_rows`, `wb_panel`, `s2_panel`, `s2_only` are hidden | **wrong** (finding 2) |
| 281-282 | of the six years, **each** area brightens most in its mapped year | guard `rise_year[s2_only] == year`; measured F 2021, G 2022, H 2022, I 2023, J 2023 | holds |
| 283 | for F, H, I, J forest opens to grass or bare ground **in one summer** | measured: rise in the mapped year +75.6/+80.2/+79.9/+71.7, every other year ≤ +14.4. Unguarded | holds, unguarded (finding 4) |
| 283-284 | G brightens over **two** summers | measured +31.8 (2021), +51.2 (2022), other years ≤ -3.4. Unguarded | holds, unguarded (finding 4) |
| 284 | G already open in 2020 | looked full size | holds |
| 285 | label may be catching up | hedged | holds |
| 285-287 | part of I lies in a cutblock harvested from 2023 | guard (share ≥ 0.1, year not NA); 27%, 2023 | holds |
| 287-288 | **none** of the others lies mostly in one | guard (< 0.1); H 3%, rest 0 | holds |
| 288-289 | F, G, H, J cannot be told at 10 m | hedge | holds |
| 293 | Wayback shows only what was imaged and released | definition | holds |
| 294 | over this box it holds **3** sharp captures, 2014-06-01 / 2016-09-11 / 2020-09-18 | inline captures.csv, but that file only covers releases 2015-01-01..2026-10-15 at zooms 16-18 | holds within that scope (finding 11) |
| 295-296 | newest drawn by **every** release 2022-05-18 to 2026-09-24, **the latest** | measured by r2 (54 of 54, cover 1; 2026-09-24 latest in config). Not reproducible from committed files | holds (r2), unguarded |
| 296 | nothing newer has been released here | r2 (also zoom 19-21 of the latest release) | holds |
| 296-297 | Sentinel-2 images every summer, at 10 m | | holds |
| 311 cap | cutblock = share inside a consolidated cutblock + start year, where ≥10% | script 286-298 (largest single block) | holds |
| 311-314 cap | 209 ha no change, 68.3 switched once and stayed, 52.7 never settled, 63.6 flickered back to first class | inline summary.csv; `freq()` 20902/…; by-year rows sum to 68.31 | holds |
| 319-321 | map moves unchanged ground between similar classes, as with one meadow | looked | holds |
| 322 | 2018 or 2023 switch rests on one year on one side | r1 (endpoints exactly 2018/2023) | holds |
| 323-325 | nothing after 2020-09-18; 2016-09-11 covers only part of the box | inline `cover_max` 0.811 | holds |
| 326 | Sentinel-2 at 10 m **bears out a date** | measured on the seen areas: the peak falls in the mapped year for C, D and E, though D and E are no land-cover change, and misses for A (2020) and B (2019) | weak (finding 9) |
| 326-327 | shows ground opened up or greened, not what did it; pale patches | no area in the article is shown greening, but this reads as a capability statement | holds (loosely) |
| research doc 61-72 | 182 releases; 2014 at 57% in its last release; 2016 never above 81%; filter as in script | r2 recomputed from the cache; the script applies the same filter at 207-208 | holds |
| research doc 72 | produced by `data-raw/wayback_change.R` (since replaced) | deleted in d43083c, and the line says so | holds |

## 3. The two fix commits

- **227a793**: the guards it added hold on the data (I share 0.27 and year 2023; 2019 palest).
  The `seen_by_eye` rewrite gave E "the same before and after", and that verdict is wrong (finding 1).
  The "Uncoloured" caption sentence is correct.
- **7f3a4bf**: the `rise` matrix and `rise_year` are correct. I reproduced every value. `which.max` drops NA,
  and no area has an NA year mean. The pick moving into the shown `wayback` block is correct. The script's
  later `picks[match(sharp_dates, ...)]` reorder happens after the shown block, so the reader's `picks` is
  in pick order. But `names(chips)` is taken from `picks` itself, so the names stay right either way. The
  fetch loop that retries ahead of the shown block depends on the chip cache returning on identical
  arguments, and `dft_wayback_fetch()` caches the finished raster. No functional bug.
  - The commit message says "so the shown code is what ran". That was made true for the fetch blocks only
    (finding 2).
  - A's verdict was fixed, but E, the same meadow's third patch, was not re-read (finding 1).

## Findings

- **[claim]** vignettes/articles/floodplain-change-dating.Rmd:78 and :265-266. E's verdict says "the same
  before and after", and the prose puts the 2016 mowing "across D and the western arm of A". At full size,
  E's southern lobe south of the farm track (x ≈ 685480-685700, y < ≈ 6030090) lies on the same diagonally
  striped, mown field as D in `wb_E_2016-09-11.tif`, and it is uniform green in `wb_E_2020-09-18.tif`. That
  is about 0.5-0.7 ha of E's 3.9 ha (crop of the E polygon below y = 6030090 / 6030100, x < 685700). This is
  the same defect as round 2's A finding, one patch further on. Give E the same wording as D, and say
  "across D and parts of A and E".
- **[claim]** Rmd:196-213 (`fig-lead`), :260 (`fig-seen`), :278 (`fig-s2only`). The fold hook shows these
  chunks' code. The code uses objects that only the hidden `data` chunk defines: `change`, the 8-bit `s2`
  list, `areas`, `yr_set`, `yr_col`, `grey_col`, `draw_fp`, `crs`, `area_rows`, `wb_panel`, `s2_panel`,
  `seen` and `s2_only`. No shown block produces `change`: the shown `dates` block ends at `bc` and
  `category`, and `change` is built in script lines 117-128, outside every `## ----` block. If a reader
  carries on from the shown fetch code, two things go wrong.
  - The shown `s2` is a reflectance composite, so `plotRGB(s2[[7]], scale = 255)` does not draw the image
    the page shows.
  - The script's `change` holds 2018-2023, not 18-23, so `coltab(value = yr_set - 2000)` colours nothing.
  This is round 2's `picks`/`fetch_retry` finding, unfixed for the figure chunks. Fix: hide the figure
  chunks (`echo = FALSE`), or show the `data` chunk they depend on.
- **[fragile]** Rmd:106-115 with :272-277. Two things are left unguarded.
  - Nothing ties `wb_before[s2_only]` to `newest`, yet the prose and the caption print `fmt(newest)` while
    the panels draw `wb_before`. It holds today (all five are 2020-09-18).
  - Nothing asserts that `seen` and `s2_only` together cover all `nrow(areas)`. An area that got no Wayback
    view would still be lettered on the map and listed in the table, but it would drop out of both figures
    and both paragraphs without a word.
  Add `all(as.Date(areas$wb_before[s2_only]) == newest)` and `length(seen) + length(s2_only) == nrow(areas)`.
- **[fragile]** Rmd:283-284. "In one summer" (F, H, I, J) and "over two summers" (G) are unguarded.
  - They hold today: the mapped-year rise is +71.7 to +80.2 against at most +14.4 in any other year, and G
    rises +31.8 then +51.2.
  - The `which.max` guard would pass if F's opening were spread across two years.
  Guard both with a ratio or a threshold on `rise`.
- **[claim, low]** Rmd:230 (tools table). "Sharp (under 1 m) images" describes what the article filters to
  (`res_m < 1`), not what the tools give. Over this very box, `dft_wayback_captures()` returns the
  2009-01-15 SPOT 5 capture at 2.5 m, served by 47 releases (captures.csv). Say "dated images, sharp (under
  1 m) where a provider supplied them".
- **[claim, low]** Rmd:236. "takes the June and July scenes". `dft_stac_composite()` keeps only scenes at
  or under `cloud_cover_max = 20` (R/dft_stac_composite.R:175). That bears on the 2019 pale patches the next
  sentence names. Say "the June and July scenes under 20% cloud".
- **[claim, low]** Rmd:245. "keeps every past version of Esri's World Imagery basemap". The archive starts
  at its first release (2014), and the article reads only 2015-01-01 onward (script line 200). Say "keeps
  past versions … since 2014".
- **[claim, low]** Rmd:257 and the :259 caption, "from after it (2020-09-18)". For D and E (dated 2020) the
  2020-09-18 capture is in the change year, not after a dated switch. It also falls after their "summer of
  the change" Sentinel-2 panel (June-July 2020) in the same row. "From the year of the change or after"
  would be accurate. The script's own rule is `cap_year >= year`.
- **[claim, low]** Rmd:326. "Sentinel-2 at 10 m bears out a date". On the five areas with sharp images, the
  peak brightening against the box falls in the mapped year for C, D and E. The sharp images show D and E
  as no land-cover change. The peak misses for A (peak 2020, mapped 2018: +83.0 against +62.8) and for B
  (2019, the pale year). So what Sentinel-2 corroborates here is the timing of a brightness change, not of
  a land-cover change. The A sentence at :267-268 makes this point for A alone. The limit should say it
  generally, or drop "bears out a date".
- **[claim, low]** Rmd:82-83 (verdicts I and J). "Opens to bare ground in 2023" comes from 10 m true
  colour, where tan and pink patches fit bare soil, slash, or dry or dead vegetation equally. The prose
  (:283) hedges with "grass or bare ground", and Limits (:326) says Sentinel-2 shows "not what did it".
  The verdicts name the surface anyway: "opens up in 2023" would match.
- **[claim, low]** Rmd:294. "Over this box it holds 3 sharp captures." captures.csv was read only from
  releases 2015-01-01 to 2026-10-15 at zooms 16-18. 2014 releases were not read, and zooms 19+ were checked
  (by r2) only for the latest release. Either scope the sentence ("its releases since 2015 hold") or widen
  the read.

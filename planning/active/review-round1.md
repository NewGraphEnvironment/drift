# /code-check round 1 (#108), branch 108-article-watching-forest-change-with-esri vs main

Reviewer: general-purpose subagent, 2026-10-15. Probes ran in a `git archive HEAD` copy under the
session scratchpad, against the warm drift cache; nothing in the repo was modified except this file.

## Findings

- **[bug, wrong claim]** vignettes/articles/wayback-change.Rmd:245 (fig-s2 caption) says the shared
  stretch means "a difference in brightness is in the ground and not in the display". The article's
  own limits bullet (lines 284-287) says the opposite for 2023: the whole scene is brighter (median red
  0.0378 against 0.0234-0.0297), "so not all of its pale ground is new". The script's comment at
  data-raw/wayback_change.R:155 also says "A hazy year brightens the whole scene". A shared stretch
  puts a brightness difference in the *data* (ground, atmosphere, illumination and compositing), not
  the ground alone. As written, the caption contradicts the limit about the very panel the reader is
  told shows the largest change. Fix: "...is in the data, not in the display", which is the script
  comment's own wording at line 184.

- **[fragile, visible artifact]** data-raw/wayback_change.R:175-178 writes the window chips with
  `COMPRESS=JPEG` and `NAflag = 0`. Lossy JPEG turns some dark value-1 pixels into 0, and those
  cells then read back as nodata. Measured: the committed `wb_2014-06-01_window.tif` has
  **1,592** cells with an NA band and `wb_2016-09-11_window.tif` has **468**, while the cached source
  chips cropped to the same window have **0** (`dft_wayback_fetch(aoi, "26751"/"9812", 17, ...)`,
  then `crop` and `global(anyNA())`). They render as white specks in fig-window, which has a white
  background (a few are visible in the 2016 panel). The window is checked to be fully covered (lines
  200-213), so these chips need no nodata. Fix: write the window and overview rasters with no
  `NAflag`, or clamp the values to at least 1 after reading, or use DEFLATE for the window chips at
  some cost in size. `wb_overview.tif` (min 36+) and the S2 rasters (DEFLATE) are unaffected.

- **[wrong claim, minor]** vignettes/articles/wayback-change.Rmd:236-238, together with the limits
  bullet at 282-283. The text says a change that first appears in one panel "happened after the
  previous panel's window and before this one's", and that a composite "dates a change only to the
  gap between two windows". A median composite does not support that bound. A change late in the
  previous window (a cut on 20 July 2018, with most clear days before it) still shows the old state in
  that window's median, and a change early in this window shows the new state. So the change can fall
  inside either window, not only in the gap between them. The specific result at line 261, "between
  July 2018 and July 2020", happens to cover July 2018 and is roughly right. The general sentence and
  the limits bullet are not. Suggest: "after the start of the previous panel's window and before the
  end of this one's".

- **[claim hides a difference between panels]** vignettes/articles/wayback-change.Rmd:81 (fig-window
  caption, "drawn at 0.5 m"). Per picks.csv, 2014-06-01 and 2016-09-11 are fetched at **zoom 17**,
  which is about 0.70 m at 54 N by `dft_wayback_captures()`'s own doc. 2020-09-18 is fetched at zoom
  18, about 0.35 m. So two of the three panels are 0.7 m tiles upsampled to the 0.5 m grid. The
  captures table, meanwhile, lists 2016-09-11 at 0.31 m. "Drawn at 0.5 m" is literally true, but it
  reads as one resolution across the panels, and the limits list (lines 278-281) puts the
  differences between panels down to sensor, season, angles and contrast, not to the zoom. A
  sharpness difference a reader sees between the 2016 and 2020 panels is partly the zoom. Either name
  the zoom in the caption or add it to the limits bullet. Not a data error.

- **[convention, writing.md "Cut what serves the authors"]**
  vignettes/articles/wayback-change.Rmd:218-219, "the data-raw script checks this". This is an
  author's verification step stated in the body. The rule allows one "how it's built" link, at the
  end, and line 289-290 is that link. The reader needs only the fact (the capture is drawn over the
  whole square), so drop the clause.

- **[measured on a different call, minor]** vignettes/articles/wayback-change.Rmd:141, "a quarter of
  an hour here". The only cold measurement on record (findings.md, progress.md) is 16 min at **zoom
  16:19** (4 metadata queries per release). The code shown and the script use 16:18 (3 per release),
  whose cold time was never measured, because its layers were already cached from the 16:19 probe.
  "A quarter of an hour" is close to 16 min, but it times a call with a third more queries than the
  one on the page. Say "about a quarter of an hour", or drop the number.

## Checked and found correct

- Every number in the prose against the CSVs: 10.59 km², 359.7 ha, 182 releases from 2015-01-21 to
  2026-09-24, 4 captures (3 sub-metre), 2014 last in 2022-04-27, 54 releases from 2022-05-18, 81%,
  57%, the days 658, 651 and 1016, the S2 medians.
- The descriptions of `dft_wayback_pick` and `dft_wayback_captures` match the code: ranking by days,
  then res, then the newer release, with cover only as a tiebreak; cover as the on-top share.
  `dft_stac_composite` defaults: median, res 10, SCL mask.
- The figures. The window shows forest in 2014 and 2016, then the clearing with a spur road and the
  track along the valley-floor edge in 2020. S2 2018 is forest and 2020 bare. In 2022 the clearing is
  greening and a new pink block sits about 0.5 km to its SW, at the window's SW corner. In 2023 the
  valley floor is pale, with bare strips running east. The 2016 cloud and shadow over the
  south-centre is confirmed on the cached chip.
- The three scale bars measure 200 m, 1 km and 1 km against their extents. The window square sits in
  the same place in the overview and in the S2 panels.
- The gq `floodplains` key exists exactly (no `$` partial match) and is `#1f78b4`. gq is public, in
  Suggests and in Remotes. temporal-composition already uses `gq::` in CI.
- No `.aux.*` was written by reading the rasters, and `git status` stayed clean.

## Verdict

Not clean: 1 wrong claim in a caption (fig-s2), 1 visible raster artifact (JPEG nodata holes), and 4
minor items.

# Review: draft commits on #108 (git diff 28cea67 HEAD), round 2

Method: I copied the repo to the scratchpad and rendered the article there (`bookdown::html_document2`,
exit 0, 21 s, 2026-10-16 20:38-20:38:35 UTC). I read the knitted markdown and looked at
fig-context and fig-box by eye. I read the data script and checked every added or changed
sentence and caption against areas.csv, captures.csv, summary.csv and context.csv. I also
compared the extents of wb_box and change.tif.

## Findings

- **[severity: fragile, claim the figures contradict]** vignettes/articles/floodplain-change-dating.Rmd:272-273.
  The sentence says "The 5 areas dated after 2020 are seen only in Sentinel-2". Each of those
  areas (F, G, H, I, J) has a sharp Wayback panel from 2020-09-18 in its row (fig-s2only), and
  the verdicts for them rest on that image. Line 379 reads F, H, I and J as forest and G as an
  open meadow from it. The G verdict ("Unclear") and the "forest opening up" reading of the
  other four both depend on the 2020 Wayback view, so the sentence misstates what the
  verdicts rest on. Only their change is seen only in Sentinel-2. Suggested wording: "... are
  seen after the change only in Sentinel-2".

- **[severity: fragile, unsupported claim]** vignettes/articles/floodplain-change-dating.Rmd:361-362
  (and the comment at 103-104). The text says the link "opens Google's current satellite image
  of it". The article cannot know that Google's image is current, and the code comment two
  lines above `areas$google` admits as much: "Google does not say when its image was taken".
  Imagery at zoom 17 in rural BC can be several years old, possibly older than the 2020-09-18
  Wayback capture. A reader told it is "current" would take it as the after image for F-J,
  which is exactly the gap the article says it cannot fill. Suggested wording: "Google's
  satellite image of it, which Google does not date".

- **[severity: fragile, caption omits what the figure shows]** vignettes/articles/floodplain-change-dating.Rmd:255
  and 258. fig-box lays white at alpha 0.35 over all ground outside the floodplain (line 258),
  but its caption does not say so. In the render, the ground outside the floodplain comes out
  a flat pale grey-green and the floodplain dark green, which reads as a property of the
  2020 image. fig-lead's caption names its dimming ("Ground outside the floodplain is
  dimmed"), but fig-box sits above it, so a reader meets this figure first. Fix: add the same
  sentence to the fig-box caption.

## Checked and fine

- The round-1 fixes hold:
  - Lead sentence (268-271): it is now limited to the 5 `seen` areas. "only C" is correct over
    that set, and A, B, D and E are the Class error rows. The guards at 136-137 tie the
    verdict groups to `seen` and `s2_only`.
  - Table caption (423): it now names "likely change or unclear", which covers G.
  - Data-script header (8-14): it now lists the watershed group and the Esri tiles among the
    sources read live.
- "dated after 2020" (272): the s2_only years are 2021, 2022, 2022, 2023 and 2023. None of the
  `seen` areas is dated after 2020. Nothing guards this, but it holds for the committed data.
- Table order: Class error first, then Change, Likely change and Unclear, as the caption says
  ("class errors first"). `row.names = FALSE` with `[ord, ]` renders cleanly.
- fig-box caption: the 2020-09-18 capture has cover_max 1 in captures.csv, and wb_box has no
  NA cells. Its extent matches change.tif to within 5 m, so the aspect ratio and the dimming
  overlay line up. The 10 gold outlines are the 1 ha+ same-year patches (summing to 49.4 of
  68.3 ha). The 500 m bar comes from `sbar(500)` in UTM.
- fig-context:
  - The floodplain is drawn blue (the gq floodplain fill) and stays inside the group outline.
  - The inset shows BC with the group in red.
  - The legend draws after `plotRGB`, so the legend-after-terra-plot trap did not bite.
  - The box sits east of Houston, inside the group.
  - The scale bar reads 0-20 km. Its cos(latitude) correction was verified in round 1.
  - The credit line is embedded in the caption.
- Rows in the `results = "asis"` chunks: each `**X** · ... · [Google Maps](...){target="_blank"}`
  line is followed by its own image, in order, 5 + 5 rows. No prose refers to a figure
  number, so dropping fig.cap on fig-seen and fig-s2only breaks no cross-reference.
- Data script: `bulk`, `around`, `topo`, `simple` and `context` are not reused elsewhere.
  `bc_outline` avoids a clash with `bc`. The `"BULK"` literal in `filter()` is translatable
  by bcdata. dplyr is in DESCRIPTION.

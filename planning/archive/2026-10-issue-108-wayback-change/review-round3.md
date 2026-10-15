# Code review, round 3 (#108, branch 108-article-watching-forest-change-with-esri at 9267c36)

Reviewer: general-purpose subagent, 2026-10-15. Probes ran on the committed artifacts read in
place (read-only) and in a `git archive HEAD` copy under the session scratchpad, against the warm
cache. Nothing in the repo was modified except this file.

## The mechanism

Round 1's six findings share one assumption: **a sentence describes what the code set out to make,
not what the page shows.** "A shared stretch" was taken to mean the brightness is "in the ground".
"Values 1-255, nodata 0" was taken to mean no data cell is lost, but JPEG made new zeros. "Window"
was taken to date the change, but a median doesn't. "res = 0.5" was taken to mean 0.5 m detail.
A clause the authors needed was taken as one the reader needs, and "the call" was taken as the call
that had been timed. I walked every claim the page makes against the data or pixels that produce it:
about 69 factual sentences and captions, plus the echoed code. Two places are still reached.

## Findings

- **[bug, the page shows code that fails or misleads]** vignettes/articles/wayback-change.Rmd:6-15.
  The setup chunk does not set `echo = FALSE`, so the page prints the code of 5 chunks:
  `fig-window`, `captures-table`, `picks-table`, `fig-overview` and `fig-s2` (12 source blocks in
  docs/articles/wayback-change.html; temporal-composition sets `echo = FALSE` and prints 0).
  That code draws the article's figures and tables. It is not the drift workflow. It calls helpers
  defined only in the hidden `load` chunk (`d()`, `draw_fp()`, `panel_label()`, `fmt()`, `sub`,
  `win`, `pk`). It also contradicts the code the reader is shown:
  - `captures-table` reads `cap$cover_max`, `cap$n_releases`, `cap$release_first` and
    `cap$release_last`. The `cap` built two chunks earlier in `captures-code` is raw
    `dft_wayback_captures()` output, which has none of those columns. A reader who runs the page
    in order gets `NULL` columns, and `data.frame()` errors on the mismatched lengths.
  - `fig-s2` calls `plotRGB(s2[[i]], scale = 255)`. The `s2` from `composite-code` holds
    reflectance in 0-0.1 (median red 0.023-0.038), so that call draws a near-black panel. The
    committed 8-bit stretched rasters are what make the figure look right, and the page never
    shows that step.

  This breaks writing.md's "Cut what serves the authors": only the people who built the page would
  miss this code. The page's `par(op)` lines also render as separate code blocks between captions.
  Fix: set `echo = FALSE` on the five display chunks only. A global `echo = FALSE` would also hide
  the four `eval = FALSE` chunks (`captures-code`, `pick-code`, `fetch-code`, `composite-code`)
  unless each of them gets `echo = TRUE`.

- **[wrong claim in captions, minor]** vignettes/articles/wayback-change.Rmd:224 and 248 (the
  fig-overview and fig-s2 captions, "the blue line the edge of the floodplain"), with
  data-raw/wayback_change.R:232-237. `st_intersection()` with the box closes the clipped polygon
  along the box frame, and `draw_fp()` draws every ring, so about 2.4 km of the blue line runs
  along the box edge where the floodplain continues outside the box:
  - right edge x = 686717.8, from N 6029172 to 6030174 (1.0 km);
  - top, from E 684543 to 685155 (0.6 km);
  - left edge x = 683393.1, from N 6028662 to 6029149 (0.5 km);
  - two bottom pieces (0.15 and 0.18 km).

  These show in the rendered overview: there is a blue line along the right frame, about a third
  of the way down, and on the top and left frames. They also show on every S2 panel. A reader told
  that the line is the floodplain's edge reads the floodplain as ending at the box edge there. The
  359.7 ha figure is unaffected. Fix: draw the boundary of the unclipped floodplain
  (`st_boundary()` of the full layer, then `st_intersection()` with the box), or use a mask in place
  of an outline. Either way, keep the polygon for the area.

## Checked and found correct (this round)

- **2023 "brighter across the whole box".** Measured on the committed s2 rasters, which share
  one linear stretch, so the ordering is preserved below the clip. Red is brighter in 2023 than in
  2022 on 93% of cells. On "stable dark" cells (below the 2022 median in all three other years),
  it is brighter on 98%. Each box quadrant is brighter: 85-99% of cells. So the claim is not just
  the new bare ground moving the median.
- **"The centre of the square is forest in 2018 and bare in 2020, greening by 2022."** Median red
  over the clearing (684000-684400 E, 6028750-6029100 N, 8-bit) is 43, 158, 88 and 130.5 in 2018,
  2020, 2022 and 2023.
- **"A new bare patch has opened just south-west of it" in 2022.** The rectangular block at the
  window's SW corner is new in 2022. Part of its eastern side, and the bare track along its north
  edge, were already pale in 2020: median red over 683700-684200 E, 6028000-6028350 N is 47, 94
  and 170 in 2018, 2020 and 2022. "New" holds for the block. Not raised.
- **"Its releases draw the older capture on the rest" (2016).** In all 33 releases serving
  2016-09-11, the 2016 and 2014-06-01 covers sum to 1. 2016 covers 0.81 in 13 releases and 0.43
  in 20.
- **"A rerun takes under a minute".** The warm `dft_wayback_releases()` plus
  `dft_wayback_captures()` call shown on the page took 39.6 s.
- **The S2 stretch.** It pools the 2-98% quantiles and clamps. 6% of 2023 red cells sit at 255,
  so brightness is clipped there. A difference that is visible is still in the data, so the caption
  holds.
- Every other date, count, share, zoom and day count on the rendered page matches the CSVs and
  the code: the `dft_wayback_pick` ranking, the `dft_stac_composite` defaults (median, 10 m,
  cloud masking), the fetch's `-tap` grid, and deepest-zoom-covering-whole.
- The post link returns 200. The `data-raw/wayback_change.R` link on `main` returns 404 until the
  branch merges, which is expected.
- The script's write and fetch paths match round 2: the JPEG NaN tag, DEFLATE nodata 0 on the S2
  rasters, the retry re-raising its condition, and the window cover check at each pick's zoom.

## Verdict

Not clean: 1 bug (5 echoed display chunks, whose code fails or misleads against the code the page
shows) and 1 minor caption claim (the floodplain outline traces the box frame).

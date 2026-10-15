# Code-check round 4 (#108): wayback-change article

Reviewed: `git diff 448874591b80703e81840d455879968c7fc7b5b9...HEAD` (excluding *.tif), HEAD dc1d12c in
detail. Rendered page and the three figures inspected.

## Clean

No issues found.

## What was checked (round-3 fixes first)

**Floodplain edge stops at the frame.** Parsed `floodplain.csv` with sf:
- `edge` minus boundary(`area`) = 0 m, so no internal or shared-feature lines are drawn inside the box.
- boundary(`area`) minus `edge` = 2,401 m, and all of it lies on the box frame (0 m off the frame):
  exactly the clip lines that round 3 objected to, now excluded.
- Every one of the 8 edge parts starts and ends on the frame (or is closed: one ring, the small
  island at the top). The edge reaches outside the box by 0.007 m (coordinate rounding).
- The only edge segment near the frame is part 4: 37 m drawn 1.6 m inside the left frame
  (x = 683394.7). It is the floodplain's own boundary, not the cut, and shows as a short blue tick
  on the left frame of the overview and S2 panels. Not a defect; noted so nobody reads it as a
  regression.

**Area unchanged.** The `area` part has the same hectares (359.7) as HEAD~1's polygon, and the
symmetric difference of the two polygons is empty. The page prints 359.7 ha.

**Nothing prints that should not.** The rendered HTML has exactly four `<pre>` blocks: the four
`eval = FALSE, echo = TRUE` workflow chunks. No setup, load or figure code and no `#>` output appear.

**Mechanism (a sentence states what the code meant to produce, not what the page shows).**
Checked each place against the data or the cache:
- Release/capture prose: from the warm cache, release 9812 draws 2016-09-11 on 81.06% and
  2014-06-01 on 18.94% of the box. All 33 releases serving 2016-09-11 draw only 2014-06-01 beside it
  ("its releases draw the older capture on the rest"). 54 releases fall on or after 2022-05-18 and all
  54 draw 2020-09-18 at cover 1.
- "a rerun takes under a minute": `dft_wayback_captures()` over 182 releases from cache took 40 s,
  and the whole script 47 s.
- 2016 cloud: the cached release-9812 box chip shows cloud and shadow in the south-centre. The
  2014 chip (release 26751) is cloud-free there, so the cloud belongs to the 2016 capture.
- "a new bare patch has opened just south-west of it" (2022): S2 red-minus-green over 100 m cells at
  about (684000, 6028220) is -71/-62 in 2018/2020 and +45/+46 in 2022. The patch is new in 2022 and
  lies SSW of the clearing.
- Window caption and text ("between two arms of the floodplain and outside both", spur road, track):
  they match the window figure.
- Zoom values in the caption and limits (0.7/0.7/0.35 m, zoom 17/17/18) match `picks.csv` and
  `zoom_m()`.
- 2023 medians match `s2.csv`. The blue line is gq's floodplain fill `#1f78b4`.
- Reproducibility: ran `data-raw/wayback_change.R` from a fresh clone at dc1d12c, warm cache. The
  committed outputs were unchanged (`git status` clean apart from the run log), including
  `floodplain.csv` and the JPEG rasters.

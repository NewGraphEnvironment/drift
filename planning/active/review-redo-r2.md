# Review round 2: #108 article redo (branch diff 4488745...HEAD, focus 227a793)

Reviewer worked in a copy of `vignettes/articles/floodplain-change-dating/` in the scratchpad; the
repo was not modified apart from this file. One read-only network call was made (`dft_wayback_releases()`,
the config JSON); `dft_wayback_captures()` was run on the box for 2020-01..2022-06 releases from the
cached metadata. The data-raw script was not rerun.

## Findings

- **[claim] vignettes/articles/floodplain-change-dating.Rmd:277 (also :175-177, :322, and the
  stopifnot at :106)**: "Sentinel-2 dates each of them: in its year, each area brightens more than the
  box as a whole does." The stated test does not date anything, because it passes in most years.
  I recomputed `rise - rise_box` for every area and every year 2018-2023 from the committed `s2_*.tif`,
  using the article's own method (mean of the three display bands, `extract(fun = mean)` against
  `global(mean)`). It passes in 33 of 60 area-years: F in 4 of 6 years, H 3, I 4, J 5. What does pick
  out the mapped year for F, H, I and J is the size of the rise: +75.6, +80.2, +79.9 and +71.7 in the
  change year, against at most +14.4 in any other year. G is the exception. Its excess is +31.8 in 2021
  and +51.2 in 2022, from a 2020 value of 21.0, darker than any forest in the box. So Sentinel-2 puts
  G's opening across 2021 and 2022 and does not date it to 2022. The guard checks only the sign
  (`all(areas$brightens[s2_only])`), so it cannot catch this. A similar caveat applies to the A
  sentence at :263-264: A's largest excess is in 2020 (+83.0), not in its mapped year 2018 (+62.8).
  The sentence's point still holds, but "in its year" is not where A stands out. Fix: state the
  evidence as the rise in the change year being the largest of the series (and guard that with
  `which.max`), and say that for G it is spread over 2021-2022. Also soften "dated by Sentinel-2 alone"
  (:177) and "Sentinel-2 ... dates a change" (:322). The date comes from the land-cover map, and
  Sentinel-2 corroborates it.

- **[claim] vignettes/articles/floodplain-change-dating.Rmd:245 (blocks `wayback` / `wayback-fetch`
  of data-raw/floodplain_change_dating.R:197-241)**: the code shown for "then picks and fetches by
  capture" does not contain the pick. The rendered page shows `releases`, `captures`, then
  `chips <- lapply(seq_len(nrow(picks)), ... fetch_retry(aoi, picks$release_id[i], ...))`. Neither
  `picks` nor `fetch_retry` is defined in anything the page shows; both come from script lines 215-234,
  which sit outside the `## ----` blocks. Confirmed in `docs/articles/floodplain-change-dating.html`:
  `fetch_retry` appears once, `dft_wayback_pick` appears zero times. A reader who copies the code gets
  "object 'picks' not found", and `fetch_retry` reads as a drift function. The hidden step is also the
  one `research/esri-wayback.md` says matters (the per-capture max-cover filter before
  `dft_wayback_pick()`). That contradicts the header's "so what it shows is what ran" (script:15-16,
  Rmd:24). Fix: move the cover filter and `dft_wayback_pick()` call into a shown block, and either
  show `fetch_retry` or call `dft_wayback_fetch()` in the shown block.

- **[claim] Rmd:291-292**: "Nothing sharper or newer has been released here". The 2016-09-11 capture
  is sharper (res_m 0.31, `captures.csv`) than the newest one (2020-09-18, 0.46). What is true is that
  nothing newer has been released. The rest of that paragraph checks out: 54 releases fall between
  2022-05-18 and 2026-09-24, n_releases is 54 for 2020-09-18, no release falls between 2022-04-27 and
  2022-05-18, and 2026-09-24 is the latest release in `waybackconfig.json`.

- **[claim] Rmd:74 (A's verdict) vs :77 (D's verdict) and :259-261**: A is "the same before and after"
  while D is "mown in 2016". In `wb_A_2016-09-11.tif` at full size, A's western arm lies across the
  diagonal edge of the same striped, mown swath, and part of the arm is on the mown side. In 2020 the
  whole of A is uniform green. So part of A shows the same 2016-mown, 2020-grassed difference that D's
  verdict reports. Fix: give A the same wording as D, or restrict A's "the same" to its unmown part.

- **[claim] Rmd:76 and :258-259**: C "with new trails through it". At full size (`wb_C_2020-09-18.tif`,
  southern half), the pale lines inside C wind and run roughly parallel to Maxan Creek. At 0.46 m that
  is as consistent with a side channel or flood scour as with a trail, and the image cannot tell which
  it is. This is the same mechanism round 1 targeted: what something is, named from a glance. The
  opening itself is supported: C sits 18 below the box in 2017 and 12 below in 2018, then 22, 19, 37
  and 47 above it in 2020-2023. Fix: "with new pale tracks or channels through it", or drop the
  sentence.

- **[claim] Rmd:234 and :323**: "A summer with few clear scenes still carries haze: the 2019 image is
  the palest." That 2019 is the palest is measured and guarded (box mean 140.5 against 62.9-98.7 for
  the other years). The cause, few clear scenes, is not measured anywhere: findings.md and the r1
  review record the haze, not a clear-day count. The `aggregation = "count"` call in CLAUDE.md would
  measure it. Until it is measured, say "carries haze", not why.

- **[fragile] Rmd:250-252**: "a sharp image from before the change (`fmt(areas$wb_before[seen[1]])`)
  and from after it (`fmt(newest)`)". This names only the first area's before date and assumes every
  seen area's `wb_after` equals `newest`. It is true today: all five are 2016-09-11 and 2020-09-18. But
  the `seen_by_eye` key check covers id, year and classes, not the `wb_*` columns, so a rerun that gives
  one area another before capture would mislabel the paragraph silently. Add
  `stopifnot(length(unique(areas$wb_before[seen])) == 1, all(areas$wb_after[seen] == fmt(newest)))`.

- **[claim] data-raw/floodplain_change_dating.R:26-28**: the header says change.tif holds "the year
  (2018-2023) of a clean switch". The file holds the year less 2000 (values 18-23, measured with
  `freq()`), as line 317 and Rmd:197 correctly say. Lines 8-10 also list what is read live and omit the
  Wayback release list: `dft_wayback_releases()` calls `wayback_get()` with no cache, every run.

## Checked and found correct

- Box 3.33 x 3.18 km, 10.6 km²; 182 releases 2015-01-21 to 2026-09-24.
- The research note's cover figures, recomputed from cached metadata: 2014-06-01 covers 1.0, then
  0.189, then 0.571 in the last release serving it (2022-04-27). 2016-09-11 never exceeds 0.811, with
  2014 on the remainder in every release that serves it.
- Category codes 0-4 (`break_category_levels()`); change.tif value counts match summary.csv; the
  by-year hectares sum to 68.31.
- Cutblock table and prose: I 27% in a 2023 block, H 3%, the rest 0; "none of the others lies mostly
  in one" holds.
- The lead caption: grey is code 1, uncoloured cells are codes 0 and 2, and dimming applies to NA
  (outside the floodplain).
- Verdicts B, D, E, F, G (open wet strip along a channel), H, I and J (forest in 2020) agree with the
  full-size Wayback views; the S2 brightening for F, H, I and J agrees with the panels.
- The rendered page matches the source at 227a793. No footnotes.

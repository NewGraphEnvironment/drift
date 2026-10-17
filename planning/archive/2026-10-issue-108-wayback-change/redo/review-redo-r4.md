# Review round 4: #108 article, fix commit 2fbce19

I worked in a copy of the repo in the scratchpad (`drift-r4`). The repo itself was not modified apart from
this file. There were no network calls, and the data-raw script was not run.

What I measured:
- the `data` chunk evaluated from `vignettes/articles/`, giving the guards, `rise`, `one_summer` and `caps`;
- eleven guard mutations, each run on its own copy of the data directory or the chunk;
- A, D and E Wayback views at full 0.5 m (1020-1580 px PNGs), with all three outlines on each;
- the shown code taken from the **rendered** HTML (`<details>` blocks) and run in a fresh
  `Rscript --vanilla` from `vignettes/articles/`;
- `pkgdown::build_article(..., new_process = FALSE)` in the copy (exit 0), and all three rendered figures read.

## Round 3 items: status now

| r3 item | what it was | status after 2fbce19 | measurement |
|---|---|---|---|
| finding 1 (Rmd :78, :265-266) | E "the same before and after"; mowing "across D and the western arm of A" | **resolved** | Full-size `wb_E_2016`: E's lobe south of the farm track lies on the striped field, and it is uniform green in 2020. Re-read the set together: all of D is striped in 2016 and green in 2020; A's western arm is on the stripes and its main body is unstriped green. The new verdicts for A, D and E and the prose "across D and parts of A and E" match all three. |
| finding 2 (shown figure code) | the figure chunks used hidden objects | **resolved** | `read-saved` shows the `data` chunk (140 lines in the HTML). The read-saved, fig-lead, `par(op)`, fig-seen and fig-s2only blocks, taken from the HTML and run in fresh R from `vignettes/articles/`, finish with no error and draw 3 PNGs. The figures now read `s2_view`, and the reflectance `s2` from the shown composites block is no longer touched. |
| finding 3 | no guard that `wb_before[s2_only] == newest`, or that seen ∪ s2_only covers every area | **resolved** | Mutations: F `wb_before` set to NA stops (count guard); A `wb_before` set to NA stops (count guard); F `wb_before` set to 2016-09-11 stops (`== newest`). |
| finding 4 | "in one summer" / "over two summers" unguarded | **resolved, with a weak half for G** (below) | `one_summer`: F 75.6 > 2×11.0, H 80.2 > 2×9.0, I 79.9 > 2×7.2, J 71.7 > 2×14.4. Mutations: F 2020 set to 40 stops; J 2020 set to 36 stops; G 2021 set to 5 stops; G 2021 set to −1 stops. G 2021 at **+0.5** with 2020 at +30 (or 2023 at +26) **passes**. |
| finding 5 (tools table) | "Sharp (under 1 m) images" | **resolved** | "Sharp (under 1 m) images where Esri holds them" is now true of a tool that also returns the 2.5 m SPOT capture. |
| finding 6 (:236) | "the June and July scenes" left out the cloud filter | **resolved** | The filter is `eo:cloud_cover <= 20` (R/dft_stac_cube.R:504) and applies scene-wide. "Under 20%" is off only at exactly 20.0, which is immaterial. |
| finding 7 (:245) | "keeps every past version" | **partly resolved** | Now reads "keeps the past versions". The definite article still reads as all of them, and the archive starts at its first release in 2014. Low. |
| finding 8 (:257, :259 caption) | "from after it (2020-09-18)" for D and E, both dated 2020 | **not addressed** | The Rmd at :277 and the caption at :279 are unchanged ("before and after the change"). For D and E the capture falls in the change year: the script's rule is `cap_year >= year`. |
| finding 9 (:326) | "bears out a date" | **rewritten; the new sentence raises its own claims** (findings below) | — |
| finding 10 (verdicts I, J) | "opens to bare ground" | **resolved** | Now "opens up in 2023". The rendered S2 2023 panels show tan and pink openings inside I and J, against dark forest in 2022. "Opens up" describes that without naming the surface. |
| finding 11 (:294) | "holds 3 sharp captures" not scoped to the read | **partly resolved** | Now "the releases from 2015 on draw 3". The release scope matches script line 200. The zoom scope (16-18, script line 202) is still unstated. A capture served only at zoom 19+ would not be counted, and zoom 19-21 were checked (by r2) only for the latest release. Low. |
| table row "shown code runs on its own" (fig-lead, fig-seen, fig-s2only) | wrong | **resolved** | as finding 2 |
| table row "E verdict" | wrong | **resolved** | as finding 1 |
| table row "I, J bare ground" | unbacked | **resolved** | as finding 10 |
| table row "245 every past version" | unbacked | **partly resolved** | as finding 7 |
| table row "273-277 last sharp image = newest" | unguarded | **resolved** | as finding 3 |
| table rows "283-284 one summer / two summers" | unguarded | **resolved (G weak)** | as finding 4 |

## New wording in 2fbce19

- "under 20% cloud": holds (see above).
- "the releases from 2015 on draw": holds for release dates; the zoom scope is still missing (finding 11 above).
- "where Esri holds them": holds.
- "opens up" (I, J verdicts; :303 for F, H, I, J): holds against the rendered S2 panels.
- "more than twice": a code comment, now visible to readers through `read-saved`. It matches the code
  (`r[[k]] > 2 * max(...)`).
- "**mowing moves it too**" (:347): unbacked. See findings.
- The `data` chunk comments are now shown to readers. One of them was written for the Rmd source order, not
  the page order. See findings.

Rebuild: the page builds; it has 8 `<details>` blocks, no footnotes and no literal `\@ref`. The prose and
inline numbers match the measured values: 5 / 5 areas, 2016-09-11, 2020-09-18, 2022-05-18 to 2026-09-24,
209 / 68.3 / 52.7 / 63.6 ha, and I at 27% in a 2023 block. The fig-lead caption, legend, scale bar and
letters read correctly.

## Findings

- **[claim]** vignettes/articles/floodplain-change-dating.Rmd:346-348. The sentence "on a meadow, mowing moves
  it too" states a cause the article never observes. The only mowing on the page is in the 2016 Wayback
  capture. That is before the Sentinel-2 series, whose first rise year is 2018, and the 2020-09-18 capture
  shows the meadow grassed, not mown. Nothing shows mowing in any June-July composite.
  - What the page does show for the meadow is a brightening year with no land-cover change. D and E peak in
    their mapped year 2020 (+42.1, +56.7) and are not a change on the ground. A peaks in 2020 (+83.0), not in
    its mapped 2018 (+62.8).
  - Say that ("on a meadow it moves without any change in cover"), or drop the cause.
- **[claim]** Rmd:301-305 against Rmd:346-348. The new Limits sentence splits the areas: where forest opened,
  the brightening bears out the date; on a meadow it does not. But :301 says "Sentinel-2 bears the dates out"
  for all five S2-only areas, and that includes G. :294 shows G as an open wet meadow in 2020, and :304-305
  says its switch "may be a label catching up". So by the page's own rule, G's brightening year (2022, +51.2)
  does not bear out its date. Scope the :301 claim to F, H, I and J, which is the set the one-summer guard
  already names.
- **[claim, low]** Rmd:277 and the :279 caption, "from after it (2020-09-18)" and "Wayback before and after the
  change". Round 3's finding 8 is unchanged. D and E are dated 2020, so the 2020-09-18 capture is in their
  change year. It is not after a dated switch, and it falls after their "summer of the change" Sentinel-2
  panel. "From the year of the change or after" matches the script's `cap_year >= year`.
- **[fragile, low]** Rmd:120. The G guard is a sign test, `rise[G, 2021:2022] > 0`, the same proxy shape round 3
  named. The verdict text says "brightens over 2021 and 2022". With G's 2021 rise mutated to +0.5 and 2020 to
  +30 (or 2023 to +26), every guard passes, so a two-summer brightening over different years would be
  described wrongly. Today G 2021 is +31.8, so it holds. A threshold on 2021 (for example 2021 at least half
  of 2022) would pin the claim.
- **[claim, low]** Rmd:38-39, the shown `data` comment "(the blocks shown below are from it)". This was true in
  the Rmd source, where `data` sits at the top. On the page the chunk is shown through `read-saved` at :212,
  after the landcover/dates block. Below it are the composites and Wayback blocks, which do come from the
  script, and the three figure blocks, which do not.
- **[claim, low]** Rmd:265 ("keeps the past versions") and Rmd:314 (zooms 16-18 unstated): round 3's findings 7
  and 11 are only partly addressed (see the table).

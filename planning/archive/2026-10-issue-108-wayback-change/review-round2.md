# Code review, round 2 (#108, branch 108-article-watching-forest-change-with-esri at 8ff0188)

## Clean

No issues found.

## What was checked, with evidence

I re-checked each round 1 fix against the data rather than reading the diff alone.

1. **JPEG nodata (fix 2).** `gdalinfo` on all four JPEG files (three window chips and the
   overview) shows `NoData Value=nan` on every band. terra reads them back with 0 NA cells,
   and real 0 values survive as data: 833 / 0 / 931 zeros in the 2014 window, 450 / 0 / 20
   in the 2016 window. So no dark pixel is masked any more. The DEFLATE S2 files keep
   nodata 0, and their values run 1-255. The overview has no NA cell either.
2. **Zoom wording (fix 4).** `zoom_m()` gives 0.70 m at z17 and 0.35 m at z18 for
   lat 54.3753, and the page renders "0.7, 0.7, 0.35 m". `own` in the Rmd matches the
   data-raw `own`: the first pick per capture, zoom 17 / 17 / 18.

   I also checked whether "the deepest zoom covering the whole box in each release" is
   true. I probed zooms 17-19 for releases 26751, 9812 and 63116 from a repo copy:
   - 26751 and 9812 have no dated footprint at z18 or z19.
   - 63116 covers the box at z18 (cover 1) and has nothing at z19.
   - `zoom = 16:19` keeps 17, 17 and 18.

   So the claim holds beyond the 16:18 search range. The 0.31 m 2016 capture is only
   served to z17 in its release.
3. **Composite dating (fix 3).** "After the start of the previous panel's window and
   before the end of this one's" is a correct bound for a June-July median. "Between
   June 2018 and July 2020" follows from it and agrees with the limits bullet. The figure
   shows the square's centre as forest in 2018 and bare in 2020.
4. **Fixes 1, 5 and 6.** Each wording matches its intent. The fig-s2 caption ("in the
   data") no longer contradicts the 2023 haze bullet.
5. **Rendered page.**
   - The prose numbers match the CSVs: 182 releases, 4 captures with 3 sub-metre, 54
     releases from 2022-05-18, 81%, 57%, 658 / 651 / 1016 days, red 0.0378 against
     0.0234-0.0297, 359.7 ha, 10.59 km².
   - There are no footnotes and no literal `@ref`.
   - `pkgdown::check_pkgdown()` reports no problems.
   - gq and bookdown are in Suggests, and gq is in Remotes.
6. **The new `.gitignore` line.** `*.aux.*` ignores only sidecars. All 13 artifacts are
   tracked, and the working tree is clean after the probes.

## Not raised (below the bar)

- The JPEG files carry a NaN nodata tag on Byte bands. terra and GDAL read it as "no
  nodata", so it does no harm.
- The window cover check is a metadata check, not a pixel NA check. Pixels were measured
  with 0 NA, so nothing fails today.

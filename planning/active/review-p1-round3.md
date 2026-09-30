# Review — #92 Phase 1, round 3

Snapshot: `scratchpad/p1snap`, gdalcubes 0.7.5. Brief: find every place in the diff or in the
three functions where a membership list is asserted rather than measured against the consumer.

## Measured first

The round-trip test checks the gdalcubes parser (`cube_view()$aggregation`), which is a stand-in
for the reduction that actually runs. So I ran the real thing: three single-band scenes (values
10, 30, 20 on 07-05, 07-15, 07-25), each value put through `raster_cube()` and then `as_array()`.

| aggregation | parsed as | reduced value | honoured? |
|---|---|---|---|
| min / max / mean / median | same | 10 / 30 / 20 / 20 | yes |
| first / last | same | 10 / 20 | yes (last = the latest date) |
| MEDIAN / Last | median / last | 20 / 20 | yes, ignoring case |
| count, sum | none | 20 | silent fallback |
| none | none | 20 | — |
| count_values / count_images | same | 3 / 3 | yes |

So the allowed six are correct as behaviour, not only as parser output. The code comment's
claims hold: it lower-cases, `count` falls back to `none` and comes back as a value, and
`count_*` are honoured. Probe script: `scratchpad/aggprobe/probe.R`. Both test files pass
(141 and 61 passing). The new tests do not skip; the only skips are pre-existing
(missing-package path, network).

## Findings

- **[fragile]** R/dft_stac_cube.R:322 (`aggregation_check()`, the "x" bullet). The refusal says
  `Got "<value>", which gdalcubes would not honour.` That is false for three values the diff
  refuses on purpose: `"none"`, `"count_values"` and `"count_images"`. I measured all three as
  honoured, and the comment eight lines above says so for the `count_*` pair. It is the same
  mechanism as round 1: a claim about the consumer that was not measured. A user who passes
  `"count_values"` is told gdalcubes cannot do it, when drift is refusing it by policy (items
  are double-counted over MGRS overlap). The message will also be wrong in Phase 2 for any value
  the composite's extended `allowed` refuses. Suggested fix: say it is not supported by drift,
  not that gdalcubes would not honour it. The two test titles that make the same claim
  (`test-dft_stac_cube.R:758`, `test-dft_stac_composite.R:299`) are only labels, not defects.

- **[bug, pre-existing, not introduced by this diff]** R/dft_stac_cube.R:601,
  R/dft_stac_fetch.R:616, and the composite path through `stac_cube_assemble()`. `resampling`
  reaches `gdalcubes::cube_view()` in the same three functions with no validation, and it
  falls back the same silent way, to `"near"`:
  `"bilinaer" -> near`, `"foo" -> near`, `"Bilinear" -> bilinear`, `"nearest" -> near`.
  So a typo in `resampling` on the continuous or composite path returns a
  nearest-neighbour cube, cached under the typo's key, with no error. This is the #92 defect
  on the sibling argument. Out of this phase's scope; file it rather than widen the PR.

No other asserted list is reached:
- The roxygen `@param aggregation` text in all three functions names only the defaults. It
  lists no set and makes no claim about gdalcubes.
- The test's refused list is drift policy, and it agrees with the measurement above.
- The allowed list in the test (`c("min", ... "last")`) duplicates `.cube_view_aggregations`,
  but the round-trip test iterates the constant itself, so the constant cannot drift away from
  gdalcubes.
- No data-raw script, vignette or test passes an aggregation outside the six.

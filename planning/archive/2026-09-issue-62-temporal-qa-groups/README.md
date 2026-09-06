# Issue #62 — Temporal QA across four watershed groups from the published annual series

## Outcome

Ran `dft_rast_break_class()` (#9) on the seven `classified_<year>` COGs stac-floodplains-bc
publishes for every group whose annual IO LULC series is complete — bulk, necr, lnth, kotl
(PINE was dropped upstream, floodplains#76; the issue's "five" became four and the body was
edited before the run). `data-raw/break_class_groups.R` reads the published assets straight
from their hrefs, verifies them against `file:checksum`, runs the BULK pipeline minus the fetch
plus floodplain-shape rows, and its `summarize` stage emits every number the note quotes and
refuses to finish if `inst/notes/temporal-qa-groups.md` does not carry its tables verbatim.
Nothing in `R/` changed. Two follow-ups filed with the numbers: drift#64 (corrected annual
series — flicker is the largest category everywhere, so it is worth building) and
stac_floodplains_bc#67 (`break_n_flips` / `break_year` assets beside `transition_2017_2023`).

What was learned: the BULK split generalises in shape but not in magnitude — sustained 20-31%,
flicker 40-49%, 2017 the odd endpoint everywhere by a modest margin — and the between-group
spread is confounded with producer path (the two cube-cut groups flicker least), which four
groups cannot separate. The per-stream `_by_blue_line_key` layer proposed for the landscape
question was rejected before the run: its polygons overlap 1.7-2.2x and kotl has none. A first
RSS sampler caught the wrapper shell (`cmd && Rscript … &` backgrounds the whole list); the
launcher starts Rscript alone. Four code-check rounds found the same mechanism one artifact
further out each time — a sentence written from a reading of the table, or a derived cell
downstream of a display rounding — reaching as far as a filed issue body; the loop ended by
enumerating every artifact that carries a number from `summary_groups.csv`.

## Measurement

`summary_groups.csv`, one row per group (bulk / necr / lnth / kotl): sustained share of
2017-2023 changed area 19.7 / 31.0 / 20.6 / 24.7 %, flicker 44.0 / 39.6 / 48.5 / 42.3 %,
overstatement factor 5.09 / 3.23 / 4.86 / 4.06; stable-endpoint flicker 0.63-0.97 times the
changed area. 2018-break over 2023-break area 1.22 / 1.25 / 1.17 / 1.09 — 2017 the odd
endpoint in every group; clouds account for 2.8 ha of bulk's 925.7 ha 2018-break area and
nothing in necr or kotl. Flicker share moved 9 points across a 2.5x range of floodplain width
with no monotone relationship. Artifact-signature patches' clean-break share 0.49-0.55 against
0.52-0.62 for the rest. BULK on the published 14651 x 11552 grid against the #9 run on the
fetched 16000 x 12000 grid: +71 valid cells, +4.62 ha changed, shares within 0.03 of a point —
the published pipeline reproduces the fetched one. Runs: 100-323 s wall, 13.7-16.3 GiB peak RSS
on 64 GB for 56M-204M cells (terra sizing to available RAM; the #9 in-memory floor is gone).
Changed the plan for #64 from "maybe" to "build it", and gave stac_floodplains_bc#67 its
numbers.

## Evidence

`data-raw/logs/break_class_groups/` — per-group CSVs, `rss.txt`, `run_wallclock.txt`,
`summary_groups.csv` / `.md`, `summary_bulk_reconcile.csv`, README. Review rounds:
`review-round{1..4}.md` in this directory.

Closed by: branch `62-temporal-qa-across-groups` (commits 69690af, 35b83c8, 0ba2283, 65da417) / PR (see `/gh-pr-push`)

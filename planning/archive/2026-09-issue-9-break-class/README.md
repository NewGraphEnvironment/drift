# Issue #9 — dft_rast_break_class(): sustained switch vs flicker across the annual class series

## Outcome

Added `dft_rast_break_class()`, the temporal, categorical-only leg of change QA beside the
spatial (`dft_transition_artifact()`, #44) and spectral (`dft_rast_break()`, #30) ones. For
each pixel across a named list of classified years it reports `n_flips`, `break_year`,
`n_before` and `n_after`; `$raster` is the first-to-last transition layer in the
`from * 1000 + to` encoding `dft_rast_transition()` uses, so the patch tools take it unchanged,
`$breaks` holds the four evidence layers and `$summary` tabulates area by transition, status
and break year. Nothing is thresholded. One streamed `terra::app()` pass to an LZW INT4S temp
file, one `crosstab()`. The bundled Neexdzii Kwa series now covers every IO LULC year 2017-2023
(`data-raw/example_years_extend.R`, refetched 2017 reproduced the bundled file cell for cell),
and the land-cover vignette has a *Temporal Evidence: Switch or Flicker?* section as the third
leg. Name chosen by the user in plan mode over `dft_rast_switch()`.

One correction to the issue: the BULK STAC item carries `classified_2017/2020/2023` only, not
seven years; the scale run fetches 2017-2023 through `dft_stac_fetch(tile_size = 20000)`.

## Measurement

Bundled tile, 2017-2023: 34.03 ha of endpoint change (93 patches, the #44 numbers), 62.8% a
clean break and 37.2% flicker; of the 2,138 clean-break pixels, 1,098 are sustained >= 2 years
each side and 1,040 have an endpoint as the odd year out (776 are 2023 alone); 2,791 pixels
flicker while reading stable on the endpoints. 0.15 s.

BULK floodplain (`co_ff04`, 386.5 km², 16000 x 12000 at 10 m, 192M cells, seven years fetched in
23.6 min): 4,620 ha of 2017 -> 2023 change in 21,710 patches, of which **19.7% is a sustained
break, 36.4% a clean break with one endpoint the odd year out (922 ha broke in 2018 — 2017
alone differs — and 757 ha in 2023), 44.0% flicker**; 3,187 ha flickers while reading stable
on the endpoints. Patches with the #44 artifact signature (15,047; 826 ha) have an area-weighted
clean-break share of 0.50 against 0.58 for the rest — the two legs are mostly independent.
Scan 87-101 s; whole pipeline (cached fetch, classify, scan, vectors, artifact, zonal) 6.5 min.
Memory (RSS every 2 s): the seven fetched inputs sit in memory and set an 8.5-20 GB floor that
is the caller's; from a 0.3 GB file-backed floor the scan peaked ~10 GB (9.6M-cell chunks) with
the crosstab flat at 7 GB; on the shipped code with in-memory inputs the spill transient peaks
at 20.8 GB and the scan runs 12-19 GB (2.5M-cell chunks). That spill sample is the whole-pipeline peak (KiB / 1024²).

## Evidence

`data-raw/logs/benchmark_break_class/summary_*.csv`, `timings.csv` (committed);
`planning/archive/2026-09-issue-9-*/review-round{1..7}.md` and `review-round8-docs.md` — eight review rounds, every
numeric claim re-measured; `tests/testthat/test-dft_rast_break_class.R` pins the fixtures,
the interop, the encoding invariant and every review finding with a restore-the-bug.

## What the review rounds found (the mechanism: a terra internal contract assumed rather than measured)

| round | found | inside the previous fix? |
|---|---|---|
| 1 | `app()` takes `apply()`-per-cell when `fun` tolerates a vector (57x); INT2S overflow at code 33 is a *warning*; `resample()` does not reproject; no single-layer guard | — |
| 2 | the overflow abort fires before `writeStop()`, stranding a partial file; the vectorised-path guard was unpinned | yes |
| 3 | `app()` infers output shape from a `min(ncol, 13)`-cell test chunk and reads a 5-column return on a 5-column raster as transposed; the stranded-file test aborted before the file existed; 19-row enumeration of every terra call | yes |
| 4 | the pad write warned on a surviving colour table | yes |
| 5 | `coltab<-` strips layer 1 only; `levels<-`/`coltab<-` deep-copy first so the caller-unmutated test could not fail; `set.cats(NULL)` is the in-place form | yes |
| 6 | `resample()` of a factor writes a RAT sidecar the cleanup missed; the spill's strip was unpinned; the spill transient was two copies | yes |
| 7 | `paste0(character(0), ".aux.xml")` is `".aux.xml"`: the cleanup would unlink that name in the caller's cwd on one error path; the cats half of `strip_copy()` redundant with the cleanup | yes |
| 8 (docs) | one RSS sample in two units; NEWS patch-group numbers not emitted by the committed script; review count restated from memory; a transport error would poison the gpkg download | — |

Closed by: branch `9-categorical-breakpoint-detection-sustain` (commits c3f6e44, 59b3f63, 5369b8f, 85b3f7e, 1e37a77, c390b14, 496588a) / PR #61

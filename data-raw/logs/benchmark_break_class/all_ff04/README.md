# benchmark_break_class/all_ff04 — the BULK scale test on `bulk_all_ff04` (drift#118)

Produced by `data-raw/benchmark_break_class_bulk.R` at commit `03f9f69` on 2026-11-13, run
once from a detached worktree of that commit (so neither the script nor `R/` could change under
it) as `/usr/bin/time -l Rscript data-raw/benchmark_break_class_bulk.R run`. 64 GB Apple
silicon Mac, macOS 15.6.1, R 4.5.2, terra 1.9.50, GDAL 3.13.0.

AOI: the `all_ff04` layer of `bulk_all_ff04/floodplain.gpkg` from stac-floodplains-bc, two
features, 660 km². It replaces `co_ff04` (386.5 km²), whose item `bulk_co_ff04` answers 403
from 2026-11-13; it is a different polygon, so these numbers replace the earlier ones rather
than reproduce them. IO LULC 2017-2023 fetched from Planetary Computer with
`dft_stac_fetch(tile_size = 20000)`, cold cache: 34 tiles per year, 1,636 s for the seven,
onto a 16000 x 14000 grid at 10 m (224M cells, EPSG:32609).

| stage | s |
|---|---|
| fetch | 1635.7 |
| `dft_rast_classify()` | 13.9 |
| `dft_rast_transition()` 2017 -> 2023 | 9.9 |
| `dft_rast_break_class()` | 84.4 |
| category crosstab | 28.2 |
| `dft_transition_vectors(changes_only = TRUE)` | 20.9 |
| `dft_transition_artifact()` | 146.6 |
| per-patch zonal | 10.6 |

31,844 change patches, 7,315.3 ha. Whole script 1,959 s (32.7 min) wall, peak memory
footprint 48,027,107,264 bytes (44.7 GiB), maximum resident set size 14,495,481,856 bytes
(13.5 GiB). Size a machine from the footprint: macOS compresses or swaps idle pages
rather than keeping them resident, so the resident set reads far below what the process
held. The block's `swaps` line is always 0 on macOS, so swap was not measured.

Committed evidence (the `.log`, `.gpkg` and `summary_patches.csv` are gitignored):

- `timings.csv` — the stage table above
- `time_l.txt` — the `/usr/bin/time -l` block; `run_wallclock.txt` — start, end, exit status
- `summary_pixels.csv`, `summary_change.csv`, `summary_patch_groups.csv` — as in the parent
  directory's README. `summary_change.csv` keeps the script's four-level labels: its `flicker`
  rows are `dft_break_category()`'s `unsettled` where `changed` is 1 and `stable_flicker`
  where it is 0, and are never summed.

The parent directory holds the 2026-09-05 `co_ff04` run (#9) that NEWS 0.14.0 cites.

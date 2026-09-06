# Code-check round 1 — data-raw/break_class_groups.R, -run.sh, .gitignore (#62)

Reviewed the staged diff against code-check.md / -shell / -r / -spatial, the BULK template
(`data-raw/benchmark_break_class_bulk.R`, unchanged), the package functions the script calls,
and the necr shakedown outputs in `data-raw/logs/break_class_groups/necr/`.

## Findings

- **[bug — evidence record]** `data-raw/logs/break_class_groups/necr/rss.txt` and
  `run_wallclock.txt` were produced by the earlier sampler the task plan says caught the
  wrapper shell, not by the launcher in this diff. `rss.txt` is 39 samples alternating
  3104 / 1488 KiB (a shell, peak 3 MiB; the BULK run's sampler peaked at 21.9 M KiB), and
  `run_wallclock.txt` reads `... start` / `... end` where the committed launcher writes
  `start <group>` / `end <group> (exit <rc>)`. Both files are declared committed evidence
  (`.gitignore` comment, script header), and the `summarize` stage would read
  `peak_rss_gib = round(3104 / 1024^2, 1) = 0.0` for necr into `summary_groups.csv` and the
  Run table of `summary_groups.md`. The committed launcher itself is correct — probed:
  `Rscript … &; ps -o rss= -p $!` reports the `bin/exec/R` process (454 MB on a 400 MB
  allocation), because both `Rscript` and `bin/R` `exec`. Re-run necr through
  `bash data-raw/break_class_groups-run.sh necr` before committing the directory: the
  downloads are cached by `fetch_once`, so it costs the ~2.5 min compute only, and the
  launcher truncates `rss.txt` and rewrites `run_wallclock.txt`.

- **[fragile]** `data-raw/break_class_groups.R:141-142` — `verify_checksum()`'s remedy
  "deleted; re-run to fetch again" walks back through the guard when the mismatch is caused
  by a stale `item.json`: `fetch_once()` skips `item.json` whenever it exists (it has no
  checksum of its own), so if a run is interrupted after the JSON but before the COGs and
  the catalogue republishes in between, every re-run downloads the new COG, compares it
  against the old checksum, deletes it and stops with the same message. Name `item.json` in
  the message (or delete it alongside the mismatched asset) so the remedy terminates.
  Low: needs an interrupted run plus an upstream republish.

## Checked and clean

- necr outputs reconcile: `pct_of_changed` sums to 100.00; `summary_break_year.csv` area sums
  to exactly categories 1+2 (3488.79 ha) and 2018+2023 to exactly category 2 (1698.96 ha),
  confirming the A1 identity; valid cells 4,183,814 in every year; patch area 5779.45 ha
  equals the changed area; `summary_pixels.csv` totals 4,183,814 with no `NA` status.
- Shape: 354.39 / 396.26 / 432.18 km² against item properties 354.61 / 396.51 / 432.46
  (−0.06%, consistent with area in UTM 10 vs BC Albers); `2A/P` recomputes to 186.7 m.
- Summarize stage: every column read has a producer in the per-group stage, and every
  `pick()` selector (`ff02/ff04/ff06`, `all/artifact_signature/other/sliver/wider`,
  `wall/break_class`, `Clouds`, `changed == 0 & flicker`) matches a label the per-group
  stage writes; the BULK reconciliation reads a CSV with the identical six-column shape
  (old `valid_cells` = 4,108,901, matching findings O2); all `kable()` column sets exist.
- Launcher: `Rscript … &` alone so `$!` is the R PID; gate on the `ALL STAGES DONE` marker,
  not exit status; `fails` counted per item; `timings.csv` only read on the OK branch,
  after the marker that follows its write.
- `.gitignore`: `check-ignore` confirms the COGs, gpkg, json, log and `summary_patches.csv`
  are ignored and the summary CSVs, `rss.txt`, `run_wallclock.txt` are not; no tracked
  `.json` under `data-raw/logs` is affected.
- `cat_fun` refuses a bare vector (forces terra's vectorised path); `cat_labels` indexing
  matches the 0-3 codes; year-set and equal-valid-count assertions are in place;
  `st_length(st_boundary())` avoids the lwgeom dependency; `digest`, `curl`, `jsonlite`,
  `knitr` are all available to a `load_all()` session (Imports/Suggests).
- Planning docs: no factual claim contradicted by the code beyond the evidence-file point
  above (`rss_<group>.txt` in the task plan vs `<group>/rss.txt` on disk is naming only).

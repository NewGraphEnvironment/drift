# Review round 8 — data, benchmark and docs commits (59b3f63, 5369b8f, 85b3f7e)

Scope: `git diff c3f6e44..HEAD`. `R/dft_rast_break_class.R` logic not re-reviewed (rounds 1-7).
Every claim below was measured on 2026-09-05 with probes in the session scratchpad
(`probe1.R`, `probe2.R`, `probe3.R`); terra 1.9.34. No repo file was edited. One untracked
`Rplots.pdf` created by my probe run was removed.

## Findings

No bugs. Five fragile items, all in the evidence record rather than the code.

- **[fragile] NEWS.md:9** — "the spill peaks at **20.8 GB** for a few seconds ... Whole pipeline
  peak **21.3 GB**" are the *same sample* in two units. The committed `rss_run.txt` maxes at
  21,843,168 KiB: / 1024^2 = 20.83 GiB (the "20.8"); / 1024 = 21,331 MiB, which the local
  `run.log` prints as `peak RSS MB: 21331.2` and NEWS rounds to "21.3 GB" (MiB / 1000). The
  sentence reads as two different peaks, and the number a reader will compare against #44's
  "10.7 GB" is in a third, unstated convention. `findings.md` line 144 carries the same "21.3"
  against a run-2 "21.8" whose unit is not recorded either. Pick one unit (GiB, since `ps -o rss`
  is KiB) and restate both.

- **[fragile] NEWS.md:6** — the per-patch sentence (area-weighted clean-break share **0.50 vs
  0.58**, **46%** with no clean-break cell, **31%** entirely clean, **15,047 patches / 826 ha**)
  is published with nothing committed that reproduces it. `summary_patches.csv` is gitignored
  (2.7 MB, 21,710 rows) and, more to the point, the committed script's section 6
  (`data-raw/benchmark_break_class_bulk.R:247-251`) prints **medians** — `run.log` shows
  `median 0.25; other patches: median 0.25` — not the weighted means or the 0/1 shares. So a
  rerun of the committed script does not print the numbers NEWS quotes; they exist only as
  prose in `planning/active/findings.md:150-152` from an ad-hoc pass over the ignored CSV. The
  planning archive is a legitimate evidence record per `planning.md`, but the release note's
  rule is that every number derives from the artifact at the time of writing. Cheapest fix:
  replace the median lines with `weighted.mean(break_frac, area_ha)` for `art` / `!art` plus
  `mean(break_frac[art] == 0)` and `== 1`, so the script itself emits the sentence (on the bundled
  tile these are 0.455 / 0.652, 35% / 33%, computed here). Same gap, smaller: **21,710 patches**
  is only in the gitignored `run.log` and `findings.md`; `summary_pixels.csv` gives the 4,620 ha
  but not the patch count.

- **[fragile] NEWS.md:10** — "**Five** review rounds found six defects". The record says seven:
  `findings.md:124-128` ("Seven `/code-check` rounds ... rounds 2-7 each found a defect"),
  `progress.md` ("after seven review rounds"), `task_plan.md` ("seven rounds on the function
  commit"), and `planning/active/review-round{1..7}.md` exist. The sentence also enumerates five
  mechanisms (per-cell `app`, INT2S overflow, `resample` no-reproject, transposed test chunk,
  `writeValues` abort) against a stated six. This is the "restated from memory rather than
  derived from the artifact" release-note shape in `code-check.md`.

- **[fragile, low] NEWS.md:8** — "ran in **6.4 min**": `timings.csv` sums to 387.8 s = 6.46 min
  and `run_wallclock.txt` is 16:14:55 to 16:21:26 = 391 s = 6.5 min. Truncated, not rounded.

- **[fragile, low] data-raw/benchmark_break_class_bulk.R:148-156** — the HTTP guard is correct
  per `code-check-r.md` (status read from `curl`, body unlinked on non-200). The uncovered path
  is a *transport* error — `curl_fetch_disk()` throws on a timeout mid-body (`timeout = 300` on
  an 8.6 MB file) — which propagates past the guard and leaves the partial `floodplain.gpkg` on
  disk; the next run's `file.exists(gpkg)` then skips the fetch and `st_read()` fails on a
  truncated SQLite with a message that reads as a bad file, not a bad download, until someone
  deletes it by hand. `cmd > file` poisoning from `code-check.md`. Not measured (no network);
  from curl's semantics. Fetch to `tempfile()` and `file.rename()` on 200, or `tryCatch` +
  `unlink`.

## Checked and clean

1. **NEWS vs CSVs.** From `summary_change.csv`: changed cells 462,035 = 4,620.35 ha; shares
   19.69 / 36.35 / 43.95 -> 19.7 / 36.4 / 44.0 as published. Stable-endpoint flicker 3,186.56 ha
   -> 3,187. `summary_pixels.csv` break area by year: 2018 922.67, 2023 757.00; 922.67 + 757.00
   = 1,679.67 ha = the endpoint category exactly, so "2017 or 2023 is the odd year out" is
   arithmetically closed. `summary_pixels.csv` and `summary_change.csv` agree on total cells
   (4,108,901) and on break vs flicker among changed cells (258,962 / 203,073). 1,414 s = 23.6
   min; 16000 x 12000 = 192M; scan 87-101 s matches `timings.csv` 101.2 and findings 86.7.
   Bundled-tile 32 / 31 / 37 reproduced (1098 / 1040 / 1265 of 3403 cells).
2. **Vignette section.** Every inline expression evaluated on the bundled data: flicker 37%,
   `sum(one)` 2138 (no NA — `one` is `!is.na(nf) & nf == 1`), `n_sustained` 1098, `n_endpoint`
   1040 (= 776 `n_after == 1` + 264 `n_before == 1`), sustained share 32%, stable-endpoint flicker
   2,791. Every `n_flips == 1` pixel has non-NA `n_before`/`n_after` (0 NA among 2138), and
   `sum(one) == changed break cells` so `n_sustained / sum(changed$n_cells)` divides like by like.
   `changed$pct_area[changed$status == "flicker"]` would render as an empty string if the status
   were absent, but the pinned test guarantees 1265 flicker cells on this data. The
   `summarise()` ordering comment is correct: swapping the order errors (`'x' and 'w' must have
   the same length`) rather than silently mis-weighting, and the `select()` names existing
   columns. Figure: `is_changed` is NA on exactly the 90,053 raster-NA cells, `n_flips` is NA on
   the same cells, so `ifel(is_changed & n_flips >= 2, 1L, NA)` yields NA there and 1 on exactly
   the 1265 changed-flicker cells; `break_year` has six distinct values 2018-2023 so the
   six-colour `type = "classes"` legend labels line up. `aoi_proj` is defined at line 273 and
   used at 277/280/284/395 before the new section. `zonal()` returns `patch_id, n_flips,
   n_flips.1` (positional rename correct); `left_join` on an sf object keeps geometry; no NA
   flags on the bundled patches. The section renders to a device without error.
3. **example_years_extend.R.** `terra::compare(..., "==", falseNA = FALSE)` returns NA wherever
   either side is NA (measured: `TRUE FALSE NA NA TRUE NA` on a 6-cell fixture with value
   mismatch, NA-vs-NA and NA-vs-value), so `sum(== 0, na.rm = TRUE)` counts only non-NA value
   mismatches and the separate `is.na() != is.na()` count catches the NA-mask mismatches — the
   pair is complete and each fixture case landed in exactly one counter. `e$xmin` on a
   `SpatExtent` returns 683391.9 (same as `xmin(e)`). `crs(describe = TRUE)$code` is character
   `"32609"`, so `epsg == "32609"` compares like with like. The local `extend.log` shows the
   control ran: 0 differing cells, 0 NA mismatches.
4. **benchmark script.** `dft_stac_fetch()` has `tile_size` (R/dft_stac_fetch.R:97). `layer =
   "co_ff04"` pinned. `cat_fun` refuses a bare vector; the single-layer `app()` on `codes`
   receives a matrix (13-row test chunk, then 102,364 rows on the bundled tile), so its
   vectorised `fun` is not run per cell. `crosstab(long = TRUE, useNA = TRUE)` returns columns
   `lyr.1, lyr.1, n` — positional rename is the only option and is correct; the NA/NaN row is
   dropped by `!is.na(ct$changed)` and no category is NA after it (category NA coincides with
   changed NA, 90,053 both), so `ct$category + 1L` never indexes with NA. `merge(all.x = TRUE)`
   gives 93 rows for 93 patches, 0 NA `break_frac`; `weighted.mean` is not used in the committed
   script (see finding 2). Bundled run of the same code reproduces the test pins.
5. **Shipping.** The four new `.tif` are 6,066-6,308 bytes; `inst/` is not in `.Rbuildignore`, so
   they ship. `system.file()` in the test is the portable form. No `.aux.xml` sidecars exist in
   `inst/extdata` at the moment (checked after all probe runs). Pre-existing, not this diff:
   `.gitignore` covers `inst/extdata/*.aux.xml` but `.Rbuildignore` has no such rule, so a
   sidecar present at build time would ship.
6. **.gitignore.** `git ls-files` has nothing matching `data-raw/logs/**/*.gpkg` or
   `summary_patches.csv`; `git check-ignore -q` on every tracked path under `data-raw/logs` and
   `inst/extdata` reports none ignored.
7. **CLAUDE.md size line.** Shipped `inst/extdata` (excl. sidecars) = 242,969 bytes = 237.3 KiB;
   "237KB" is right in the binary convention the previous "204KB" used.

## Out of scope, noted

- `CLAUDE.md` has an **uncommitted** working-tree edit (the BULK scale-test paragraph) not in the
  reviewed diff; `git status` shows ` M CLAUDE.md`. Its committed state at HEAD is what was
  reviewed.

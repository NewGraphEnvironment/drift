# drift#72 — expose the temporal split as a function

## Outcome

`dft_rast_break_class()` reports threshold-free measurements and lets the caller compose the
label. That design stays; what changed is that the composition now lives in the package
instead of being re-derived in **four** places (the issue named three — `is_sustained()` in
`data-raw/disturbance_compare.R` was the fourth). Three new exports:
`dft_break_strength()` (the measurement, never versioned), `dft_break_category()` (row grain)
and `dft_rast_break_category()` (pixel grain), split by grain rather than switched by an
argument so the pixel path's terra hazards do not sit in the doc a data-frame caller reads —
and so the patch grain (#67) can be a third function over the same predicate.

The vocabulary went from four levels to five, retiring `flicker`: `unsettled` is flicker whose
endpoints differ, `stable_flicker` is flicker whose endpoints agree, and they must never be
summed. Nothing shipped had ever pooled them — `summary_change.csv` always split on `changed`
— so **no committed number moved in this release**. What changed is that the vocabulary no
longer invites the mistake.

Three call sites migrated (`break_class_groups.R`'s per-group, summarize and article-bulk
stages, and `disturbance_compare.R`); `benchmark_break_class_bulk.R` is deliberately frozen as
the committed producer of the BULK evidence. The committed four-level `summary_change.csv`
files are not rewritten either — `data-raw/read_change.R` maps them on read, and the map is a
bijection with `(changed, four-level)`.

What the work is really a record of: **four review rounds each finding a defect inside the
previous round's fix**, all of one mechanism a reviewer named better than the author had —
*a base-R coercion turns an absent value into a legitimate, in-range one, and the guard beside
it tests the value rather than its provenance*. Recycling and `as.integer(2020.7)`; an NA class
name and a lost RAT; `as.integer("NaN")`. The loop was closed by enumerating every place the
vocabulary is written down, not by a quiet round — and that enumeration found the last one,
the 4→5 map written twice, which is the very mechanism the issue was filed about reproduced
inside its own fix.

## Measurement

**Scale, BULK floodplain, 14651 x 11552 = 169,248,352 cells at 10 m** (97.7% NA outside the
floodplain threads). `dft_rast_break_class()` 60.6 s, `dft_rast_break_category()` **26.8 s**,
reconciliation crosstab 16.5 s, **peak RSS 8.79 GiB** over 52 samples. The pixel-grain category
reproduces the committed four-level run **cell for cell** once mapped; 90,935 sustained cells
carry `strength >= 2` against 168,269 endpoint-only at exactly 1.

**What the split is worth naming.** On BULK, 2,032.9 ha changed-but-unsettled against
3,186.5 ha flickering with the endpoints agreeing. Pooled, that is 7,811.5 ha of "changed"
where the published layer says 4,625.0 — a **69% overstatement**.

**Behaviour preservation, measured not asserted.** The summarize rollup reproduces each group's
committed `summary_change.csv` on integer cell counts in all four groups.
`summary_class_temporal.csv`: 539 rows in, 539 out, key sets identical under the 4→5 map, and
**zero rows whose `n_cells` or `area_ha` moved**. `is_sustained()` equivalent on every input its
caller can reach for series lengths 2 through 9. `article-bulk` regenerates `bulk_grid_1km.csv`
byte-identical, same 21,701 patches, same selected patch 18141 at the same 0.299 min share.

**terra 1.9.34 reads a two-column `app()` return on a two-column raster as transposed** and
scrambles it silently; widths 1 and 3–6 are correct. `dft_rast_break_class()` pads at `ncol == 5`
because its own return is five columns, so the new function needed its own condition — and the
existing width sweep (4/5/6) could not have reached it. Removing the pad turns the test red.

**`as.integer("NaN")` is `0`, with no warning** (R 4.5.2), where `as.integer(NaN)` is `NA` and
`as.numeric("NaN")` is `NaN`. `terra::crosstab(useNA = TRUE)` returns numeric columns carrying
`NaN`, so `as.integer(as.character(x))` publishes a plausible zero. It had reached a committed
artifact (`summary_strength.csv` said `strength 0` for three categories that have none), and in
the article-bulk self-check it would have labelled an unscannable pixel **`stable`** — the one
thing the guard twelve lines below exists to refuse. Found by reading a committed number and
asking what it meant, not by a test.

Two wrong turns worth keeping. `on.exit()` at a script's top level never fires, so the first
BULK run's peak RSS — the whole point of the exercise — was swallowed when a `stopifnot`
aborted; `withr::defer(envir = globalenv())` fixed it. And `df[cond, ]` with an `NA` in `cond`
returns an all-`NA` **row** rather than dropping it, so `all(c(2, 3, NA) >= 2)` was `NA` and the
strength assertion failed on entirely correct data — which read as a bug in the function for
one round trip.

## Evidence

- `data-raw/logs/benchmark_break_category/` — the BULK scale run: `timings.csv`,
  `rss_summary.csv`, `rss.txt`, and the two reconciliations (`summary_category.csv`,
  `summary_strength.csv`), all emitted by `data-raw/benchmark_break_category_bulk.R`.
- `data-raw/logs/break_class_groups/` — the four-group evidence the migration is verified
  against, unchanged by this work apart from the `pct_flicker` → `pct_unsettled` rename.

Closed by: PR #74

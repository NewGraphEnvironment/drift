# Review round 2 — `data-raw/disturbance_compare.R`, `data-raw/disturbance_compare-run.sh`

Reviewed the code on disk, not the mid-rewrite CSVs. Two probes run:

- `terra::crosstab(long = TRUE, useNA = TRUE)` returns **numeric** columns, not the
  factor columns `as.data.frame.table` would give (terra 1.9.34, measured). So
  `as.integer(q$break_year_modal)` in `offset_rows()` is a calendar year, not a level
  index. That was the one way the whole Phase 2 offset could have been silently wrong,
  and it is clean.
- `R/dft_transition_vectors.R:154` assigns `patch_id <- seq_len(nrow(polys_sf))` **before**
  the vector area filter and **before** `st_intersection(out, zones_proj)`, and
  `R/dft_rast_break_class.R:180` returns `breaks = out[[2:5]]` as plain `INT4S` layers with
  no `levels()`. Both premises the join rests on hold.

---

## The mechanism behind round 1

Round 1's findings 1, 3, 5, 6 and the `fire_events_disc` half of 8 are one mechanism, not five bugs:

> **Every derived number is computed from whichever frame is nearest in the code, and the
> frames differ in POPULATION (unclipped vs clipped, tagged vs evaluated, all vs
> only-those-that-broke, per-year vs distinct) or in PRECISION (raw vs round-tripped through
> a rounded CSV). Nothing in the data names which population or precision a column carries,
> so two columns that mean "the same thing" can be computed over different sets and no
> assertion in the script can see it.**

`tag_evaluated` is the right *shape* of fix — it makes one population membership explicit and
carries it into the frame. The remaining findings are the places the same mechanism reaches
that the fix did not name.

Where it reaches in this file, and status:

| site | populations involved | status |
|---|---|---|
| `ev_patch` tags (645–646, 692–695, 655) | unclipped `pat_sv` vs clipped `published` | **fixed** by `tag_evaluated`, gating all three `pops` and `offset_rows()` |
| `join_audit` (556–568) | `pat_sv` geometry area vs cell-count area | clean — `area_ha` is `st_area()` (`dft_transition_vectors.R:155`), not a cell count, so the delta row is an independent check, not circular |
| `recon` area column (491, 449) | drift's own `area_ha` vs post-intersection `st_area` | deliberate, documented at 447–448 |
| `pubd` largest-fragment pick (620, 631) | fragments of one patch | correct: `order(patch_id, -area_ha)` then `!duplicated` |
| **`agree$n_patches` vs `ev$fire_patches_*`** | published-clipped-all vs unclipped∩evaluated∩has-a-break | **finding 1** |
| **stale vs fresh per-group CSVs** | this run vs the last one | **finding 2** |
| **`group_meta.csv$n_fire_events_disc`** | cross-file read with no schema/currency gate | **finding 3** |
| **`reproduced` (summarize) vs `reconciled` (per-group)** | rounded CSV vs raw, plus a different condition set | **finding 4** |
| **`tag_evaluated` for clip-TRIMMED patches** | full patch vs the fragment the tag was evaluated on | **finding 5** |
| **`in_fire == 1` with `fire_year` NA** | Phase 0/2 (year-grouped) vs Phase 3 (flag only) | **finding 6** |

---

## Findings

- **[bug]** `disturbance_compare.R:267-277` (+ `654-656`) — **`pct_lag01` is conditioned on the
  outcome and the excluded count is never reported.** `offset_rows()` filters
  `!is.na(ev_patch$break_year_modal)`, so a tagged patch that never produced a clean break cell
  (all flicker, all stable, or all-NA) contributes no row to `summary_break_offset.csv` at all.
  `agree` then computes `n <- sum(q$n_patches)` over exactly that survivor set and reports
  `pct_lag01 = n_lag01 / n` under the heading *"Agreement at lag 0 or +1, discriminating
  disturbance years only"*. The denominator is the set of patches **that broke**, and the
  statistic is *how well the break date agrees* — the selection is on the outcome variable, which
  biases agreement up, and nothing in any output records by how much.
  This is compounded by adjacency: the generated `summary_groups.md` puts
  `ev$fire_patches_full + fire_patches_partial` (counted over **all** `published` in_fire rows,
  no break requirement) directly above `agree$n_patches` (the filtered set), both labelled as the
  discriminating sample. A reader dividing across the two tables gets a number neither table
  computes. #62 measured flicker at 40–49% of change, so the gap is not a rounding artefact.
  The comment at `649-651` states the restriction for `off`; nothing states it for `agree`, and
  the note quotes `agree`. Fix: carry the excluded count as a column (e.g. `n_no_break_year`,
  from the same `q` before the `break_year_modal` filter) so the denominator is auditable, and
  say so in the `agree` heading.

- **[bug]** `disturbance_compare.R:199-203, 254-255, 727` + `disturbance_compare-run.sh:22-33` —
  **a partially-failed run leaves a mix of fresh and stale CSVs, and `summarize` cannot tell.**
  The runner truncates `run.log` and `rss.txt` per run but never clears `$d/*.csv`. The script
  writes its CSVs progressively — `summary_events.csv` (401), `summary_reconcile.csv` (495),
  `summary_class_compare.csv` (516), `join_audit.csv` (569), `summary_patch_join.csv` (647),
  `summary_break_offset.csv` (677), `summary_flicker_strata.csv` (709), `group_meta.csv` (727,
  **last**). A run that dies in Phase 3 therefore leaves fresh Phase 0/1/2 CSVs beside stale
  Phase 3 and stale `group_meta.csv`. `summarize`'s only gate is
  `file.exists(summary_reconcile.csv)` — which the failed run just refreshed — so it assembles
  the note from two different runs and reports success. The runner's `FAIL` line is out-of-band
  from `summarize` and nothing carries it across. This puts wrong numbers in a committed evidence
  record with nothing saying so, which is the one failure mode this script exists to prevent.
  Cheapest fix: `group_meta.csv` is written last and already carries `date` and `subbasin_md5` —
  stamp a run id (or use `date` + a fresh `ALL STAGES DONE` marker file written at 732) and have
  `summarize` require every group's stamp to be at least as new as its own `summary_reconcile.csv`
  mtime. A `rm -f "$d"/*.csv` in the runner before launch is the blunter version and also works.

- **[fragile]** `disturbance_compare.R:254-255` — **`read.csv(...)$n_fire_events_disc` returns
  `NULL` for a `group_meta.csv` that predates the column, and `data.frame()` silently drops a
  `NULL` argument.** If all four groups carry a stale meta the four frames are consistently
  missing the column, `do.call(rbind, ...)` succeeds, and the `ev` table — and the note built from
  it — ships with no distinct-fire-count column and no error anywhere. If only *some* groups are
  stale, `rbind` errors on mismatched columns, which is the loud direction. So the silent
  direction is the one that fires after a clean checkout or a `git clean`. This is exactly the
  zero-length/NULL-drops-a-column trap: the wrong outcome is a well-formed table. Assert the
  column: `m <- rd(g, "group_meta.csv"); stopifnot("n_fire_events_disc" %in% names(m))`.
  Note `have` is gated on `summary_reconcile.csv` only, so `group_meta.csv` may also be absent
  entirely — that at least errors loudly.

- **[fragile]** `disturbance_compare.R:233-235` vs `517-519` — **the two `reproduced` derivations
  can disagree, and one of them is decided by floating-point noise.** The summarize-stage version
  reads `repro_ha` and `pub_ha` out of `summary_reconcile.csv`, where both were written as
  `round(x, 1)` (491). Each value carries up to 0.05 of rounding error, so the rounded difference
  can exceed the true difference by up to 0.1 — a true delta of 0.02 across a `.149`/`.169`
  boundary becomes a rounded delta of 0.1 and fails `< 0.1`, while the per-group `reconciled`
  (computed on raw sums) passes. Worse, `3627.2 - 3627.1` is `0.09999999999...` in doubles and
  *passes* `< 0.1`, so which side of the boundary a run lands on is not even stable across
  arrangements of the same data. Separately, the summarize version adds
  `max_abs_d_ha < 0.005` — and since `d_ha` was already rounded to 2 dp (514), that condition is
  exactly `== 0`, a per-class hectare requirement the per-group `reconciled` does not impose at
  all. So `group_meta.csv$reconciled` and `summary_groups.csv$reproduced` are two committed
  columns asserting the same claim under different conditions and different precision. Round 1's
  fix #6 aligned the *class-count* leg and left these two. Either compare on unrounded values
  (write an extra unrounded column, or recompute), or make the per-group `reproduced` carry the
  identical condition set and have summarize read that boolean rather than re-derive it.

- **[fragile]** `disturbance_compare.R:645` (+ `686-707`) — **`tag_evaluated` is binary, but the
  zone clip trims as well as drops.** The comment at 635–644 reasons about patches the clip
  *removed*; a patch that straddles the sub-basin boundary is **kept**, so it has a published row
  and `tag_evaluated == TRUE`, but floodplains evaluated `in_fire`/`in_harvest` against the
  clipped fragment only. Meanwhile `ev_patch$area_ha`, `flicker_frac` and `break_frac` all come
  from the **full unclipped** patch (`pat_sv`). Two consequences, both one-directional in the same
  way round 1's finding was: a patch whose harvest overlap lies on the outside of the boundary
  reads `in_harvest = 0` and joins the residual; and its full area is used as the Phase 3 weight
  in `weighted.mean(..., ev_patch$area_ha[k])` even though only part of it was evaluated. The
  script already measures the total trimmed area (`recon`'s `after_sieve_unclipped` →
  `after_zone_clip` delta, surfaced as `clip_ha` at 219–220) but never attributes it per patch.
  Cheapest disclosure: `merge` `published$area_ha` in as `area_ha_clipped` (it is already in
  `pubd` at 617 and dropped at 633) and add a `clip_frac = area_ha_clipped / area_ha` column, so a
  reader can see which rows were only partly evaluated — and count how many are below 1.

- **[fragile]** `disturbance_compare.R:183-185` vs `692-693` — **a patch with `in_fire == 1` and a
  NA `fire_year` is invisible to Phase 0 and Phase 2 but enters Phase 3.** `event_rows()` builds
  `split_by` from `unique(yr[!is.na(yr)])` and every group mask is `!is.na(yr) & yr == ...`, so an
  undated tagged patch appears in no row of `summary_events.csv` and is silently absent from the
  pre-registered sample. `disc_fire` (398) and `offset_rows()` (656) exclude it too — consistently.
  But `pops$fire_touching` / `pops$harvest_touching` test the **flag only**, so it is in the Phase 3
  population. Three tables, two definitions of "fire-tagged", and the count of the difference is
  reported nowhere. The comment at 189–190 shows the author already reasoned about `n_events` being
  uncountable for harvest; the undated-patch case is the same gap on `n_patches`. Either emit a
  `year = NA` row from `event_rows()` (the function already has the 0-row schema for it) or assert
  `sum(sel & is.na(yr)) == 0` so the two definitions cannot part company unnoticed.

---

## Checked and clean

Recording these so the next round does not re-walk them.

- **`tag_evaluated` reaches every consumer that needs it.** `offset_rows()` (655), all three
  `pops` (692–695), and `join_audit`'s `patches_not_tag_evaluated` (568, computed from the same
  set membership). `strata` (686–689) is ungated but is only ever intersected with a gated `pops`,
  so the un-evaluated rows cannot enter a row of `fl_rows`. There is no fourth ungated consumer of
  the unclipped population against clipped tags — the residual exposure is the *trimmed* case
  (finding 5), not an ungated one.
- **`discriminates_v(published$fire_year)` (399) is correct on a Real column with NAs.**
  `as.integer(NA_real_)` is `NA_integer_`, `discriminates()` short-circuits to `NA_character_`,
  which satisfies `vapply`'s `character(1)` template, and `NA %in% c("full","partial")` is `FALSE`.
  A zero-length `fire_year` gives `character(0)` and the whole chain degrades to a 0-row
  `disc_fire` and `n_fire_events_disc == 0`. `is_sustained()` and `discriminates()` were checked
  by hand against 2016–2024: `{2019..2022}` sustained, `2018`/`2022` partial, `2017`/`2023`/
  out-of-range `none` — matches the table at 93–97.
- **`break_frac_area_wtd` (663-667) divides by the right denominator.** The numerator
  `sum(break_frac * area_ha)` and the denominator `sum(area_ha)` are aggregated in the same call
  over the same group, and `a$area_ha <- round(a$area_ha, 1)` at 670 happens **after** the
  division, so the weight is unrounded. `break_frac` cannot be NA in this subset: `q` is filtered
  on `!is.na(break_year_modal)`, a non-NA `break_year` implies `n_flips == 1`
  (`dft_rast_break_class.R` docs), which implies `n_valid >= 1`, which is the `ifelse` guard at
  612. So no NA can leak into the numerator while the denominator stays finite.
- **`merge(recon, cls, by = "group", sort = FALSE)` (232) is safe.** The row order is formally
  unspecified, but every column of the result is row-wise on `group` and no other frame is
  positionally aligned against `recon` (`ev`, `agree`, `flick` each carry their own `group`
  column). The real issue in that block is finding 4, not the ordering.
- **`terra::crosstab` types** — measured numeric, see the top of this file. `useNA = TRUE`
  returns the NA row and only observed combinations; `ct_by`/`ct_nf` drop `is.na(patch_id)` at
  543–544 before use.
- **`per_patch_delta` (555) is not circular.** `pat_sv$area_ha` is `st_area()` of the polygon
  (`dft_transition_vectors.R:155`), independent of the `rasterize` → `crosstab` cell count it is
  compared against.
- **`patch_id` join validity.** `pat_sv` and `pat_cl` are the same call differing only in `zones`,
  and `seq_len()` precedes both the area filter and the intersection, so the ids are identical.
  `pat_unsv` comes from a different raster and is only ever counted, never joined.
- **`aggregate(cbind(in_fire, in_harvest) ~ patch_id, ..., na.action = na.pass)` (628-630)** —
  `aggregate.formula` splits the `cbind` matrix into separate columns before applying `FUN`, so
  `any(v == 1, na.rm = TRUE)` sees one flag at a time; `na.pass` keeps the NA rows the round-1
  finding was about. `merge(flags, firstrow, all.x = TRUE)` (633) cannot duplicate rows — both
  sides are unique on `patch_id`.
- **`agg_cells()` empty guard (580-589)** correctly returns a typed 0-row frame rather than
  hitting `aggregate`'s "no rows to aggregate"; the downstream `all.x` merge plus the fill at 610
  turns it into a 0.
- **`unlink_tif()` (138-142)** — `nzchar`/`is.na` filter plus the `length()` guard covers the
  `paste0(character(0), ".aux.xml")` → `".aux.xml"` trap. `withr::defer(envir = globalenv())`
  evaluates `unlink_tif(tmp_tifs)` lazily, so the `tmp_tifs <- c(tmp_tifs, ...)` at 531 is seen.
  `terra::sources(pid_r)` returns a real path because `filename =` was passed.
- **Runner `$!` and the RSS trace.** `Rscript ... &` is started alone on its own line with every
  `mkdir`/`: >` above it, so `pid=$!` is the R process, not a wrapper shell. `ps -o rss=` is KiB
  on both BSD and GNU and `$1/1024/1024` is GiB. The `[ -n "$peak" ]` default covers the
  empty-`rss.txt` case. `wait "$pid"` after the `kill -0` loop can return 127 if bash has already
  dropped the job from its table, but `rc` is only ever printed — the OK/FAIL decision is on the
  in-band `ALL STAGES DONE` marker, and `timings.csv` is written (730-732) before that marker is
  emitted, so the `grep 'wall'` in the OK branch cannot race it. The loop accumulates `fails` and
  `exit "$fails"` rather than reporting the last item's status.

---

Path: `/Users/airvine/Projects/repo/drift/planning/active/review-round2.md`

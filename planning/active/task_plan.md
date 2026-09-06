# Task: Corroborate the temporal QA against dated disturbance, and reconcile BULK tree-loss totals with floodplains (#67)

#62 established the temporal composition of published change across four watershed groups. Every
leg of that assessment is internal to the imagery — it describes whether labels settled, and cannot
assign cause. `floodplains` already tags transition patches with dated provincial disturbance
layers; joining the two gives the first external check available on the temporal method. Two
independently derived totals for BULK tree loss are also in the way, and #66 is blocked on them.

**Plan revised after a Plan review that landed post-approval.** Four findings, each verified against
the code and the published data before being folded in, are marked **[R]**. They changed the join
method (column join, not rasterize), the claimable scope of Phase 2 (only 2019–2022 discriminates),
and the framing of Phase 3 (touching, not containment). See `findings.md`.

## Phase 0: Discharge the snapshot, pre-register the sample

- [ ] Record every verified point in `findings.md` with the command that produced it
- [ ] Write `summary_events.csv` FIRST: tagged patches and area by (group x source x year), with the
      2019–2022 discriminating subset called out and distinct `fire_number` counted — committed
      before any agreement number exists, so a null is a result and not a rewrite
- [ ] Edit the #67 body in place: discharge the "verify before relying" caveat, correct the
      1,565.1 ha line (it is `from_class = 'Trees'` and includes Trees -> Water), add the tag counts
      and the discriminating-window table, state that no database is needed

## Phase 1: Reconcile 4,625.0 ha against 3,627.2 ha (blocking for #66, gates Phase 2)

- [ ] `dft_rast_transition(patch_area_min = 10000)` on the published COGs; record cells and area
      removed by the class-agnostic sieve (`R/dft_rast_transition.R:113-114`)
- [ ] `dft_transition_vectors(changes_only = TRUE)` — same-valued components (`:115`), so a
      surviving mixed blob re-splits; count and area move in OPPOSITE directions
- [ ] Zone clip: area lost outside the sub-basin; assert zero split rows (one basin each)
- [ ] Patches dropped entirely by the clip — predicted by `max(patch_id) - n` (bulk: 30)
- [ ] Degenerate/zero-area rows: `st_geometry_type()` table and zero-area count
- [ ] Compare on feature count, total ha, AND the per-transition-class table (53 rows for BULK)
- [ ] Assert `dft_rast_break_class()$raster` differs from the sieved raster only by the sieve mask
- [ ] Quantify `subbasins.gpkg` against the published `ff04` polygon (gitignored-input dependency)
- [ ] `summary_reconcile.csv`: one row per mechanism, Δcount and Δha, summing exactly

## Phase 2: `break_year` against the disturbance date

- [ ] **[R]** Vectorize the sieved, UNCLIPPED raster so polygon boundaries lie on cell edges, and
      join the published attributes by `patch_id` — `R/dft_transition_vectors.R:153` assigns it
      globally BEFORE the zone intersection at `:171`, so it is drift's own key
- [ ] Fallback `dft_transition_attribute(match_mode = "largest")` if the ids do not reproduce
- [ ] **[R]** `terra::crosstab(long = TRUE, useNA = TRUE)`, NOT `zonal()` — terra's zonal fast path
      is only `{mean,min,max,sum,notNA,isNA}`; anything else falls back to a full-grid
      `as.data.frame()` (169M–204M rows here)
- [ ] `join_audit.csv` as committed evidence: zero-cell patches (target 0), `sum(cells) * cell_ha`
      against `sum(area_ha)` (target exact), duplicate-`patch_id` count
- [ ] **[R]** Restrict to the 2019–2022 discriminating window; report 2018/2023 separately, labelled
      structurally endpoint-only. State each exclusion count by reason
- [ ] Report the FULL offset distribution by count and area, per group and pooled, with lag {0, +1}
      pre-registered as agreement
- [ ] Frame to the sample: fire is 3 events in one group (case series, no rate, no p-value);
      harvest is 225 patches / 858 ha with no event id

## Phase 3: Flicker in harvest-touching patches against the untagged residual

- [ ] Flicker fraction per patch from the `n_flips` crosstab, defined as
      `n(n_flips >= 2) / n(non-NA n_flips)`, NA cell count published beside it
- [ ] Compare harvest-touching against `!in_fire & !in_harvest` — flags are additive, never subtract
- [ ] **[R]** Stratify on the #44 signature (`flag_sliver`, `area_ha >= 0.5`): change concentrates at
      cutblock edges and slivers flicker more, so an unstratified result is confounded by shape
- [ ] **[R]** State the control-group limitation: cutblocks are loaded filtered
      `HARVEST_START_YEAR_CALENDAR >= 2017`, so pre-2017 cutblocks are ABSENT from the database and
      sit in the untagged residual — the succession signal is in the control group
- [ ] Say "touching a cutblock", never "inside" — `in_harvest` is `st_intersects` with no published
      overlap fraction

## Phase 4: Carry the findings out

- [ ] `summarize` stage assembles `summary_groups.csv` / `.md`, refusing to finish if the note's
      copy differs
- [ ] Section in `inst/notes/temporal-qa-groups.md`, tables generated not hand-typed
- [ ] Carry anything changing a published figure's description into #66 and the #67 body
- [ ] File separately: `dft_rast_transition()` passes no `filename =` to `patches()` / `subst()` /
      `ifel()` (`R/dft_rast_transition.R:113-125`) — 6–7 full-grid rasters held
- [ ] Settle and record whether the work belongs here or in floodplains

## Validation

- [ ] `bash data-raw/disturbance_compare-run.sh bulk necr lnth kotl` — every group `OK` on its own
      `ALL STAGES DONE` marker, peak RSS recorded
- [ ] `Rscript data-raw/disturbance_compare.R summarize` reproduces the committed tables
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

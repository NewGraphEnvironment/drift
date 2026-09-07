# drift#67 — Compare the temporal QA against dated disturbance (2026-09-06)

#62 measured the temporal composition of published land-cover change on four watershed groups,
but every leg of that assessment is internal to the imagery — it says whether labels settled,
never whether anything happened on the ground. This issue asked whether `floodplains`' dated
fire and harvest tags corroborate `dft_rast_break_class()`'s `break_year`, and reconciled two
conflicting BULK totals that were blocking #66.

**Outcome: all three questions answered, and the reconciliation is exact.** The published
`transition_vector.gpkg` and drift's own change patches were never in conflict — the published
layer is drift's output after a 1 ha class-agnostic sieve and a sub-basin clip, reproduced
exactly in all four groups with 0 of 53/44/41/46 transition classes differing. `break_year`
agrees with the disturbance date at lag 0 or +1 for 86.2% of discriminating fire patches that
broke and 72.0% of harvest, with the mode at +1 — the annual-composite lag pre-registered
before the distribution was seen. Flicker is markedly *lower* in disturbed patches, which does
**not** support the succession reading and argues for reading flicker as classifier noise.

Verifying the issue's own snapshot changed the shape of the work before any code was written:
the tags are already published so no database is needed; `patch_id` is drift's own global key
so the join is a column join; `in_fire` is `st_intersects`, so the claim is "touching", not
"inside".

Landed in `main` via PR (see below). Delivered `data-raw/disturbance_compare.R` + `-run.sh`,
the committed evidence under `data-raw/logs/disturbance_compare/`, and
`inst/notes/temporal-qa-disturbance.md`. Findings that change how a published figure should be
described were carried into #66 before its article is written. Follow-up #69 filed for
`dft_rast_transition()`'s unfilenamed sieve intermediates.

## Measurement

- **Reconciliation (Q1), the strongest result — a reproduction, not a correlation.** BULK
  21,701 patches / 4,625.0 ha → 7,191 / 3,639.7 (1 ha sieve) → 7,161 / 3,627.2 (sub-basin clip),
  against a published 7,161 / 3,627.2. Max |Δha| 0.00 in every group. The clip is not uniformly
  small: 12.5 ha on bulk against 130.5 ha on kotl. This closed the "one fact derived twice"
  problem blocking #66 and changed how the published figure must be described.
- **`gross_loss_ha` includes Trees → Water.** The published 1,565.1 ha on BULK is
  `from_class = 'Trees'`; excluding Trees → Water it is 1,428.2 ha. Carried into #66.
- **Agreement (Q2).** Fire 150 tagged / 123 broke / 106 at lag {0,+1} = 86.2%; harvest 308 / 250
  / 180 = 72.0%. Both denominators published because the rate is conditioned on its own outcome.
  Fire is five events across two groups — a case series supporting no rate and no p-value.
- **Flicker (Q3).** Harvest-touching against untagged residual, `wider` stratum: 0.205 / 0.450
  (bulk), 0.279 / 0.412 (necr), 0.068 / 0.475 (lnth), 0.072 / 0.440 (kotl).
- **Run cost.** Peak RSS 13.7–17.3 GiB, wall 162–654 s, grids 56M–204M cells.

## Wrong turns, kept because they are the evidence of how this was arrived at

- **The discriminating window was wrong in both directions.** A plan review said "only 2019–2022
  discriminates" and it was taken as a flat window. A disturbance in year `Y` reaches
  `break_year` `Y` or `Y+1`, so 2018 and 2022 are *partial* and 2019–2021 *full*. The flat window
  excluded 2018 — which holds the largest fire signal in the dataset, necr's 2018 fires putting
  414.7 ha at `break_year` 2019 — and called 2022 full. **Caught by reading the output, not by
  review**, when a 2018 fire showed 33 patches at offset +1 in a year labelled non-discriminating.
  All four groups were re-run so the committed evidence is internally consistent.
- **The first join design would have manufactured Q3's result.** Rasterizing the published
  polygons onto the break grid drops sub-cell fragments — a perimeter-to-area loss concentrated
  in slivers, which are the high-flicker population. Replaced with a `patch_id` column join once
  `dft_transition_vectors()` was read closely enough to see the id is assigned *before* the zone
  clip.
- **Five code-check rounds, 31 findings**, each of rounds 2–5 finding a defect inside the
  previous round's fix. The mechanism: every derived number was computed from whichever frame was
  nearest, and the frames differ in population (unclipped / clipped / evaluated / broke) or
  precision. At its worst `area_ha` carried three populations across four CSVs. The material bug:
  patches the zone clip dropped were forced into Phase 3's control group — 219 on kotl against
  30/18/9 elsewhere, one-directional and area-weighted. Terminated by enumerating every derived
  column against its population and precision, not by a quiet round.
- **A comment claimed an assertion that did not exist** ("Asserted below against the sieved
  raster's class table"); there was no such check and `rm(trans)` ran before `res` existed.
- **The guard against mixing script versions stamped the wrong version** — `script_sha` was
  computed at the end of the run, so a mid-run edit stamped the post-edit sha onto CSVs the
  pre-edit code produced. That is the guard failing toward pass, on the guard that exists to stop
  exactly that, and it was live in this session because the file *was* edited mid-run repeatedly.

## Evidence

`data-raw/logs/disturbance_compare/` — per-group CSVs, `rss.txt` traces, and the assembled
tables the note quotes verbatim. `inst/notes/temporal-qa-disturbance.md` is the write-up; its
tables are generated and the `summarize` stage refuses to finish if the note's copy differs
(proven to fire on a one-digit mutation, and the script-version guard proven to fire on a
mutated `script_sha`).

`review-round1.md` … `review-round5.md` are the code-check rounds, including the enumeration
that terminated them.

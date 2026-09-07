# Review round 4 — data-raw/disturbance_compare.R (+ -run.sh)

Reviewed the full file on disk (848 lines) plus `disturbance_compare-run.sh`, and measured
against the completed outputs in `data-raw/logs/disturbance_compare/{kotl,lnth}` (bulk and
necr were mid-run).

**Verdict: the class is NOT closed.** Round 3's ten fixes all hold — I verified each of the
four specific questions empirically and every one is correct. But the enumeration below finds
the same mechanism alive on three further axes, two of which are *live right now* on disk.

---

## Round 3's fixes — verified

Each checked by running the exact expression, not by reading.

**(a) `rd()` attaching `group` to every read — clean, no caller breaks.**

| caller | file | has a `group` column already? | effect |
|---|---|---|---|
| `r` (L219) | `summary_reconcile.csv` | no | column added, only `r$step`/`n_patches`/`area_ha` read |
| `c2` (L239) | `summary_class_compare.csv` | no | column added, only `nrow`/`d_n`/`d_ha` read |
| `gm2` (L240), `gm` (L252) | `group_meta.csv` | **yes** | `x$group <- rep(g, nrow(x))` **overwrites in place with the identical value** — `names()` and `nrow()` unchanged (verified: both group_meta files carry `group` as column 1 and the value is `g`) |
| `events` (L248) | `summary_events.csv` | no | column added, then rbind across groups |
| `off` (L275) | `summary_break_offset.csv` | no | as above |
| `flick` (L304) | `summary_flicker_strata.csv` | no | as above |

The 0-row path is also safe. `write.csv` of a 0-row frame writes a header only; `read.csv` of
that returns 0 rows with **every column typed `logical`**; `rep(g, 0)` is `character(0)`; and
`rbind(<0-row all-logical frame>, <typed frame>)` returns the typed frame with correct classes
(measured). So an all-`none` group cannot break the assembly.

**(b) `addNA(factor(q$offset))` round trip — correct.** Measured on `c(0L, 1L, NA, -3L, 10L)`:
`factor()` orders levels numerically (`"-3" "0" "1" "10"`), `addNA` appends the `NA` level,
`as.character` returns `NA_character_` for it, and `as.integer` returns `NA_integer_` with no
warning. `aggregate(by = list(..., addNA(...)))` **keeps** the NA group (control without
`addNA` drops it, confirming the guard is load-bearing) and emits only observed combinations,
not the full cross product.

**`q$break_frac[is.na(q$break_frac)] <- 0` does NOT corrupt `break_frac_area_wtd`.** The fill is
value-neutral in the numerator, provably: `break_year` is non-`NA` iff `n_flips == 1`, so
`offset` is `NA` ⟺ no cell has `n_flips == 1` ⟺ `n_break == 0` ⟺ `break_frac == 0` whenever
`n_valid > 0`. Confirmed on lnth — both `offset = NA` rows carry `break_frac_area_wtd = 0`.
Its *only* effect is admitting `n_valid == 0` patches to the **denominator**, which is R4-3.

**(c) The summarize `stale` clear is correctly placed.** It sits at L311–318, after `recon`,
`cls`, `events`, `ev`, `agree` and `flick` are all constructed (L218–304) — so R3-1's class of
crash fires before anything is deleted. Everything after the clear that can fail (`kable`, the
note guard) leaves `summary_groups.csv` absent, so the marker invariant holds in every branch.
One behavioural consequence is R4-6.

**(d) `trimmed_ha` is correct.** With `tag_evaluated & is.na(area_ha_eval)` now a hard `stop()`,
neither term can be `NA`. Untrimmed patches contribute a float difference of order 1e-15 each
(both `area_ha` and the published `area_ha` are `st_area()` on the same geometry). lnth reports
4 trimmed patches / 2.91 ha, and `max_abs_patch_ha_delta` at 1.49e-10 corroborates the scale.

---

## Findings

### R4-1 — MEDIUM — L829–843 (`group_meta.csv`) + L202–206 (`summarize` gate): nothing identifies the *script version*, so `summarize` can assemble a note that mixes two definitions of the same measurand. Live on disk right now.

The per-group marker invariant is stated as *"meta present ⇒ every CSV beside it came from the
same run"* (L369–370). That is true and it is per-group. `summarize` then gates only on the
**presence** of four `group_meta.csv` files (L203) and rbinds their siblings. Nothing asserts the
four groups came from the same *script*.

`group_meta.csv` records `date` (day resolution), `running_drift_version` and `terra` — none of
which move when this script's definitions change. Measured just now:

```
kotl : group,item,crs,...,join_zero_cell_patches,date,terra   date= 2026-09-06
lnth : group,item,crs,...,join_zero_cell_patches,date,terra   date= 2026-09-06
```

**Identical column sets, identical date** — and yet kotl's outputs predate round 3 while lnth's
postdate it:

```
kotl/summary_break_offset.csv   : source,disturbance_year,offset,n_patches,area_ha,break_frac_area_wtd,discriminating
lnth/summary_break_offset.csv   : source,disturbance_year,offset,n_patches,area_ha_unclipped,break_frac_area_wtd,discriminating
kotl/summary_flicker_strata.csv : stratum,population,n_patches,area_ha,flicker_frac_area_wtd,break_frac_area_wtd
lnth/summary_flicker_strata.csv : stratum,population,n_patches,area_ha_unclipped,area_ha_eval,flicker_frac_area_wtd,break_frac_area_wtd
```

kotl has 29 offset rows and **0** with `offset = NA` (pre-R3-5, filtered on `break_year_modal`);
lnth has 14 rows, 2 of them `NA` (post-R3-5). So kotl's `n_tagged` would be `n_with_break`, and
kotl's `break_frac_area_wtd` in the flicker table is weighted by the **clipped** area while
lnth's is weighted by the **unclipped** area — round 3's central correction.

This time `summarize` fails loudly, and only by luck: I ran the rbind it would perform and got
`ERROR: names do not match previous names`. That error is a **side effect of a column rename**,
not a guard. Round 3 changed a definition *and* a name together; a future round that changes a
definition and keeps the name (round 3 itself considered exactly that for
`break_frac_area_wtd`, whose name is unchanged in the flicker table) assembles
`summary_groups.md` from two definitions, writes the marker, and reports success. The note's Q3
conclusion leans explicitly on cross-group comparability (L692–693), which is the property this
gate does not check.

Fix: stamp an identity into `group_meta.csv` and assert it is uniform —

```r
script_sha = substr(digest::digest(file = "data-raw/disturbance_compare.R", algo = "sha256"), 1, 12),
run_started = format(t0, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),   # `date` is day-resolution
```
```r
shas <- vapply(have, function(g) rd(g, "group_meta.csv")[["script_sha"]], character(1))
if (length(unique(shas)) != 1L) stop("groups were produced by different script versions: ",
                                     paste(sprintf("%s=%s", have, shas), collapse = ", "))
```

Note the stopifnots at L241/L255 are the right shape but guard *column presence*, which is what
a rename moves — not what a redefinition moves.

---

### R4-2 — MEDIUM — L512: the comment claims an assertion that does not exist and, given L507, cannot exist. The `unsieved_vectorize` row rests on an unchecked premise the reconciliation arithmetic structurally cannot detect.

```r
507  rm(trans); invisible(gc(verbose = FALSE))
...
510  # dft_rast_break_class()$raster is documented identical to
511  # dft_rast_transition(x, from = first, to = last)$raster, so this is the unsieved transition
512  # and costs no extra pass. Asserted below against the sieved raster's class table.
514  res <- dft_rast_break_class(classified)
```

`grep -n "cats\|levels\|identical\|compareGeom\|stopifnot"` over the whole file returns no such
assertion, and `trans` — the only thing it could compare against — is removed **seven lines
before** `res` exists. So the sentence is false and the premise is untested.

Why it matters rather than being a stray comment:

- `pat_unsv` (L518) is vectorized from `res$raster` and supplies the entire
  `unsieved_vectorize` row of `summary_reconcile.csv` — the "21,701 patches / 4,625.0 ha" the
  header quotes and the top of the chain the note's Q1 reads.
- `sieve_ha` in `summary_reconcile_groups.csv` is `unsieved_vectorize − after_sieve_unclipped`,
  i.e. a difference between a `break_class` product and a `rast_transition` product.
- That difference is **expected to be large and non-zero** (it *is* the sieve), so a divergence
  in NA handling or class encoding between the two rasters is absorbed into it silently. The
  deltas still "sum exactly" (they are diffs of one column), so the file's own arithmetic
  cannot fail. This is the proxy-vs-property shape: the only observation of the premise is a
  quantity that is non-zero either way.

Also note `pid_r` is rasterized onto `res$raster` (L577) while `pat_sv` was derived from
`trans$raster` — safe in practice (both descend from `ref`), but again unasserted.

Fix — assert what the comment says, **before** the `rm`:

```r
res <- dft_rast_break_class(classified)
stopifnot(terra::compareGeom(trans$raster, res$raster, stopOnError = FALSE),
          identical(terra::cats(trans$raster)[[1]], terra::cats(res$raster)[[1]]))
rm(trans); invisible(gc(verbose = FALSE))
```

(If holding both grids at once is unacceptable at BULK scale, capture
`terra::cats(trans$raster)[[1]]` and the geometry into small objects before the `rm` and compare
against those. What must not stand is the comment claiming a check that is absent.)

---

### R4-3 — LOW/MEDIUM — L660–661 / L758 / L809: `n_valid == 0` is a third state. It is admitted to `summary_break_offset.csv`'s denominators, excluded from every `summary_flicker_strata.csv` population, and counted in no audit row — so `n_patches`, `area_ha_unclipped` and `break_frac_area_wtd` name two populations across the two files.

`flicker_frac` and `break_frac` are `NA` on exactly the same set — `n_valid == 0`, a patch whose
every cell has `n_flips = NA` (an interior year is `NA` over the whole patch). Then:

- **`offset_rows()` keeps it.** `q$break_frac[is.na(q$break_frac)] <- 0` (L758) makes it a
  contributing row, so it enters `n_patches` and `area_ha_unclipped` in
  `summary_break_offset.csv`, and hence `n_tagged` / `n_with_break` in
  `summary_agreement_groups.csv`.
- **Phase 3 drops it.** `k <- strata[[s]] & pops[[p]] & !is.na(ev_patch$flicker_frac)` (L809) —
  so it never enters `n_patches`, `area_ha_unclipped` or `area_ha_eval` in
  `summary_flicker_strata.csv`.
- **Nothing counts it.** `join_audit.csv` has a row for every *other* exclusion —
  `patches_zero_cells`, `patches_not_tag_evaluated`, `patches_trimmed_by_clip`,
  `fire_flag_without_year` — and none for this one.

This is R3-2's third state one axis over: there the silent-exclusion case was made a `stop()`;
here it is silently included on one side and silently excluded on the other, under identical
column names.

Latent today, measured on both completed groups:

```
kotl  n_valid==0: 0 patches / 0 ha    is.na(flicker_frac): 0    any n_na>0: 0
lnth  n_valid==0: 0 patches / 0 ha    is.na(flicker_frac): 0    any n_na>0: 0
```

Zero on both — but the script's own `agg_cells()` guard (L629–638) exists precisely because
`n_na` is non-zero on some groups, so the population is reachable, and bulk/necr are unmeasured.

Fix — one audit row, and let the fill stay (it is value-neutral, see (b) above):

```r
metric = c(..., "patches_no_valid_flip_cells", "no_valid_flip_ha"),
value  = c(..., sum(ev_patch$n_valid == 0),
                round(sum(ev_patch$area_ha[ev_patch$n_valid == 0]), 2))
```

Or, matching R3-2's standard, make it loud: `if (any(ev_patch$n_valid == 0)) stop(...)` — it is
the same "excluded from one population, included in another, counted nowhere" defect.

---

### R4-4 — LOW — L38–46 / L355: the `ev` table exists only inside `summary_groups.md`; the header's description of `summary_groups.csv` is false, and that file is a byte-copy of `summary_reconcile_groups.csv`.

The header states the CSVs are "the committed evidence record" (L26) and that
`summary_groups.csv / .md` hold "one row per group, **every number the note quotes**" (L40).

`summary_groups.csv` is written from `recon` (L355) — the same object written to
`summary_reconcile_groups.csv` at L319. Identical content, two filenames.

Meanwhile `ev` (L255–273) — `fire_patches_full`, `fire_patches_partial`, `fire_ha_disc`,
`fire_events_disc`, `harv_patches_full`, `harv_patches_partial`, `harv_ha_disc` — is passed to
`kable()` at L331 and **written to no CSV at all**. The note's "Discriminating sample" table,
which is where the Phase 0 pre-registration lands, has no machine-readable artifact behind it.
Anyone re-deriving those numbers has to parse markdown.

Fix: write `ev` to `summary_events_disc_groups.csv` (or make `summary_groups.csv` the merge of
`recon` and `ev` rather than a duplicate of `recon`), and correct L40 either way.

---

### R4-5 — LOW — L191 vs L447: two counts of "distinct fires" with different `NA` handling, in the same document.

```r
191  n_events = if (is.null(id_col)) NA_integer_ else length(unique(q[[id_col]][k])),
447  n_fire_events_disc <- length(unique(disc_fire$fire_number[!is.na(disc_fire$fire_number)]))
```

`length(unique(x))` counts `NA` as one distinct value. So a discriminating year in which every
fire-tagged patch carries a `fire_year` but no `fire_number` reports `n_events = 1` — for zero
identified fires — while `n_fire_events_disc` correctly reports 0. Both appear in
`summary_groups.md` (as `n_events` in the events table and `fire_events_disc` in the
discriminating-sample table). This inverts the reasoning in the comment two lines above L191,
which chose `NA` over `0` for harvest specifically so a count would not read as "no events".

`join_audit.csv` counts `fire_flag_without_year` but has no `fire_flag_without_number` row, so
the condition is also invisible.

Latent: kotl's 91 fire-flagged patches have 0 `NA` fire_numbers and 0 `NA` fire_years; lnth has
no fire patches. Fix is one filter — `length(unique(na.omit(q[[id_col]][k])))` — plus the audit
row.

---

### R4-6 — LOW — L346–355: the *ordinary* `summarize` failure path deletes the git-tracked `summary_groups.csv` and the error does not say so.

The note guard (L349) fires whenever `inst/notes/temporal-qa-disturbance.md` has not yet been
rebuilt — which is the expected state on any run where the numbers moved, i.e. the common case.
By then L316 has already removed `summary_groups.csv` and L355 has not run. The marker semantics
are right (absent marker ⇒ incomplete), but the operator is left with a deleted tracked file and
an error message that talks only about the note.

Fix: add one clause to the message — `"; summary_groups.csv was cleared and not rewritten — "
"re-run summarize after updating the note, or git checkout it"`.

---

## Enumeration: every derived column, its population and its precision

Populations: **PUB** = published rows (clipped, one row per fragment) · **SV** = `pat_sv`
patches (sieved, unclipped) · **CL** = `pat_cl` (sieved, clipped, area from geometry) ·
**UNSV** = `pat_unsv` (unsieved) · **EVAL** = SV ∩ PUB (`tag_evaluated`) ·
**VALID** = `n_valid > 0`.

### `summary_events.csv`
| column | population | precision | name agrees? |
|---|---|---|---|
| `year` | PUB, flag==1, year non-NA | int | ✓ |
| `n_patches` | **PUB rows** | exact | ⚠ *counts published rows, not patches* — same name used for **SV** patches in `summary_break_offset.csv` |
| `area_ha` | PUB (clipped) | round 1 | ⚠ unqualified `area_ha`; every other file now qualifies (`_unclipped` / `_eval`) |
| `n_events` | PUB rows | exact | ⚠ **R4-5** — counts `NA` as an event |
| `discriminating` | f(year) | — | ✓ |

### `summary_reconcile.csv`
| column | population | precision | name agrees? |
|---|---|---|---|
| `n_patches` / `area_ha` | UNSV / SV / CL / PUB, one per row | round 1 | ✓ — `step` + `mechanism` name the population per row |
| `d_n` / `d_ha` | diffs of the above | diff of rounded | ✓ consistent with `sieve_ha`/`clip_ha`, which are the same diffs |

### `summary_class_compare.csv`
| column | population | precision | name agrees? |
|---|---|---|---|
| `n_repro` / `ha_repro` | CL | raw / round 2 on `d_ha` | ✓ |
| `n_pub` / `ha_pub` | PUB | raw | ✓ |
| `d_n` / `d_ha` | CL − PUB | round 2 | ✓ |

### `join_audit.csv`
| row | population | name agrees? |
|---|---|---|
| `patches_in`, `patches_with_cells`, `patches_zero_cells`, `cells_total`, `area_from_cells_ha`, `area_from_geometry_ha` | SV | ✓ |
| `max_abs_patch_ha_delta` | SV ∩ has-cells (inner merge) | ✓ — the excluded set is `patches_zero_cells` |
| `published_patch_ids_matched` / `_unmatched` | PUB | ✓ |
| `patches_not_tag_evaluated` | SV \ PUB | ✓ |
| `patches_trimmed_by_clip` / `trimmed_ha` | EVAL | ✓ — **no NA reachable** since L710 stops |
| `fire_flag_without_year` / `harvest_flag_without_year` | PUB rows | ✓ |
| *(absent)* | **VALID complement** | ✗ **R4-3** |
| *(absent)* | flag-without-`fire_number` | ✗ **R4-5** |

### `summary_patch_join.csv`
| column | population | name agrees? |
|---|---|---|
| `area_ha` | SV (unclipped) | ⚠ unqualified, but it is the per-patch source file and `area_ha_eval` sits beside it |
| `area_ha_eval` | EVAL (published, clipped) | ✓ |
| `flicker_frac`, `break_frac` | SV cells, denominator `n_valid` | ✓ (`n_valid`, `n_na` published beside) |
| `tag_evaluated` | SV ∈ PUB | ✓ |

### `summary_break_offset.csv`
| column | population | precision | name agrees? |
|---|---|---|---|
| `offset` | EVAL ∧ flag ∧ year non-NA | int, NA survives `addNA` | ✓ |
| `n_patches` | **EVAL patches** (⊂ SV) | exact | ⚠ same name as PUB-row count in `summary_events.csv`; and ⊃ the flicker file's by **R4-3** |
| `area_ha_unclipped` | same, weight = SV area | round 1 | ✓ name, ⚠ population per **R4-3** |
| `break_frac_area_wtd` | measurand SV cells, weight SV area, `NA`→0 | round 3 | ✓ name, ⚠ population per **R4-3** |
| `discriminating` | f(disturbance_year) | — | ✓ |

### `summary_flicker_strata.csv`
| column | population | precision | name agrees? |
|---|---|---|---|
| `n_patches` | EVAL ∧ pop ∧ stratum ∧ **VALID** | exact | ⚠ differs from the offset file's by **R4-3** |
| `area_ha_unclipped` | SV area over that set | round 1 | ✓ name |
| `area_ha_eval` | published area over that set | round 1 | ✓ name |
| `flicker_frac_area_wtd` | measurand SV cells, weight SV area | round 3 | ✓ — R3-3/4/10 closed: measurand, weight and `ge_0.5_ha` threshold are all unclipped |
| `break_frac_area_wtd` | as above | round 3 | ✓ name, ⚠ **VALID** vs the offset file per **R4-3** |

### summarize outputs
| column | source | name agrees? |
|---|---|---|
| `drift_*`, `pub_*`, `repro_*`, `sieve_ha`, `clip_ha` | `summary_reconcile.csv`, rounded values only | ✓ — consistent with that file's own `d_ha` |
| `reproduced` | read back from `group_meta.csv`, **not re-derived** | ✓ |
| `n_classes`, `n_classes_differ`, `max_abs_d_ha` | `summary_class_compare.csv` | ✓ |
| `fire_patches_full/partial`, `*_ha_disc` | `summary_events.csv` (**PUB rows**) | ⚠ sits one table above `n_tagged` (**EVAL patches**) in the same `.md`; different names, different populations, nothing reconciles them |
| `fire_events_disc` | `group_meta.csv` distinct count | ✓ |
| `n_tagged`, `n_with_break`, `n_lag01`, `pct_lag01_of_break`, `pct_lag01_of_tagged` | all from `summary_break_offset.csv` | ✓ — R3-5 closed; one population, both denominators published |
| `summary_groups.csv` contents | copy of `recon` | ✗ **R4-4** — header says "every number the note quotes" |
| `ev` table | markdown only | ✗ **R4-4** |

---

## `disturbance_compare-run.sh` — clean

- `Rscript ... &` is started **alone**, so `$!` is the R process — the drift#62 wrong-PID trap
  is correctly avoided, and the comment says why.
- Gates on the in-band `ALL STAGES DONE` marker, not the exit status.
- `[ -n "$peak" ] || peak="n/a"` covers the empty-`rss.txt` path.
- `set -uo pipefail` without `-e` is right for a loop that counts its own failures;
  `fails` is accumulated per item, so the wrapper's exit reflects the items, not the last one.
- `grep 'wall' "$d/timings.csv"` is only reached on the marker-present branch, and `timings.csv`
  is written before the marker is printed, so it cannot read a missing file.

No findings.

---

## Summary

| id | severity | location | class |
|---|---|---|---|
| R4-1 | MEDIUM | L829–843 / L202–206 | no script identity in the marker; mixed-definition assembly. **Live on disk now** |
| R4-2 | MEDIUM | L512 (with L507) | a rule stated in a comment is not an enforced rule; the arithmetic cannot detect the divergence |
| R4-3 | LOW/MED | L660–661 / L758 / L809 | `n_valid == 0` third state: in one file's denominators, out of the other's, counted nowhere |
| R4-4 | LOW | L38–46 / L355 | `ev` has no CSV; `summary_groups.csv` duplicates `summary_reconcile_groups.csv` and the header misdescribes it |
| R4-5 | LOW | L191 vs L447 | two "distinct fires" counts with different `NA` handling |
| R4-6 | LOW | L346–355 | the ordinary failure path deletes a tracked file without saying so |

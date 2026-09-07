# Review round 5 — `data-raw/disturbance_compare.R` (+ `-run.sh`)

Reviewed the file on disk (911 lines) plus `cc_diff5.txt`, `disturbance_compare-run.sh`,
`R/dft_rast_transition.R`, `R/dft_rast_break_class.R`, and the on-disk artifacts of the
completed `lnth` run. Every claim below is measured; the probe outputs are quoted inline.

---

## Part 1 — round 4's fixes, audited on the axis one over

### (a) `script_sha` — the mechanics are fine, the PLACEMENT is not

Measured (digest 0.6.39):

```
digest(file = <path>, algo = "sha256")   ==  digest(<path>, algo = "sha256", file = TRUE)   TRUE
digest(file = "no/such/file.R", ...)     ->  Error: The file does not exist: no/such/file.R
digest(file = <symlink>)                 ->  hashes the TARGET's bytes, same digest
```

So the three sub-questions asked resolve clean:

- `file =` with `object` missing is a supported form — digest carries an explicit
  `if (is.character(file) && missing(object))` shim. It is *not* silently hashing the
  logical `TRUE`.
- A path that does not resolve **errors**, loudly, with `errormode = "stop"` (the default).
  It does not return `NULL`/`NA` into the CSV. And it errors at line 891, i.e. *before*
  `group_meta.csv` is written, so the "meta present => every CSV beside it came from the
  same run" invariant survives the failure.
- A symlinked path resolves to the target's content, so a symlinked checkout produces the
  same sha, not a different one.
- The relative path is also safe from a wrong cwd: `pkgload::load_all(".")` at line 79
  already refuses to run outside a package root, and digest then errors loudly rather than
  writing a wrong value.

**What is broken is when it is computed. See R5-1.**

### (b) `stopifnot(all(trans_cats[[2]] %in% terra::cats(res$raster)[[1]][[2]]))` — correct column, correct direction

Both producers set the identical two-column RAT:

```
R/dft_rast_transition.R:158   set.cats(r_trans, layer = 1, value = data.frame(id = codes,          transition = labels))
R/dft_rast_break_class.R:293  set.cats(r_trans, layer = 1, value = data.frame(id = codes_present,  transition = labels))
```

`[[2]]` is the `transition` label column in both. Column index correct.

Direction correct too, and for the reason the comment gives: `dft_rast_transition()` derives
`codes` from `terra::freq(r_trans)` **after** the sieve has already NA'd small patches
(`R/dft_rast_transition.R:132`), while `dft_rast_break_class()` derives `codes_present` from
a crosstab over the unsieved transition. So sieved ⊆ unsieved by construction, and subset is
the only direction that can be asserted. The assertion is non-vacuous — it would fail on a
label the sieved raster has and the unsieved one does not, which is the divergence being
guarded.

Two bounded caveats, neither a defect:

- It compares **labels**, not ids. Here that is equivalent, because both label strings are
  built by the same `paste0(code_lookup[from], " -> ", code_lookup[to])` from the same
  `classified` input, so a label mismatch and an id mismatch are the same event.
- It is vacuously TRUE if `trans_cats` is the empty-RAT branch
  (`R/dft_rast_transition.R:141`, `id = integer(0)`), since `all(character(0) %in% x)` is
  `TRUE`. That branch implies zero transitions, which the `nrow(published) > 0` and
  reconciliation assertions already make unreachable. Not worth a guard.

`res_geom`/`trans_geom` is `identical()` on doubles — exact, non-vacuous, and correctly
captured before `rm(trans)`. Clean.

### (c) `run_started` with `%OS3` under a non-UTC `TZ` — correct, and TZ-invariant

Measured, one `POSIXct` formatted under three machine zones:

```
TZ=America/Vancouver  -> 2026-09-06T19:34:56.789Z
TZ=UTC                -> 2026-09-06T19:34:56.789Z
TZ=Asia/Tokyo         -> 2026-09-06T19:34:56.789Z
```

`format.POSIXct(x, tz = "UTC")` renders the instant in UTC regardless of the machine zone,
`%OS3` takes its 3 digits from the format string rather than `getOption("digits.secs")`, and
the trailing `Z` is a literal (not `%Z`), which is honest because the rendering *is* UTC.
The live artifact agrees: `lnth/group_meta.csv` carries `2026-09-07T00:05:26.880Z` against a
`run_wallclock.txt` start of `2026-09-07T00:05:24Z` — 2.9 s apart, which is the download
short-circuit. Clean.

### (d) the `rd0`/`shas` block vs `have` — ordering is correct

`have` is defined at line 212 and stopped-on at 213-215; `rd0`/`shas` are at 222-231. The
block runs after, and `have` is guaranteed length 4 at that point, so
`length(unique(shas)) != 1L` is a real comparison rather than a `TRUE` over a singleton.
`anyNA(shas)` covers both a meta predating the column and a header-only meta
(`character(0)[1]` is `NA_character_`). Clean.

### Other round-4 fixes, spot-checked against the live `lnth` artifacts

- **R4-3** (`n_valid == 0` third state): `patches_no_valid_flip_cells 0` / `no_valid_flip_ha 0`
  present in `join_audit.csv`. Row exists, populated from `ev_patch` (the P_sv population),
  correct.
- **R4-5** (`na.omit` before `length(unique())`): `fire_flag_without_number 0` present.
- **R4-2**: verified above.
- **R4-4**: `summary_events_disc_groups.csv` is written at line 345 and is in the stale-clear
  list at 334. The `stale[file.exists(stale)]` filter means its current absence on disk (it
  predates the fix) is handled.
- `n_trimmed` / `trimmed_ha` recomputed independently from `summary_patch_join.csv`:
  `n_trimmed = 4`, `trimmed_ha = 2.909`. The script's signed sum equals the
  positive-trims-only sum to 3 dp (no patch has `area_ha_eval > area_ha` beyond ~1e-10 fp
  noise), so the signed form is not hiding a cancellation. Matches `join_audit.csv` exactly.
- `terra::crosstab(long = TRUE, useNA = TRUE)` returns **numeric** columns, not factors
  (measured on a 4x4 fixture: `class pid: numeric  class n_flips: numeric`). So
  `ct_nf$n_flips >= 2` is a real numeric comparison, not the silent `NA` that a factor would
  produce. The `fl`/`br`/`tot` split is sound, and `lnth`'s flicker fractions vary across
  strata (0.068 → 1.0) rather than collapsing to 0, which is the confirming observation.

---

## Findings

- **[high]** `data-raw/disturbance_compare.R:891` — **`script_sha` is computed at the END of
  the run, so a file edited mid-run stamps the post-edit sha and the guard fails toward
  pass. This is live in the run happening right now.**

  `digest(file = "data-raw/disturbance_compare.R")` opens the path fresh at line 891, minutes
  after `t0`. The stamp therefore records the file's state when the run *finished*, not the
  version the run *started with* — while every number in the group's CSVs was produced by the
  version it started with.

  Measured, from the artifacts on disk at review time:

  ```
  script mtime          2026-09-07T00:05:24Z
  current sha12         5e5f59fd67cb

  bulk   start 2026-09-07T00:01:24Z   (no end line — still running)
  lnth   start 2026-09-07T00:05:24Z   end 00:08:07   group_meta script_sha = 5e5f59fd67cb
  necr   start 2026-09-07T00:08:07Z   (running)
  kotl   start 2026-09-06T23:31:26Z   end 23:42:26   (no CSVs on disk)
  ```

  `bulk` was launched **four minutes before the file became `5e5f59fd67cb`**. When it reaches
  line 891 it will hash the file as it is *now* and stamp `5e5f59fd67cb` — byte-identical to
  `lnth`'s and to whatever `necr` stamps. `summarize`'s `length(unique(shas)) != 1L` will then
  find one unique value across all four, accept them, and assemble the note.

  That is precisely the state R4-1 was written to refuse: *"a mid-session edit ... leaves four
  metas that look identical while their siblings carry two different definitions of one
  measurand."* The guard's own placement reproduces its target case.

  I measured whether the mid-run rewrite also changes what *executes*, because that would
  raise the severity further: it does not. A 115 KB script rewritten in place 1 s into a 4 s
  `Sys.sleep()` still printed `ORIGINAL` from a line past the sleep — R reads far enough ahead
  that the running process is isolated. So `bulk` is running the pre-edit code and will stamp
  the post-edit sha. The mismatch is entirely in the stamp, and entirely silent.

  Fix is one hoist, beside `t0` at line 412 (per-group stage, after `summarize` has quit):

  ```r
  t0 <- Sys.time()
  script_sha <- substr(digest::digest(file = "data-raw/disturbance_compare.R",
                                      algo = "sha256"), 1, 12)
  ```

  and `script_sha = script_sha` in `meta`. Then `bulk` stamps the pre-edit sha, `lnth`/`necr`
  stamp the post-edit one, and `summarize` refuses with the message it already has. Correct
  behaviour, and it is the *only* thing that makes the guard able to fire on the run in
  progress.

  Note this also fixes an ordering hazard the current placement has independently: with the
  hash at line 891, a run that dies anywhere in Phases 0-3 leaves no stamp at all, so the
  stamp can only ever describe a completed run's *end state*. Hoisted, it describes the input,
  which is the fact the guard is about.

- **[low]** `data-raw/disturbance_compare.R:227` — `summarize` checks the four stamps against
  **each other**, never against the script it is itself running from. So "run all four groups,
  edit the file, run summarize" passes, and `summary_groups.md` — which is then required to
  appear verbatim in a committed note — is attributed to a tree state that no longer exists.

  Adding `|| !identical(unique(shas), <this file's sha12>)` closes it. I am flagging this
  **low and optional** rather than as a blocker, because it has a real cost the current form
  avoids: the per-group and `summarize` stages live in one file, so a cosmetic edit to the
  `summarize` half would invalidate four still-valid per-group stamps and force ~50 minutes of
  re-runs. That is a genuine tradeoff, not an oversight, and the current scope ("same script
  across groups") is defensible as stated. Recording it so the choice is deliberate rather
  than assumed. Fixing R5-1 is not optional; this is.

Nothing else found. `-run.sh` re-read in full: the `$!`-alone launch, the empty-`rss.txt`
`peak` default, the `ALL STAGES DONE` in-band gate over a truncated `run.log`, and the
`fails` accumulator over the per-item loop are all correct.

---

## Part 2 — termination

### Verdict: **CLOSED** on the population/precision class. R5-1 is not an instance of it.

The class rounds 2-4 kept re-finding was: *two columns meaning "the same thing" computed over
different populations, with nothing in the data naming which*. I enumerated every derived
column in every emitted CSV against its population and its precision. **No column's population
disagrees with its name.** The evidence is the table below.

R5-1 is a different animal and should not be read as the class reopening: it is not a column
computed over the wrong population, it is the *identity stamp* that stops two populations
being mixed **across groups**. It is the guard on the class, not an instance of it.

### Populations

| symbol | definition | lnth |
|---|---|---|
| `P_unsv` | `pat_unsv` — unsieved drift patches | — |
| `P_sv` | `pat_sv` — sieved, **unclipped**; `ev_patch` is 1:1 on this | 2762 |
| `P_sv∩eval` | `P_sv` with a published row (`tag_evaluated`) | 2753 |
| `P_cl` | `pat_cl` — sieved + zone-clipped | — |
| `P_pub` | rows of `published`; unique on `patch_id` in all four groups (measured) | 2753 |

Areas: **`U`** = drift's own `area_ha` = n_cells × cell_area, pre-intersection (unclipped).
**`C`** = published/recomputed geometry area, post-intersection (clipped).

### Enumeration

**`summary_events.csv`** — one population throughout

| column | population | area | precision |
|---|---|---|---|
| `year` | `P_pub` disturbance date | — | int |
| `n_patches` | `P_pub`, flag==1 & year==y | — | int |
| `area_ha` | `P_pub` | **C** | round 1 |
| `n_events` | distinct non-NA `fire_number` in that cell; `NA` for harvest | — | int |
| `discriminating` | derived from `years` | — | — |

`area_ha` carries the published layer's own column name and the published layer's own
(clipped) footprint. ✓

**`summary_reconcile.csv`** — four populations, **one per row**, each named in its own
`step`/`mechanism` cell

| step | population | area |
|---|---|---|
| `unsieved_vectorize` | `P_unsv` | **U** |
| `after_sieve_unclipped` | `P_sv` | **U** |
| `after_zone_clip` | `P_cl` | **C** (recomputed `st_area`) |
| `published` | `P_pub` | **C** |

`d_n`/`d_ha` are `diff()` over those rows. Precision: round 1. ✓

**`summary_class_compare.csv`** — `_repro` = `P_cl`/**C**, `_pub` = `P_pub`/**C**;
`d_n` int, `d_ha` round 2. Suffixes name the population. ✓

**`join_audit.csv`** — deliberately mixed, and that is the file's stated job ("proof the
patch_id join is lossless"), so both sides must be present

| metric | population | area | precision |
|---|---|---|---|
| `patches_in` | `P_sv` | — | int |
| `patches_with_cells` / `patches_zero_cells` | `P_sv` ± rasterized cells | — | int |
| `cells_total` | cells of `P_sv` | — | int |
| `area_from_cells_ha` | `P_sv`, n_cells × cell_ha | **U** | round 2 |
| `area_from_geometry_ha` | `P_sv` | **U** | round 2 |
| `max_abs_patch_ha_delta` | `P_sv` | **U** | signif 3 |
| `published_patch_ids_matched` / `_unmatched` | `P_pub` ∩/∖ `P_sv` | — | int |
| `patches_not_tag_evaluated` | `P_sv ∖ P_pub` | — | int |
| `patches_trimmed_by_clip` | `P_sv∩eval`, U−C > 1e-6 | — | int |
| `trimmed_ha` | `P_sv∩eval`, Σ(U−C), signed | U−C | round 2 |
| `fire_flag_without_year` | `P_pub` | — | int |
| `harvest_flag_without_year` | `P_pub` | — | int |
| `fire_flag_without_number` | `P_pub` | — | int |
| `patches_no_valid_flip_cells` | `P_sv`, n_valid==0 | — | int |
| `no_valid_flip_ha` | `P_sv`, n_valid==0 | **U** | round 2 |

The `patches_*` prefix marks `P_sv` rows, `published_*` marks `P_pub`, and the three
`*_flag_without_*` rows are `P_pub` row counts that do **not** claim to be patch counts. The
only unclipped-vs-clipped ambiguity would be in a bare `_ha` column, and every `_ha` here is
**U** with no `_eval` sibling in the file to confuse it with. ✓

**`summary_patch_join.csv`** — `P_sv`, one row per patch

| column | population | area | precision |
|---|---|---|---|
| `area_ha` | `P_sv` | **U** | raw |
| `flag_sliver` / `_boundary` / `_reciprocal` | `P_sv` (#44, tagged on `pat_sv`) | — | logical |
| `n_valid` / `n_na` / `n_flicker` / `n_break` | cells of that `P_sv` patch | — | int |
| `break_year_modal` | modal over **break cells only**; NA if none | — | int |
| `flicker_frac` / `break_frac` | over `n_valid`; NA when `n_valid == 0` | — | raw |
| `in_fire` / `in_harvest` | `P_pub`, `any()`-collapsed; 0 after fill | — | int |
| `fire_year` / `fire_number` / `harvest_start_year_calendar` | `P_pub`, largest fragment | — | raw |
| `tag_evaluated` | `P_sv ∈ P_pub` | — | logical |
| `area_ha_eval` | `P_pub` Σ; NA when not evaluated | **C** | raw |

`area_ha` vs `area_ha_eval` is the pair that names the two footprints, and the
`n_eval_no_area` `stop()` at 750-754 makes `tag_evaluated & is.na(area_ha_eval)` loud rather
than a fourth silent state. ✓

**`summary_break_offset.csv`** — `P_sv∩eval ∩ flag==1 ∩ year non-NA`, grouped (year, offset)

| column | population | area | precision |
|---|---|---|---|
| `offset` | `break_year_modal − disturbance_year`; NA retained via `addNA` | — | int |
| `n_patches` | that set | — | int |
| `area_ha_unclipped` | Σ over that set | **U** | round 1 |
| `break_frac_area_wtd` | Σ(break_frac × U)/ΣU | **U** weight | round 3 |
| `discriminating` | derived | — | — |

The weight footprint and the reported area footprint are the same one, and the column name
says which. ✓

**`summary_flicker_strata.csv`** — `P_sv∩eval ∩ pop ∩ stratum ∩ !is.na(flicker_frac)`

| column | population | area | precision |
|---|---|---|---|
| `n_patches` | that set | — | int |
| `area_ha_unclipped` | Σ | **U** | round 1 |
| `area_ha_eval` | Σ | **C** | round 1 |
| `flicker_frac_area_wtd` | weighted.mean(flicker_frac, **U**) | **U** weight | round 3 |
| `break_frac_area_wtd` | weighted.mean(break_frac, **U**) | **U** weight | round 3 |

Strata thresholds (`ge_0.5_ha`) are on **U**, the same footprint as the weight and the
measurand. Every `pops` entry is gated on `tag_evaluated`, so `area_ha_eval` is never NA in
any `k`. ✓

**`group_meta.csv`** — scalars, each self-naming: `n_fire_events_disc` (`P_pub`, distinct
non-NA `fire_number`, discriminating years), `patches_dropped_by_clip` (`|P_sv ∖ P_cl|`),
`rows_split_by_clip` (`nrow(P_cl) − distinct patch_id`), `join_zero_cell_patches` (`P_sv`),
`reconciled` (raw logical). ✓

**summarize outputs**

| file | population | precision |
|---|---|---|
| `summary_reconcile_groups.csv` | as `summary_reconcile.csv`; `reproduced` from meta | 1-dp round-trip for the `_ha` columns, 2-dp for `max_abs_d_ha`, **raw** for `reproduced` — documented at 260-264, and `reproduced` is deliberately not re-derived |
| `summary_events_groups.csv` | `P_pub`, verbatim + `group` | 1-dp round-trip |
| `summary_events_disc_groups.csv` | `P_pub` throughout: `*_patches_*` rows, `*_ha_disc` = **C**, `fire_events_disc` = meta scalar | 1-dp round-trip |
| `summary_agreement_groups.csv` | `P_sv∩eval` throughout: `n_tagged`, `n_with_break`, `n_lag01` all from `summary_break_offset.csv` | int |
| `summary_flicker_groups.csv` | verbatim + `group` | as source |

### The two residuals, named rather than hidden

Neither reopens the class; both are stated so the next reader does not have to rediscover
that they were considered.

1. **`fire_patches_full + fire_patches_partial` (in `summary_events_disc_groups.csv`, a
   `P_pub` row count) and `n_tagged` for fire (in `summary_agreement_groups.csv`, a
   `P_sv∩eval` patch count)** are two counts of "fire-tagged patches in a discriminating
   year", in two tables of one note, over two populations, and no column name says so. They
   are equal **iff `published_patch_ids_unmatched == 0`** — and that row is published in
   `join_audit.csv` (measured 0 on lnth). So the discrepancy, if it ever appears, is
   reconcilable from committed rows without re-running anything. That is the standard round 2
   set for this class, and it is met.

2. **`flicker_frac_area_wtd` / `break_frac_area_wtd` do not name their weight's footprint**,
   and `summary_flicker_strata.csv` carries two area columns. The *population* is
   unambiguous; only the weighting footprint is un-named. It is **U** in both files that use
   the name, which was the round-3/4 fix, so the column means one thing everywhere it
   appears. A footprint qualifier is not a population, so this does not meet the class's own
   definition. Renaming to `*_area_wtd_unclipped` would close it cosmetically and is not
   required.

### Bottom line

- **Population/precision class: CLOSED.** No column's population disagrees with its name.
  Every population boundary that a reader could get wrong has a published reconciling row
  (`published_patch_ids_unmatched`, `patches_not_tag_evaluated`, `patches_trimmed_by_clip` /
  `trimmed_ha`, `patches_no_valid_flip_cells` / `no_valid_flip_ha`), and every clipped/
  unclipped pair is distinguished by column name (`area_ha` vs `area_ha_eval`,
  `area_ha_unclipped` vs `area_ha_eval`).
- **One blocker remains, and it is on the guard rather than the data: R5-1.** Until
  `script_sha` is hoisted to `t0`, the cross-group identity guard cannot fire on the run
  currently in progress — `bulk` will stamp a version it did not start with, and `summarize`
  will accept four metas that carry two different definitions. Fix that and the loop
  terminates.

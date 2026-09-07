# Code review — round 1: `data-raw/disturbance_compare.R` + `-run.sh` (#67)

Reviewed on branch `67-corroborate-the-temporal-qa-against-date` against the full files on
disk, `data-raw/break_class_groups.R`, `R/dft_rast_transition.R`,
`R/dft_transition_vectors.R`, `R/dft_rast_break_class.R`, the committed CSVs under
`data-raw/logs/disturbance_compare/`, and the four downloaded `transition_vector.gpkg`.
Every claim below was measured, not reasoned; the measurements are quoted inline.

## Verified clean (the four things the brief asked to be checked hardest)

Recorded so a later round does not re-litigate them.

1. **The `patch_id` join is genuinely lossless, and there is no CRS risk.**
   `pat_sv` comes from `terra::as.polygons()`, so its boundaries are on cell edges and the
   centre rule in `rasterize()` cannot drop a cell. Measured on the bundled fixture:
   per-patch `area_ha − n_cells * cell_ha` max `5.4e-11` over 48 patches, 0 mismatched, and
   `terra::same.crs(terra::vect(pat), res$raster)` is `TRUE`. Measured on all four production
   groups from `join_audit.csv`: `patches_zero_cells` 0, `area_from_cells_ha ==
   area_from_geometry_ha` exactly (3639.69 / 4729.98 / 1151.97 / 2888.35), `unmatched` 0.
   `res$raster` and `trans$raster` share a grid because `compareGeom()` is asserted over the
   inputs and `dft_rast_break_class()`'s pad branch only fires at `ncol == 5`.
2. **`crosstab(long = TRUE)` returns numeric, not factor.** I read the terra 1.9.34 method
   body: the factor-relabel branch fires only when `is.factor(x)` for that layer, and
   `pid_r` comes back `is.factor FALSE`, `datatype FLT4S`. Measured column classes
   `numeric numeric numeric`, `range(break_year) 2018 2023`. So `as.integer(break_year_modal)`
   in `offset_rows()` is the year, not a level index. The missing marker is `NaN`, not `NA` —
   every guard in the script uses `is.na()`, which is `TRUE` for `NaN`, so this is safe.
3. **`is_sustained()` / `discriminates()` agree with the library and with `cat_fun`.**
   `break_class_scan()` sets `break_year = years[idx+1]`, `n_before = idx`, `n_after = n − idx`,
   so `match(by, years) − 1` recovers `idx` exactly and `pmin(i, length(years) − i)` is
   `pmin(n_before, n_after)` — the same predicate as `break_class_groups.R`'s
   `cat_fun` (`pmin(v[,2], v[,3]) >= 2`). Enumerated: sustained = 2019..2022; `discriminates()`
   gives none/partial/full/full/full/partial/none for 2017..2023, matching the header comment
   and `group_meta.csv` (`full "2019|2020|2021"`, `partial "2018|2022"`). NA and
   out-of-range `Y` both fall through correctly (`FALSE & NA` is `FALSE`; empty `reach`
   returns `"none"`).
4. **`sum(pat_cl$area_ha)` is comparable to `sum(published$area_ha)`.** Measured on bulk:
   `max |published$area_ha − st_area(published)*1e-4| = 3.5e-11`, totals 3627.247 both ways —
   so the published column *is* geometry-derived post-intersection, exactly what
   `pat_cl$area_ha <- as.numeric(sf::st_area(pat_cl)) * 1e-4` reproduces.
   The per-class `merge(..., all = TRUE)` is a full outer join with `NA -> 0` afterwards, so a
   class present on one side only surfaces as `d_n != 0` rather than being missed.
5. **`offset_rows()`'s `aggregate` is correct.** `aggregate(cbind(...), by = list(a, b), FUN = sum)`
   dispatches through `aggregate.default -> aggregate.data.frame(as.data.frame(matrix))`, so
   `n_patches` is the row count and `area_ha` the sum, grouped on the two-column `by`. Both
   `by` variables are non-NA by construction (`q` is filtered on both). The 0-row branch
   returns the same column order as the non-empty one.
6. **`agg_cells()`'s empty guard works and is needed.** `aggregate(cbind(a,b) ~ id, ...)` really
   does error `no rows to aggregate` on an empty subset (reproduced). `merge(x, y0, by =, all.x = TRUE)`
   against the 0-row frame returns a logical-NA column, which the `<- 0L` fill then coerces —
   verified.
7. **The shell wrapper's `$!` is the right PID and the marker gate is sound.** `Rscript ... &`
   is on its own line with every `mkdir`/`: >` before it, and the committed traces confirm it:
   `bulk/rss.txt` starts at 32 KiB and reaches 1.45 GiB+ over 254 samples, i.e. the R process,
   not the wrapper shell. `run.log` is truncated by `>` each run so a stale
   `ALL STAGES DONE` cannot be matched, and `timings.csv` is written before the marker is
   printed.
8. **`.gitignore` coverage is correct.** `git check-ignore` confirms `.tif`, `.gpkg`, `.log`,
   `.json` and `summary_patch_join.csv` are ignored while `rss.txt` and `run_wallclock.txt`
   are tracked.
9. **The byte-identity premise in the header comment is true.** `md5` of
   `R/dft_rast_transition.R` and `R/dft_transition_vectors.R` at `v0.13.0` equals HEAD's for
   both, so the reconciliation is the fair test it claims to be.
10. **The note's unpinned Q2 numbers re-derive exactly** from the committed CSVs (see finding 6
    for why that is still worth changing): fire `0+77+0+46 = 123`, lag01 `0+68+0+38 = 106` →
    86.2 %; harvest `70+129+12+39 = 250`, `55+91+8+26 = 180` → 72.0 %; pooled offsets fire
    `0->37, +1->69, +2->8` and harvest `0->75, +1->105, +2->22`.

---

## Findings

### 1. **[bug]** `disturbance_compare.R:627-629` — patches the zone clip dropped are forced into `untagged_residual`, contaminating Phase 3's control group by a group-dependent amount (4.4 % of kotl's residual, 0.4 % of bulk's)

`ev_patch` is built from `pat_sv` (sieved, **unclipped**), but the disturbance tags come from
`published` (sieved **and clipped**). Every `pat_sv` patch with no published row falls out of
`merge(ev_patch, pubd, by = "patch_id", all.x = TRUE)` as `NA` and is then set to `0` at
line 590 — so it enters `pops$untagged_residual` as if floodplains had evaluated it against
fire and harvest and found neither. It was never evaluated at all: it lies outside the
sub-basin, so it is absent from the layer that carries the tags.

Measured from `join_audit.csv` and `group_meta.csv`:

| group | `patches_in` | matched to published | never tag-evaluated | share of that group's `untagged_residual` (all stratum) |
|---|---|---|---|---|
| bulk | 7191 | 7161 | 30 | 30 / 7038 = 0.4 % |
| necr | 5710 | 5692 | 18 | 18 / 5341 = 0.3 % |
| lnth | 2762 | 2753 | 9 | 9 / 2740 = 0.3 % |
| **kotl** | 5148 | 4929 | **219** | **219 / 5013 = 4.4 %** |

The contamination is **asymmetric and one-directional**: a clip-dropped patch can only ever
land in the residual, never in `harvest_touching` or `fire_touching`. And it is
area-weighted — `flicker_frac_area_wtd` uses `ev_patch$area_ha`, the *unclipped* area, and
`summary_reconcile.csv` records the kotl clip as removing **130.5 ha** against a kotl
`untagged_residual` of 2686.8 ha, i.e. up to ~4.9 % of the weight in the number the note's
Q3 conclusion rests on. Because kotl's share is an order of magnitude above the other three,
it also breaks the cross-group comparability the note leans on
("consistent across groups ... worth more than any single group's number").

The script already knows the two populations differ — it computes `dropped_ids` and publishes
`patches_dropped_by_clip` — but nothing connects that to the Phase 3 strata, and the note's
three stated limits on Q3 do not mention it.

Fix is one line: restrict the Phase 3 populations (or `ev_patch` itself, before the strata) to
patches that appear in `published`, e.g.

```r
evaluated <- ev_patch$patch_id %in% published$patch_id
pops <- list(harvest_touching  = evaluated & ev_patch$in_harvest == 1,
             fire_touching     = evaluated & ev_patch$in_fire == 1,
             untagged_residual = evaluated & ev_patch$in_harvest == 0 & ev_patch$in_fire == 0)
```

and re-run, since the published `summary_flicker_strata.csv` and the note's Q3 table would
move (bulk/necr/lnth negligibly, kotl measurably). Whichever way it moves, state the residual's
definition — "matched no disturbance layer **and was offered the chance to match one**" —
rather than leaving it implied.

### 2. **[fragile]** `disturbance_compare.R:318` — the top-level `on.exit()` never fires, so `unlink_tif()` is dead code

`on.exit(unlink_tif(tmp_tifs), add = TRUE)` sits at the script's top level. Under `Rscript`
the current frame is the global environment, which never exits, so the handler is registered
and never called. Reproduced:

```
$ cat /tmp/t6.R
on.exit(cat("ON.EXIT RAN\n"), add = TRUE)
cat("script body done; sys.nframe =", sys.nframe(), "\n")
$ Rscript /tmp/t6.R
script body done; sys.nframe = 0
```

No "ON.EXIT RAN". This is the exact trap in the repo's own `code-check-r.md`
("`on.exit()` at a script's top level never fires"), including its warning that the failure is
untestable inside `tempdir()`: the `pid_r` file and its `.aux.xml` sidecar are under
`tempdir()`, which R's own session cleanup removes, so a working handler and a broken one
produce the same observable result and nothing leaks in practice. The cost is that the
carefully-guarded `unlink_tif()` (its `character(0)` / `.aux.xml` handling, and the
`tmp_tifs <- c(tmp_tifs, terra::sources(pid_r))` bookkeeping at line 510) buys nothing, and
would keep buying nothing if a future edit moved an intermediate out of `tempdir()`.

Remedy prescribed by the convention: `withr::defer(unlink_tif(tmp_tifs), envir = globalenv())`,
which prints `Ran 1/1 deferred expressions` as its own confirmation. Note the lazy-evaluation
half is already correct — `tmp_tifs` is read at exit, not at registration.

### 3. **[fragile]** `disturbance_compare.R:584-588` — `aggregate(formula)` silently drops NA rows, making the `na.rm = TRUE` inside `FUN` unreachable and turning a tagged patch into an untagged one

```r
flags <- stats::aggregate(cbind(in_fire, in_harvest) ~ patch_id, pubd,
                          FUN = function(v) as.integer(any(v == 1, na.rm = TRUE)))
firstrow <- pubd[!duplicated(pubd$patch_id), ...]
pubd <- merge(flags, firstrow, by = "patch_id")     # inner join
```

`aggregate.formula` applies `na.action = na.omit` to the model frame **before** `FUN` ever
runs, so any row with `NA` in *either* flag is deleted, and the `na.rm = TRUE` is dead code.
Reproduced on a 5-row frame with `in_fire = c(1,0,NA,0,1)`, `in_harvest = c(0,1,1,1,NA)`:

```
  patch_id in_fire in_harvest      <- patches 2 and 4 are GONE
1        1       1          1
2        3       0          1
```

Patch 2 (`in_fire NA`, `in_harvest 1`) and patch 4 (`in_fire 1`, `in_harvest NA`) vanish from
`flags`; the **inner** `merge(flags, firstrow)` then removes them from `pubd` entirely; the
outer `merge(ev_patch, pubd, all.x = TRUE)` leaves `NA`; and line 590 sets both flags to `0L`.
Net effect: a genuinely fire- or harvest-tagged patch is reclassified into
`untagged_residual` and dropped from the Phase 2 offset distribution, silently. Same class of
error as finding 1, arriving by a different route.

Second, sharper failure: if a whole flag column were `NA` for a group (a fire join that matched
nothing and left the column NULL), `aggregate` **errors**:

```
Error in aggregate.data.frame(lhs, mf[-1L], FUN = FUN, ...) : no rows to aggregate
```

— aborting at the last stage of a 9–11 minute run. This is precisely the failure the script
guards for 35 lines above, in `agg_cells()`, with the comment "Guard once, here, so an empty
stratum stays a zero rather than aborting a 12-minute run at its last step". The guard exists
on one `aggregate` and not on the other.

**Latent, not live, on the current data** — I checked all four published layers:

```
in_fire     class=logical  nNA=0   uniq=FALSE,TRUE   (all four groups)
in_harvest  class=logical  nNA=0   uniq=FALSE,TRUE   (all four groups)
```

so the collapse currently produces the right answer, and the logical-vs-integer type is handled
correctly everywhere (`TRUE == 1L` is `TRUE`; verified `aggregate` on a logical `cbind` returns
`0/1` integers). But `event_rows()` at line 177 guards `!is.na(p[[flag_col]])`, i.e. the script's
own two consumers of these columns disagree about whether `NA` is possible — the cross-function
normalization inconsistency `code-check-r.md` names. Either drop the `!is.na()` in `event_rows()`
and assert the columns are non-NA once, or make this path honour `NA`:
`na.action = na.pass` plus `merge(flags, firstrow, by = "patch_id", all.x = TRUE)`.

### 4. **[fragile]** `disturbance_compare.R:593-598` — the comment says "patches with a CLEAN break at the modal year"; the code imposes no cleanliness condition at all

`break_year_modal` is built from `byv <- ct_by[!is.na(ct_by$break_year), ]` — the modal break
year **among the patch's break cells only**. A patch that is 90 % flicker and 10 % clean break
gets a `break_year_modal` from that 10 % and enters `offset_rows()` with the same weight as a
patch that is 100 % clean break. Nothing filters on `break_frac`.

So the Q2 headline ("86.2 %", "72.0 %", and the note's "drift's `break_year` lands on it or one
year later in roughly three quarters of the affected area") is over *all tagged patches with at
least one break cell*, not over cleanly-broken ones. The note repeats the code's framing
verbatim. Nothing errors and the direction of the result is unlikely to reverse — Phase 3
reports `break_frac` 0.72–0.93 for the tagged populations — but the number means something
looser than both the comment and the note say it does.

Pick one: add the restriction (`ev_patch$break_frac >= 0.5`, say, with the threshold stated),
or restate the definition in both places as "the modal break year among the patch's break
cells, with no minimum break fraction".

### 5. **[fragile]** `join_audit.csv` compares only totals, so it cannot see a per-patch misassignment — while being titled "Proof the patch_id join is lossless"

`patches_with_cells` vs `patches_in`, and `area_from_cells_ha` vs `area_from_geometry_ha`, are
aggregate identities. A `rasterize()` that assigned a cell to the wrong neighbouring patch
conserves both and the audit reads clean. The per-patch identity does hold — I measured it on
the bundled fixture (`max |area_ha − n_cells * cell_ha| = 5.4e-11` over 48 patches, 0
mismatched) — so this is a gap in the *evidence*, not in the result. One extra row closes it,
and it is the row a reader of an artifact called "proof" will assume is there:

```r
mm <- merge(data.frame(patch_id = pat_sv$patch_id, ha = pat_sv$area_ha), cells_by_patch,
            by = "patch_id")
# audit row: max_abs_patch_ha_delta = max(abs(mm$ha - mm$n_cells * cell_ha))
```

### 6. **[fragile]** the note's headline numbers are outside the verbatim guard, and `summarize`'s `reproduced` is weaker than the per-group one

Two related gaps in what the "the script refuses to finish if this file's copy differs" claim
actually covers.

- The guard (`disturbance_compare.R:297-305`) pins the four generated tables only. The note's
  most-quoted claims are hand-transcribed and unpinned: **"0 of 53 / 44 / 41 / 46 transition
  classes differ in count, max |Δha| 0.00"** (from `summary_class_compare.csv`, which
  `summarize` never reads), the pooled Q2 table, the Q3 flicker table, and the peak-RSS /
  wall-clock line. I re-derived every one from the committed CSVs and they are **correct today**
  (see "Verified clean" item 10) — the issue is that nothing keeps them correct, which is
  exactly what `break_class_groups.R`'s own comment warns about ("a hand-edited number in the
  note is exactly what the round-8 review of #9 found").
- `summarize`'s `recon$reproduced` (lines 223-224) is `repro_patches == pub_patches &
  abs(repro_ha − pub_ha) < 0.1`. The **per-group** `reproduced` (line 496) additionally requires
  `all(cmp$d_n == 0)`. So the `reproduced` column that lands in `summary_groups.csv` and in the
  note's first table asserts strictly less than the prose above it does — one fact derived twice,
  with the weaker derivation the one that gets published. Reading
  `summary_class_compare.csv` in `summarize` and adding an `n_classes` / `n_classes_differ`
  column would make the prose claim a generated cell.
- Minor, same family: `if (file.exists(note))` means a missing note is a silent pass. It mirrors
  `break_class_groups.R`, so it is the established pattern rather than a new defect, but the
  note is committed so the branch may as well be `stop()`.

### 7. **[fragile]** `inst/notes/temporal-qa-disturbance.md:63-64` — "five events in two groups" then enumerates four

> Fire is **five events in two groups** — necr's 2018 fire and kotl's 2020, 2021 and 2022 fires

Measured from the published layers, restricted to discriminating years:

```
necr 2018:  G40053 (2 patches), R11498 (85 patches)   <- TWO fires
kotl 2020:  N71973 (2);  2021: N71245 (9);  2022: N71980 (52)
```

The count 5 is right (and matches `fire_events_disc` 0+2+0+3 = 5); the enumeration is short by
one, because necr's 2018 row is two distinct `fire_number`s, not one. The sentence is the stated
basis for "this is a case series", so it is worth being exact: *necr's two 2018 fires and kotl's
2020, 2021 and 2022 fires*.

### 8. **[fragile]** minor, grouped

- `disturbance_compare.R:344-345` — `gpkg_fp` (`floodplain.gpkg`) is fetched **and
  checksum-verified** on every group run and then never read; `grep` finds no other use. That is
  a wasted download plus a wasted sha256 over a published asset, and the header comment (line 15)
  lists it as an input the script reads. Either drop it or use it. Same for `base_url` (line 118),
  `cell_m2` (line 368) and `sp` (line 314) — assigned, never referenced.
- `disturbance_compare.R:241` — `f("fire", "n_events", c("full", "partial"))` **sums** distinct
  `fire_number` counts across year rows, so a fire spanning two discriminating years would be
  counted twice. Verified not to happen on the current data (each `fire_number` occupies exactly
  one year within the discriminating set), but the statistic is a count of distinct events and
  is not computed as one.
- `disturbance_compare.R:233-236` — `f <- function(...) { v <- sum(...); if (length(v)) v else 0 }`.
  `sum()` always returns length 1, so the guard can never take its `else`. Harmless (the `na.rm`
  sum of an empty selection is already `0`) but it reads as protection that is not there.
- `disturbance_compare-run.sh:60` — when `rss.txt` has no samples (a run that dies before the
  first `ps`), `sort -n | tail -1 | awk '{printf ...}'` emits nothing and `peak` is empty, so the
  line prints `peak RSS  GiB`. Only reachable on the OK branch, so cosmetic.

---

## Not findings (checked, no issue)

- `terra::zonal()` is correctly avoided in favour of `crosstab()`; the reasoning in the comment
  at lines 513-517 matches terra 1.9.34's actual fast-path set.
- No `%in%` on a SpatRaster, no `terra::freq()` on a possibly-all-NA raster, no `minmax()`,
  no `levels<-`/`coltab<-` on a caller's raster, no `st_intersection` output written without a
  cast — none of the flagged terra/sf traps are reachable in this script.
- `merge()` cannot multiply rows: every joined frame is unique on `patch_id`
  (`aggregate`-produced or `!duplicated`-produced), and `anyDuplicated(published$patch_id)` is
  `0` in all four groups.
- `firstrow` does pick the largest fragment: `pubd` is sorted `order(patch_id, -area_ha)`
  before `!duplicated()`, so the first row per `patch_id` is its maximum-area row. Moot on
  current data (no duplicate `patch_id`) but correct.
- No `area_ha` suffix collision: `area_ha` is dropped from `pubd` by the
  `merge(flags, firstrow)` projection before it reaches `ev_patch`.
- `strata` uses `%in% TRUE` so `NA` flags fall to `FALSE`; `weighted.mean` is guarded by
  `sum(k) > 0`; all `pops` components are NA-free after the line-590 fill.
- `knitr::kable()` without `format = "markdown"` still emits pipe tables here (confirmed in the
  generated `summary_groups.md`), so the divergence from `break_class_groups.R` is cosmetic.

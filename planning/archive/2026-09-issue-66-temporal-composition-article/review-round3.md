# Review round 3 — `article-bulk` stage (drift#66)

Reviewed: `data-raw/break_class_groups.R` (article-bulk block, full file for context),
`inst/cartography/drift_temporal.csv`, `inst/extdata/temporal-composition/README.md`,
`data-raw/logs/break_class_groups/README.md` (also staged), the three produced artifacts,
the committed reference `data-raw/logs/break_class_groups/bulk/summary_change.csv`, and
`vignettes/articles/temporal-composition.Rmd` (untracked, but the sole consumer of the
artifacts this diff produces).

Everything below was measured, not read. terra 1.9.34, R 4.5.

---

## Findings

### 1. `[bug]` `inst/cartography/drift_temporal.csv:6` — the new row has 25 fields against a 24-field header

One extra comma before the note. `read.csv()` on the shipped file returns **6 rows, not 5**:

```
$ Rscript -e 'x<-read.csv("inst/cartography/drift_temporal.csv"); print(dim(x)); print(x[5:6,c(1,5,7,24)])'
[1]  6 24
                          layer_key    class_value fill_color notes
5                 temporal_category stable_flicker    #cbc9e2      <- note LOST
6 ColorBrewer Purples 3-class light                              <- phantom row
```

Two consequences, both silent:

- the `stable_flicker` row's `notes` is `""` — the ColorBrewer provenance the row was written
  to carry is gone;
- a phantom layer keyed `"ColorBrewer Purples 3-class light"` enters the registry.
  `gq::gq_reg_merge(gq_reg_main(), gq_reg_custom(...))` accepts it without warning and adds it
  as a **layer** (it groups by `layer_key`), so `reg$layers` now contains a garbage entry with
  no classes. The article's palette survives only because gq groups by `layer_key` and the
  phantom row happens to land outside `temporal_category` — an accident, not a guard.

Row 4 ends `1,,,,,,,,,,,,,,,,Okabe-Ito reddish purple` (16 commas); row 6 ends
`1,,,,,,,,,,,,,,,,,ColorBrewer…` (17). Delete one comma.

Worth a one-line assertion beside it, since nothing in the repo reads this file strictly:
`stopifnot(nrow(read.csv(f)) == 5L, !anyNA(read.csv(f)$fill_color))`.

---

### 2. `[bug]` `vignettes/articles/temporal-composition.Rmd:80-88` — 5 of the 7 panels in Figure 1 are mis-coloured, and Rangeland is drawn as Snow/Ice

`terra::plot(type = "classes", levels =, col =)` maps `col` **positionally onto the layer's own
sorted unique values**, not onto the class codes. The chunk computes `present` over the whole
7-layer stack and then plots each layer individually:

```r
present <- sort(unique(stats::na.omit(as.vector(terra::values(lulc)))))   # 1,2,5,9,11
ct <- ct[match(present, ct$code), ]
cols <- ct$color
for (i in seq_len(terra::nlyr(lulc))) terra::plot(lulc[[i]], type="classes", levels=ct$class_name, col=cols, ...)
```

Per-layer codes in the committed `bulk_window.rds`:

```
2017 codes: 1,2,5,9,11
2018 codes: 1,2,5,11    <-- Snow/Ice absent
2019 codes: 1,2,5,11
2020 codes: 1,2,5,9,11
2021 codes: 1,2,5,11
2022 codes: 1,2,5,11
2023 codes: 1,2,5,11
```

So in 2018/2019/2021/2022/2023 code 11 (Rangeland) takes `cols[4]` — Snow/Ice. Rendered and
sampled:

```
legend says Rangeland = #E3E2C3   Snow/Ice = #A8EBFF
2017 rendered colours: #2E6C39 #FFFFFF #DCDCB6 #DC8429 #3587D7   <- #DCDCB6 ~ Rangeland
2023 rendered colours: #FFFFFF #2E6C39 #9AE6FF #DC8429 #3587D7   <- #9AE6FF ~ Snow/Ice
2023 rangeland (code 11) cells: 705
```

The figure exists to show a patch going Trees -> **Rangeland**, and in the 2023 panel those 705
Rangeland cells are drawn in the Snow/Ice colour while the shared legend below says otherwise.
The failure is invisible on inspection because both colours are plausible land-cover fills and
the two correct panels (2017, 2020) are the ones with all five codes.

The same chunk's sibling gets it right — the reach panel is **value-keyed**:

```r
terra::coltab(reach, layer = 1) <- data.frame(value = 0:4, col = unname(pal[keys]))
```

Use that form for `lulc` (a `data.frame(value = ct$code, col = ct$color)` coltab per layer, or a
per-layer `ct` filtered to that layer's own codes). Note this is the property the `strip()`
comment traded away deliberately — "a cropped factor keeps every level so the legend fills with
classes the panel does not contain" — so the fix is a value-keyed coltab, not a re-attached RAT.

---

### 3. `[bug]` `data-raw/break_class_groups.R:190-197` — `strip()` does not strip: 6 of 7 `lulc` layers keep their colour tables

`terra::coltab(y) <- NULL` on a multi-layer raster removes **layer 1 only**
(`removeColors(layer[1] - 1)`) — the trap `code-check-spatial.md` names, and the very trap the
neighbouring `set.cats()` loop exists to route around. The loop was written for `levels<-` and
the `coltab<-` line beside it was not given one. Measured on the committed artifact:

```
layer 1 2017 : no coltab
layer 2 2018 : coltab rows 8
... layers 3-7 the same
```

Rendering is unaffected today (measured: an explicit `col=` wins over an attached coltab), so
this is a latent defect rather than a live one — but the helper silently fails the contract its
own comment states, the artifact ships six palettes the article says it re-attaches itself, and
any consumer calling `terra::plot()` or `writeRaster()` without `col=` gets the embedded table.

Fix: `for (i in seq_len(terra::nlyr(y))) terra::coltab(y, layer = i) <- NULL` inside the same
loop as `set.cats()`.

---

### 4. `[fragile]` `data-raw/break_class_groups.R:260-266, 176-178` — the committed extent provenance is the *requested* box, and the guard beside it cannot fire on the difference

`terra::crop()` silently truncates to the intersection when the extent runs past the raster.
Measured:

```
requested ext: -55,105,-55,105
crop     ext:  0,110,0,110      (no warning)
```

`prov$patch_xmin..reach_ymax` are taken from `as.vector(e_patch)` / `as.vector(e_reach)` — the
box that was *asked for*. If the rule ever selects a patch within 200 cells of the floodplain
raster's edge, `cat_reach` comes back smaller and `bulk_window.csv` records an extent the `.rds`
does not have. The article draws its locator box straight from those columns
(`graphics::rect(win$reach_xmin, …)`), so the box would mark ground the panel does not show.

The guard that looks like it covers this cannot:

```r
stopifnot(terra::compareGeom(lulc, cat_patch, stopOnError = FALSE))
```

Both sides were cropped by the *same* extent, so both truncate identically and the comparison
passes. It is two things that move together.

Fix either way round: record `as.vector(terra::ext(cat_patch))` / `ext(cat_reach)` in `prov`, or
assert `dim(cat_patch)[1:2] == c(61, 61)` and `dim(cat_reach)[1:2] == c(401, 401)`. The first is
better — it makes the CSV a measurement of the artifact rather than a restatement of intent.

---

### 5. `[fragile]` `data-raw/break_class_groups.R:238, 244, 251` — `abs(x - y) > 0.5` on a quantity that is exact to 0.01, with a measured residual of 1e-11

Every term is an integer cell count times `cell_ha = 0.01`, so the honest comparison is exact.
Measured against the committed grid:

```
valid   41089.720000 vs 41089.720000  diff 0.000e+00
changed  4624.970000 vs  4624.970000  diff 1.091e-11
stabflk  3186.530000 vs  3186.530000  diff 1.819e-12
```

The tolerance is ten orders of magnitude above the float noise, and it lets **49 cells (0.49 ha)
of real floodplain go missing without a word**. Two hundred metres away in the same file, the
`summarize` stage makes the same class of comparison exactly and says why:

> Verified delta 0 in all four groups, so `identical()` is the right strength — there is no
> tolerance to tune and no float drift to absorb.

Use the same strength here: `identical(round(valid_ha / cell_ha), as.numeric(sum(ref$n_cells)))`,
or keep a tolerance sized to the arithmetic (`1e-6`), not to nothing.

---

### 6. `[fragile]` `data-raw/break_class_groups.R:289-291` — the size guard fires after the file is written, and the two CSVs are already updated

```r
saveRDS(art, out_rds, compress = "xz")
message(...)
if (file.size(out_rds) > 500e3) stop("artifact over 500 KB; shrink the reach window")
```

On the failure path the oversized `.rds` is on disk and stageable, and `bulk_grid_1km.csv` and
`bulk_window.csv` were rewritten before it — so a failing run leaves the three committed
artifacts out of sync with each other, with the two CSVs describing an `.rds` the guard rejected.
This contradicts the discipline the same file states for the `summarize` stage:

> `--- guard: five checks, all before any write ---`
> so a failing run leaves no CSV behind for the next one to trust

Minimum fix: `unlink(out_rds)` on the failure path. Better: write to a temp path, check the size,
`file.rename()` into place — and check the rename's return value, which `file.rename()` reports
as `FALSE` rather than erroring.

---

### 7. `[fragile]` `data-raw/logs/break_class_groups/README.md:28-31` — the edit widened the subject of a sentence that is false for the new half

```
The `summarize` stage also writes the pkgdown article's tables into
`inst/extdata/temporal-composition/` (drift#66), and a third stage, `article-bulk`, writes that
article's BULK figure data alongside them. Both are described in that directory's own README. They
are a rollup of the committed `summary_pixels.csv` files, guarded against each group's
`summary_change.csv` on integer cell counts, so they cannot drift from the numbers above.
```

"They" now covers both stages. For the `article-bulk` outputs both clauses are wrong: they are a
**fresh scan of the COGs**, not a rollup of `summary_pixels.csv`; and `bulk_grid_1km.csv` is
guarded on **hectares with a 0.5 tolerance**, not on integer cell counts. Only the reproduction
self-check is on integers.

This is R2.1's mechanism recurring inside R2.1's own fix — a sibling README asserting a scope the
newly-included subject does not satisfy. Split the sentence rather than widening it.

---

### 8. `[fragile]` `inst/extdata/temporal-composition/README.md:24, 39` — two claims the new files falsify

**a) `## Two things worth knowing before quoting these numbers` now has three.** The diff added
"**Five categories, not four.**" beside the two existing bolded paragraphs and left the heading.

**b) "No patch-size threshold is applied anywhere in this directory."** This is now false.
`bulk_window.csv` is the product of exactly a patch-size threshold — `cand$area_ha >= 1 &
cand$area_ha <= 4` — and it publishes patch-level cell counts (`n_cells_sustained`, etc.). The
sentence exists to stop a reader comparing these numbers to `transition_vector.gpkg`'s sieved
patch totals, so it is load-bearing, and a reader now applies it to a file it does not describe.
Scope it to the pixel-level tables.

---

### 9. `[fragile]` `data-raw/break_class_groups.R:184-189, 274` — the `.rds` byte-reproducibility the `varnames` fix restores does not exist

The comment says a leaked tempfile basename means "the `.rds` stops being byte-reproducible".
Pinning `varnames` is right — a per-process random path is strictly worse than a date — but
`art$meta` is `prov`, which carries `date = format(Sys.Date())` plus the `terra` and `drift`
versions. So the artifact still churns on any re-run on a new day, and the property the fix is
described as restoring is not held. Either say what the fix actually buys (churn on every run ->
churn per day) or drop `date` from the wrapped copy and keep it in the CSV only.

---

### 10. `[fragile]` `data-raw/break_class_groups.R:133-136` — `n_candidates_all` is published as a fact about the patch layer but measured after an inner join

```r
cand <- merge(sf::st_drop_geometry(patches)[...], wide[...], by = "patch_id")
n0 <- nrow(cand)
```

`n0` is written to `bulk_window.csv` as `n_candidates_all` and quoted in Figure 1's caption as
"of 21,701 change patches". A patch present in `patches` but absent from `wide` — a rasterize
that placed no cell centre inside it — is dropped by the inner join and the denominator shrinks
silently. It happens to be exact today (21,701, matching the number `CLAUDE.md` records for
BULK), which is the only reason nothing shows. One line closes it:
`stopifnot(identical(n0, nrow(patches)))`.

---

## Mechanism and enumeration

### The mechanism

Every fix so far — R1.1, R1.2, R1.3, R2.1, R2.2, R2.3, and the three found by running it — is one
shape:

> **A claim states a scope; the thing that produces or enforces it covers a different scope; and
> nothing compares the two.**

The claim is whatever a reader will act on — a guard's message, a comment, a README sentence, a
published column name, a helper's name. The enforcement is what the code does. R1.1 claimed a
factor and divided a rounded share. R1.2 claimed "the rollup reproduces the file" and walked only
the rollup's keys. R1.3/R2.1 claimed stages the code did not have. R2.2 claimed a positive control
and drove one arm. R2.3 claimed one condition in a message covering three. The proxy guard claimed
"the grid is right" and measured block count. `cat_fun`'s category 3 claimed "flicker" over two
populations. `varnames` claimed byte-reproducibility.

The fix is always one of two moves: **widen the enforcement to the claim, or narrow the claim to
the enforcement.** Findings 1, 3 and 7-10 above are the first move being needed; finding 5 and 6
are the second.

### Enumeration

Every site in this diff that makes a scope claim, and whether enforcement matches it. Verdicts
marked *(measured)* were established by running the code, not by reading it.

| # | site | claim | enforcement | verdict |
|---|---|---|---|---|
| A | script header, "Outputs" block | three files from `article-bulk` | the three writes | **closed** |
| B | block comment, "reuses `cat_fun()`/`cat_labels` as the SAME objects" | no second copy | both are the top-level closures; no redefinition in the block | **closed** |
| C | "never runs in CI" | not reachable from CI | `data-raw/` script, no workflow invokes it | **closed** |
| D | `message("reproduces … cell for cell")` | this run == the committed run | `anyDuplicated` + `setequal` on keys, then `identical()` on `as.integer` counts — both arms | **closed**; note `ct[!is.na(ct$changed), ]` drops any cell with `category` non-NA and `changed` NA, which the self-check then cannot see — caught transitively by conservation check #1, which counts `valid` from `category` |
| E | `fig_fun` comment, "category 3 pools two populations" | the 5-class split keeps them apart | the split, plus the separate `stable_flicker` conservation check | **closed** |
| F | `fig_fun` mapping | every (changed, category) pair handled | `(1,1)(1,2)(1,3)` -> `ca`; `(0,3)` -> 4; `(0,0)` -> 0. The three structurally impossible pairs `(1,0)`, `(0,1)`, `(0,2)` would fall to 0 / `ca` — but each would add a key absent from `summary_change.csv`'s five rows, and `setequal(k_now, k_ref)` refuses first. `changed==1 & category==0` cannot occur: `n_flips == 0` implies first == last | **closed** |
| G | `if (!is.matrix(v)) stop(...)` in `cat_fun`/`fig_fun`; **absent** in the `changed` and `valid` closures | `app()` must not run per cell | *(measured)* the per-cell path fires only for **multi-layer** input: a vector-tolerant fun on a 4-layer raster took 40,013 calls, on a 1-layer raster 2. `changed` (`codes`, 1 lyr) and `valid` (`category`, 1 lyr) are single-layer; `category` (`res$breaks`, 4 lyr) and `fig_cat` (2 lyr) both carry the guard | **closed**, but two of the four are closed *incidentally* — a later change making either input multi-layer regresses silently. Cheap to add the guard to both |
| H | `n_cells.0` guard message | "stable cells inside a change patch" | `%in% names(wide) && sum(...) > 0`; the message matches the single condition | **closed** |
| I | `n0` as `n_candidates_all` | "of N change patches" | inner `merge()`, no comparison to `nrow(patches)` | **OPEN — finding 10** |
| J | `stopifnot(compareGeom(lulc, cat_patch))` + `prov$patch_*`/`reach_*` | the committed extents are the artifact's extents | both sides cropped by the same extent, so truncation is invisible; `prov` records the requested box | **OPEN — finding 4** |
| K | `strip()` comment, "a factor written out drops a RAT sidecar … the article re-attaches labels and colours" | no cats, no coltabs | `set.cats()` loops all layers; `coltab<-` strips layer 1 only *(measured: layers 2-7 keep 8-row tables)* | **OPEN — finding 3** |
| L | `varnames` comment, ".rds stops being byte-reproducible" | it is byte-reproducible once pinned | `meta$date` = `Sys.Date()` in the wrapped object | **OPEN — finding 9** |
| M | round-trip `stopifnot` | wrap/unwrap is lossless | covers `lulc` only, not `category`/`reach`; compares an object against itself so it can only catch wrap/unwrap, which is what it claims | **closed** (narrow claim, narrow check). Extending it to the other two costs one line and would have surfaced K, since the coltab is the thing that differs between layers |
| N | `names(ind) <- c("stable","sustained","endpoint","unsettled","stable_flicker")` after `segregate(classes = 0:4)` | layer *i* is class *i-1* | *(measured)* `segregate(classes = 0:4)` returns exactly 5 layers named `"0".."4"` in ascending order **including for classes absent from the raster**; NA stays NA, so an absent class is an all-zero layer rather than a missing one | **closed** — the positional assumption holds. Worth `stopifnot(identical(names(ind), as.character(0:4)))` before the rename, since it is enforced by nothing |
| O | `n_drop <= 0` guard | the `valid > 0` filter is not decoration | positive control on the filter | **closed** |
| P | three conservation checks, `abs(x - y) > 0.5` | "matches the committed total" | tolerance 5e-1 on a quantity exact to 1e-2, measured residual 1e-11 | **OPEN — finding 5** |
| Q | conservation covers valid / changed / stable_flicker | the grid carries the whole floodplain and nothing more | `stable_ha` is unchecked, as is the partition identity. Both *are* implied — `fig_cat` is NA exactly where `changed` or `category` is NA by construction of `fig_fun`, and check #1 catches any widening of that set — and measured, `stable + changed + stable_flicker - valid = 7e-11` | **closed by implication**; asserting `sum(the four parts) == valid_ha` would make it a measurement rather than an argument |
| R | the three checks vs the grid's **geometry** | the 1 km grid is right | all three are sums over value columns; nothing checks `x`/`y`. *(measured)* `aggregate(fact = 100)` on a non-multiple grid **expands the extent** (5x7 at fact 3 -> ext `0,9,-1,5`) and gives edge blocks full-size centres, with sums conserved exactly (35 in, 35 out). So the padding is benign and the coordinates are correct for the aggregated grid — an edge block's centre can sit up to ~490 m outside the source raster, immaterial on a 146 x 115 km locator | **closed** for the padding question; the residual "all three pass while x/y is wrong" is real but reachable only through an `as.data.frame(xy = TRUE)` defect |
| S | `if (file.size(out_rds) > 500e3) stop(...)` | the artifact never exceeds 500 KB | runs *after* `saveRDS()`, and after both CSV writes | **OPEN — finding 6** |
| T | `README.md` table, three new rows | what each file holds | matches the writes | **closed** |
| U | `README.md`, "Regenerate with `summarize`, then `article-bulk`" | that sequence reproduces the directory | `article-bulk` depends on the **per-group `bulk`** stage (the COGs and `summary_change.csv`), not on `summarize`; only the script's own error message says so | **OPEN (minor)** — say `bulk`, then `summarize`, then `article-bulk` |
| V | `README.md`, "## Two things worth knowing" | two | three | **OPEN — finding 8a** |
| W | `README.md`, "No patch-size threshold is applied anywhere in this directory" | every file in the directory | `bulk_window.csv` is a 1-4 ha selection | **OPEN — finding 8b** |
| X | `README.md`, "the conservation checks refuse to write if any of the three totals misses its committed value" | the checks precede every write | they do — all three precede `write.csv(grid, …)` and everything after it | **closed** |
| Y | `data-raw/logs/.../README.md`, "They are a rollup … guarded on integer cell counts" | both stages' outputs | false for `article-bulk` on both clauses | **OPEN — finding 7** |
| Z | `drift_temporal.csv` new row | a fifth class in a 5-row table | 25 fields against a 24-field header -> 6 rows, note lost | **OPEN — finding 1** |
| AA | article Fig 1, `levels = ct$class_name, col = cols` from stack-wide `present` | each panel is coloured by class | `col` maps positionally onto the **layer's** unique values; 5 of 7 panels shift | **OPEN — finding 2** |

**Termination.** 27 sites, 17 closed (7 of them by measurement rather than by reading), 10 open.
The enumeration is over *claims*, not over lines, and it was built by walking the block top to
bottom and asking of each comment, guard message, published column and README sentence: what does
this assert, and what enforces it. The three defects that were found by *running* the stage in
this phase (the proxy guard, the pooled category 3, the `varnames` leak) all sit in this table —
G/N/R, E, L — which is the check that the enumeration reaches the class rather than only the
instances.

Items I and N are the two closed-by-accident entries: both hold today for reasons the code does
not state, and both cost one `stopifnot` to convert into facts.

---

## Checklist items examined and found clean

- **`stats::aggregate` traps** — not used in the new block. The `summarize` stage's uses are
  pre-existing and out of this diff.
- **`terra::zonal()` fast path** — correctly avoided; `crosstab()` is used with the reason in a
  comment, and *(measured)* `crosstab(long = TRUE)` returns **numeric** columns, not factors, so
  `as.integer(as.character(x))` is a harmless round trip. `patch_id` maxes at 21,701, well below
  the ~1e5 point at which `as.character()` on a double switches to scientific notation.
- **`app()` transposition** — `cat_fun`, `fig_fun` and both anonymous closures return a *vector*
  per chunk, so the k-column-on-a-k-column-raster trap is unreachable.
- **`aggregate(fun="sum", na.rm=TRUE)` returning 0 for an all-NA block** — handled by the `valid`
  indicator, and the `n_drop <= 0` guard proves the filter fires.
- **`reshape()` naming** — *(measured)* columns are named exactly `n_cells.<k>`; column *order*
  varies with first appearance but the code indexes by name. A category absent from every patch
  simply yields no column, which the `if (!cn %in% names(wide))` branch creates. Note `wide[[cn]]
  <- 0L` would error on a 0-row `wide`; unreachable here (21,701 patches) but not asserted.
- **`$` partial matching** — *(measured)* `data.frame` `$` does **not** partial-match:
  `d$n_cells` on a frame with `n_cells.1`/`n_cells.2` returns `NULL`. `sel$n_cells.1` is an exact
  match. `grid$valid` is read *before* `valid_ha` is created, so there is no ambiguity there
  either.
- **`mask()` `touches = TRUE`** — no `mask()` in the block.
- **crosstab / rasterize alignment** — `patches` is polygonized from `res$raster`, so cell-centre
  rasterization cannot lose or gain a cell.
- **conservation checks reading their own output** — none of the three reads
  `bulk_grid_1km.csv`; all compare an in-memory `grid` against the committed CSV from an
  independent producer. The self-check having just proved this run == that CSV does not make them
  circular: they test the `segregate` -> `aggregate` -> filter -> hectares path, which the
  self-check never touches.
- **`ifelse` type coercion in `fig_fun`** — `out` silently promotes to double; written as `INT1U`,
  values 0-4, no overflow.

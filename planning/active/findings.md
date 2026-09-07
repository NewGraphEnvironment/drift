# Findings — sliver-shaped patches and where flicker concentrates (#73)

## Measured during plan-mode exploration (2026-09-07)

Machine: 64 GB, macOS. terra 1.9.34, drift 0.16.0. BULK floodplain (`bulk_co_ff04`),
14651 x 11552 = 169,248,352 cells at 10 m, EPSG:32609, 4,108,972 valid.

### `terra::distance()` at floodplain scale is cheap

| step | seconds |
|---|---|
| water mask (`ifel`) | 2.1 |
| `terra::distance()` over 169M cells | **8.3** |
| `dft_rast_break_class()` (7 years) | 59.2 |
| `dft_rast_break_category()` | 26.9 |
| whole band x category probe, end to end | 107.7 |

The distance transform is the cheapest step in the pipeline, an order of magnitude under the scan
that already runs.

**Corrected after review:** an earlier draft claimed the issue body "has the cost inverted" and
scheduled an edit to the issue saying so. The issue never mentions compute cost. It says *"the
confound is the work"* and that Phase 1 can ship alone "if phase 2 **runs long**", which plainly
means the design question, not the wall clock. Measuring 8.3 s refutes nothing the issue claimed,
and the finding below on `break_year` shows the design question was in fact still open. That
issue-body edit is dropped; correcting a premise the author never held would have put a wrong
correction on the record.

### Corridor profile, stable-water-core reference

Reference = pixels classed Water in **all seven** years. On BULK that is 591,901 cells,
which equals the `Water,Water,stable` row of the committed `summary_pixels.csv` exactly.
That identity is what makes the reference non-circular: every reference cell is stable by
construction, so the reference cannot manufacture the instability being measured.

| distance from core | valid cells | stable | break_sustained | break_endpoint | unsettled | stable_flicker |
|---|---|---|---|---|---|---|
| core (0 m) | 591,901 | 100.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| 0-10 m | 45,440 | 2.8% | 8.7% | 33.3% | 22.2% | 33.0% |
| 10-30 m | 81,105 | 45.0% | 4.6% | 15.1% | 18.2% | 17.1% |
| 30-50 m | 72,593 | 69.3% | 2.7% | 6.8% | 10.2% | 11.1% |
| 50-100 m | 146,396 | 73.2% | 2.5% | 5.8% | 8.0% | 10.5% |
| 100-200 m | 229,578 | 74.8% | 2.6% | 5.2% | 6.7% | 10.6% |
| 200-500 m | 446,109 | 74.6% | 3.4% | 4.9% | 6.6% | 10.4% |
| >500 m | 2,495,850 | 81.6% | 2.2% | 3.8% | 4.6% | 7.8% |

Unsettled 4.8x, combined flicker (unsettled + stable_flicker) 4.5x, `break_sustained` 4.0x.

**Corrected after review:** an earlier draft of this file said "monotone in every column". It is
not. `stable` dips 74.8 -> 74.6 between the 100-200 and 200-500 m bands, `stable_flicker` is flat
across 50-200 m, and `break_sustained` has a **local maximum at 200-500 m** rather than falling.
Only `unsettled` and `break_endpoint` are monotone once the core row is dropped. The
`break_sustained` shape matters on its own: settled, real change peaks *away* from the water, which
argues against reading the corridor result as "change concentrates on the channel". It is a
**flicker** result.

### Sensitivity: 2017-Water reference

The same probe against a single-epoch (2017 Water) reference, which is partly circular
because a margin pixel that flickers Water/non-Water is both near 2017 water and unsettled:

| distance | stable | break_sustained | break_endpoint | unsettled | stable_flicker |
|---|---|---|---|---|---|
| 0 m (water itself) | 94.1% | 0.6% | 1.6% | 1.2% | 2.5% |
| 0-10 m | 19.3% | 6.1% | 22.0% | 29.2% | 23.4% |
| >500 m | 82.2% | 2.2% | 3.8% | 4.3% | 7.5% |

The effect holds under both references and is *stronger* under the non-circular one, which
is the direction that supports the claim rather than the one that would undermine it.

### The oscillation-versus-walk separation already exists

The issue's sketch step 3 proposes separating a monotone channel walk from mixed-pixel
oscillation using `break_year` / `n_before` / `n_after`. `dft_rast_break_category()` (#72)
already is that separation: a clean switch is `break_sustained` / `break_endpoint`, an
oscillation is `unsettled` / `stable_flicker`. No new machinery is needed. Both are
elevated at the margin, oscillation about 5x and the walk about 4x, so the naive "flicker
near water means noise" reading is incomplete in the direction #67 already warned about.

### The confound is class composition, not distance

2017 class composition shifts sharply with distance to the core: the first ring is roughly
a third Water and carries most of the Bare pixels, and Trees peaks in the 10-50 m bands.
Water and Bare are the intrinsically confusable classes, so distance and composition are
not separable by the banding alone. Controlled with a three-way
`crosstab(band, from_class, category)` — one call — so a within-class share can be quoted.

### The acceptance criterion cites a sentence that does not exist

The issue asks that the article\'s *"the spatial arrangement has not been examined"*
sentence be removed once it stops being true. Grepped `vignettes/`, `docs/`, `NEWS.md` and
`planning/` for `spatial arrangement`, `arrangement` and `not been examined`: **zero
matches**, against a positive control (`does not support`, 1 match) proving the search
works. The article never concedes the gap; it simply never raises the spatial axis. So the
concession has to be **added** before it can be filled, and the issue body needs the edit.

### Constraints found

- The article's own `wordcount` chunk stops the render above the cap. 731 words now.
- `summarize` refuses to write unless a rollup matches `summary_change.csv` on integer
  counts; `article-bulk` refuses unless it reproduces BULK cell for cell.
- `break_class_groups.R:231` requires `inst/notes/temporal-qa-groups.md` to contain
  `summary_groups.md` verbatim.
- The five temporal categories are unchanged, so `inst/cartography/drift_temporal.csv` and
  the article's `stopifnot()` on the class set are untouched.

## Plan review round 1 — findings acted on

A `Plan` subagent reviewed the task plan against the issue and the code while Phase 1 was being
written, so it read the implementation rather than the plan text. Nine findings were verified
against the committed artifacts and acted on; the two most consequential changed what the article
will claim.

### The stable-water core excises the stable class from the near bands (verified, reframes the result)

The core is every pixel with `n_flips == 0` and class Water. So **every permanent-water pixel is
removed from the band population and put in the core**, and the 0-10 m ring is by construction the
set of cells beside permanent water that are *not* permanent water — the one place the dominant
stable class has been excised a priori. The far bands keep all of theirs.

Measured, `from_class = Water` on bulk, share within band and class:

| band | stable |
|---|---|
| core | 100% |
| 0-10 m | **0%** |
| 10-30 m | **0%** |
| ... | **0%** |
| >500 m | **0%** |

Zero in every band outside the core, exactly as predicted: a 2017-Water cell that is not in the
core either changed or flickered, so `stable` is structurally unreachable. **Any all-class band
share is contaminated by this, and the Water column of the within-class table is a tautology.**

The fix is not a different reference — it is to lead with a class that cannot be in the core.
`from_class = Trees` is immune, and it is clean and monotone (bulk, share within band and class):

| band | stable | flicker |
|---|---|---|
| 0-10 m | 8.4% | 54.5% |
| 10-30 m | 61.6% | 24.3% |
| 30-50 m | 82.2% | 12.7% |
| 100-200 m | 86.2% | 10.1% |
| >500 m | 88.1% | 7.6% |

Across all four groups, within-Trees flicker runs 46.3-59.7% in the first ring against 3.3-11.1%
beyond 500 m. **That is the number the article should quote**, not the all-class band share.

### `break_sustained` does not establish a walk (verified, added to the stage)

An earlier draft of this file claimed the issue's step 3 "needs no new machinery" because
`dft_rast_break_category()` already separates the channel walk from mixed-pixel oscillation. It
does not: a classifier that changed its mind once and permanently produces `break_sustained` too.
A walk is a spatial-temporal signature — `break_year` rising with distance across a band of pixels
— and that layer was not in the plan. It is in `res$breaks` already, so it cost one crosstab.
`summary_corridor_breakyear.csv` is the result.

### A control is not a null (verified, added to the stage)

The acceptance criterion asks for a corridor claim "with its null stated". A three-way crosstab on
`from_class` is a **control** for composition — it says the gradient is not an artifact of which
classes sit near water. It says nothing about whether *water* is special. The null that answers
that is a from-epoch class boundary with no water on either side: same machinery, same bands, same
denominator. If flicker rises at any edge the same way, the corridor framing is not supported and
the honest reading is a generic edge effect. Added as a third reference arm.

### The issue's own boundary-signature numbers are wrong, and the effect reverses in one group

The issue body quotes `break_frac` "0.464-0.544 against 0.515-0.629" for artifact-signature
patches against the rest. Read straight off the four committed `summary_patch_groups.csv` files:

| group | artifact_signature | other | sliver | wider |
|---|---|---|---|---|
| bulk | 0.494 | 0.575 | 0.464 | 0.590 |
| necr | 0.490 | 0.621 | 0.478 | 0.629 |
| lnth | **0.518** | **0.515** | 0.478 | 0.532 |
| kotl | 0.550 | 0.583 | 0.544 | 0.588 |

The quoted range conflates two rows: 0.464-0.544 is the **sliver** range and 0.629 is necr's
**wider** value. The artifact range is 0.490-0.550 against 0.515-0.621. And in **lnth the
direction reverses** — artifact-signature patches settle slightly *more* than the rest. So the
article must not assert a boundary-signature effect as universal; it holds in three groups of
four. The width effect, by contrast, is solid: sliver `n_flips` exceeds wider in all four and
sliver `break_frac` is below wider in all four.

### "One pixel wide" is not what `flag_sliver` measures

`R/dft_transition_artifact.R:141,238` — `flag_sliver` is `(2 * area / perimeter) / cell_size <
1.5`, an effective-width proxy. At 10 m an isolated cell scores 0.5 px, a 2x2 block 1.0, a 2x3 1.2,
a 3x3 exactly 1.5 (not flagged); rasterized diagonals have inflated perimeter and are
systematically flagged. So the population is "effective width under 1.5 pixels — small compact
blobs as well as one-cell strips", not "one pixel wide". The value traces to a committed CSV, which
is what the acceptance criterion asks; the sentence did not describe the measurand.

### kotl's reference is a lake, not a channel

Core share of valid cells: bulk 14.4%, necr 25.3%, lnth 33.7%, **kotl 67.0%**. Kootenay Lake is
two thirds of that floodplain, so "distance to the channel" reads as "distance to a regulated lake
shore" there. Band occupancy is not the problem — every band holds 37k-2.5M cells in every group —
the framing is. Reported in the article rather than corrected.

### Guards added

- Both comparator arms now have a positive control; one perturbed count drives only the value arm.
- Band-degeneracy check: every conservation arm is satisfied by an all-zero distance raster, which
  is what a 1/0 mask produces, since `terra::distance()` measures *from* NA cells *to* non-NA ones.
- Realised band set asserted against the eight declared codes — `classify()` leaves an unmatched
  value at its original value rather than setting NA, so an out-of-range distance would survive as
  a phantom band carrying a raw metric.
- Unmapped from-epoch class codes refused rather than becoming an NA class name.
- `wopt = list(steps = 64)` on the seven-layer `app()`; `terra::tmpFiles(remove = TRUE)` per group.

### Findings checked and already satisfied by the implementation

`terra::distance()` polarity (the mask is built 1/NA), the `7L` magic literal (`ncol(v)` is used),
the water code (read from `dft_class_table()`), the four-level vocabulary in `summary_change.csv`
(joined on `category_label` through `read_change()`, never on the integer id), factor layers
reaching `crosstab()` (`deepcopy` + `set.cats(NULL)`), and the reclass lower bound of -1 reaching a
published column (fixed before the first commit).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| A background probe launched with `&` inside a Bash call returned "completed" while the R process was still running; the log held only a progress bar | Gate on the in-band `PROBE DONE` marker and wait on the PID with `kill -0`, never on the wrapper exit |

## Issue context

Pasted verbatim and **not verified** — the boundary-signature numbers in it
are wrong, see the review section above. Kept as the record of what was asked.

**If we do it:** a reader of the temporal-composition article learns that nine tenths of the
change patches are one pixel wide and that the unsettled share is concentrated where classes
already meet — which is what decides whether a quoted hectare is worth acting on. **If we never
do:** the article's most visually striking feature stays unexplained, and the next reader forms
the corridor hypothesis from the reach figure with nothing to check it against.

## Context

[What a Land-Cover Change Figure Is Made Of](https://newgraphenvironment.github.io/drift/articles/temporal-composition.html)
(#66) states the temporal split and says, correctly, that **the spatial arrangement has not been
examined**. It mentions slivers and boundaries zero times. Two different gaps sit behind that
sentence and they are in very different states.

## Phase 1 — the half that is already measured

`data-raw/logs/break_class_groups/<group>/summary_patch_groups.csv` is committed for all four
groups and already stratifies by width and by boundary signature. Nothing needs recomputing:

| group | sliver patches | sliver area | `n_flips` sliver v wider | `break_frac` sliver v wider |
|---|---|---|---|---|
| bulk | 19,516 / 21,701 (89.9%) | 1,077.6 / 4,625.0 ha (23.3%) | 2.28 v 1.94 | 0.464 v 0.590 |
| necr | 19,676 / 21,990 (89.5%) | 973.5 / 5,779.4 ha (16.8%) | 2.20 v 1.83 | 0.478 v 0.629 |
| lnth | 11,589 / 12,434 (93.2%) | 510.1 / 1,629.7 ha (31.3%) | 2.23 v 2.10 | 0.478 v 0.532 |
| kotl | 15,772 / 17,042 (92.5%) | 846.5 / 3,537.8 ha (23.9%) | 2.03 v 1.92 | 0.544 v 0.588 |

The headline is the first two columns: **90-93% of change patches are one pixel wide, and they
carry only 17-31% of the changed area.** They also flicker more and settle less, in every group.

`dft_transition_artifact()`'s `flag_boundary` already means *"traces a pre-existing land-cover
interface"* — a patch hugging an existing boundary scores high, a real thin change that **cuts
across** one scores near zero. So "other land cover boundaries" is measured too:
`artifact_signature` (sliver **and** boundary-hugging or reciprocal) is 9,351-15,567 patches and
400-822 ha per group, with `break_frac` 0.464-0.544 against 0.515-0.629 for the rest.

Phase 1 is a paragraph and one panel in the existing article, plus the corresponding row in the
exact-values table. No new computation, no new committed data.

## Phase 2 — the half that is not measured at all

**Nothing in this repo measures distance to the channel.** #62's Q3 was originally designed around
the per-stream `<sp>_ff04_by_blue_line_key` layer and was dropped before the run: tributary
floodplains nest inside the mainstem's and overlap 1.7-2.2x, `valley` is constant, and kotl has no
such layer. `summary_shape.csv` replaced it with whole-floodplain ff02/ff04/ff06 geometry, which
cannot answer a within-floodplain question.

So the thing the reach figure shows — unsettled cells tracing the channel margins — is currently
an eyeball reading of one 4 km window, and the article is right not to assert it.

**The confound is the work.** Flicker at a Water/Trees interface has two very different causes:

- a boundary that never moved, oscillating from mixed-pixel noise — an artifact; or
- a boundary that *walked* — channel migration, which is real change and arguably the most
  interesting thing in the dataset.

`break_year` and `n_before`/`n_after` already distinguish a monotone walk from an oscillation per
pixel, so the separation is reachable — but it is a design question, not a filter. #67 found
flicker is markedly **lower** in disturbed patches, so the naive "flicker means noise" reading is
already on thin ice and should not be assumed here.

Sketch, to be settled at the plan gate:

1. Distance transform from the from-epoch Water class (and/or a stream network), per group.
2. Unsettled share as a function of that distance, against a null from the same floodplain.
3. Separate oscillation from directional walk using the existing `$breaks` layers.
4. Extend the article's section once, with both grains told together.

## Why one issue and not two

"Narrow patches flicker more" and "flicker concentrates along the corridor" are the same story at
two grains. Landing them as separate article edits means the second rewrites the first section.
Phase 1 can ship on its own if phase 2 runs long — the article gains the measured half and says
plainly that the corridor question is open.

## Depends on

**#72 should be settled first.** It decides whether `$summary$status` keeps pooling
changed-unsettled with stable-endpoint flicker. Phase 2 is a flicker-concentration analysis, so it
needs that distinction fixed at the source rather than re-derived here — this would otherwise be
the fourth place composing it by hand.

## Acceptance

- Article gains a section on patch width and boundary signature, every value traced to a committed
  CSV emitted by a committed script.
- Body prose stays within the 1000-word cap (currently 731).
- Any corridor claim is either measured, with its null stated, or absent. **The article's "the
  spatial arrangement has not been examined" sentence is removed only when it stops being true.**
- Cartography per `cartography.md`, post-render self-review against all 12 points.

## Related

#66 (the article), #62 (Q3, and why the per-stream layer was dropped), #64, #67 (flicker lower in
disturbed patches), #72 (pooled flicker populations),
NewGraphEnvironment/stac_floodplains_bc#67. Relates to NewGraphEnvironment/sred-2025-2026#16.


# Findings — expose the temporal split as a function (#72)

## Measured at the plan gate

**terra `app()` 2-column transpose trap — CONFIRMED.** terra 1.9.34, this repo. A `fun` returning
2 columns on a raster exactly 2 columns wide is read as transposed and silently scrambled:

```
ncol=1 nlyr=2 layer_a_correct=TRUE
ncol=2 nlyr=2 layer_a_correct=FALSE     <- scrambled, no warning
ncol=3 nlyr=2 layer_a_correct=TRUE
ncol=4 nlyr=2 layer_a_correct=TRUE
ncol=5 nlyr=2 layer_a_correct=TRUE
ncol=6 nlyr=2 layer_a_correct=TRUE
```

`dft_rast_break_class()` pads at `ncol == 5L` because *its* return is 5 columns
(`R/dft_rast_break_class.R:206`). A 2-column return needs its own pad condition at `ncol == 2L`.
The existing width sweep in `test-dft_rast_break_class.R:300-321` covers 4/5/6 and cannot reach it.

**The pooling case is pinnable on data that ships.** Two independent routes, both in-package:

- `inst/extdata/temporal-composition/summary_groups.csv` (BULK row): `changed_ha = 4625`,
  `stable_flicker_ha = 3186.5`, so pooled = 7811.5, ratio 1.689.
- The bundled seven-year series already pins both populations at 1/100 scale
  (`test-dft_rast_break_class.R:369-396`): 3,403 changed, of which 1,265 flicker
  (-> `unsettled`), plus 2,791 that flicker while the endpoints agree (-> `stable_flicker`);
  1,098 sustained; 776 + 264 endpoint-only.

So no new data file is needed, and the summary <-> pixel parity test can be end-to-end.

**The four re-derivations agree today; the defect is the vocabulary, not the arithmetic.** The
`summarize` stage reconciles the aggregate rollup to the pixel-grain `summary_change.csv` on
integer cell counts in all four groups, with a positive and a structural control
(`data-raw/break_class_groups.R:337-376`), and `article-bulk` refuses to run unless it reproduces
`summary_change.csv` cell for cell (`:456-470`). The PR must not claim to fix wrong numbers — the
cost is duplication plus a hand-written equality check, and a four-level name that invites a
reader to drop the `changed` column and sum.

**The endpoint test and the `pmin >= 2` test are provably the same rule.** For a break at index
`idx`, `n_before = idx`, `n_after = n - idx`, `break_year = years[idx + 1]`, so `strength < 2` is
exactly `break_year %in% c(years[2], years[n])` at every series length. `temporal_category()`'s
endpoint test and `cat_fun()`'s threshold are one rule written twice.

**The unit is observations, not years.** On a gapped series `2017, 2020, 2023` a break at 2020
gets `strength = 1` — "endpoint-only" — though three calendar years flank it each side.
`dft_rast_break_class()` accepts a gapped series (`:138` checks only `^[0-9]{4}$`). Any prose
tying strength to years is wrong there, including `R/dft_rast_break_class.R:36-38` and
`inst/extdata/temporal-composition/README.md:26-27`.

**`break_sustained` is unreachable for `n < 4`**, since `max_strength = floor(n/2)`.
`dft_rast_break_class()` explicitly supports `n == 2` (`test-dft_rast_break_class.R:249-257`), so
the level set will legitimately carry an empty level on supported input.

## Design review

Full review from the Plan agent is in `review-round1.md`. Adopted: the grain split, the `rule`
column over an attribute, the single `app()` pass, the pad-at-2 condition, the NA-status contract,
the `filename =` argument, the `$years`-absent error path, and the ordering that puts the
committed-CSV equivalence gate before anything needing floodplain-scale rasters.

Not adopted: a `strength` column on `$summary`. `dft_break_category()` returns it and
`dft_break_strength()` computes it, so the acceptance criterion is met without widening a table
the issue says to leave alone.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Issue context

**If we do it:** the temporal split is computed in one place instead of four, the confidence
number we already measure survives into the answer, and the vocabulary can improve later without
breaking anyone. **If we never do:** every consumer keeps re-deriving the split by hand, the next
one to sum "flicker" overstates changed area by roughly 70%, and the strength measure stays
discarded.

## Two problems, one cause

`dft_rast_break_class()` deliberately thresholds nothing — it reports measurements and the caller
composes. That design is right and this issue does not propose changing it. But `$summary$status`
collapses to `stable` / `break` / `flicker` via `pmin(n_flips, 2)`, and that collapse does two
unhelpful things at once.

**1. `flicker` pools two populations that are used differently.**

- endpoints *differ* and never settle — part of what a two-epoch layer reports as change;
- endpoints *agree* while the years between flicker — invisible to a two-epoch comparison entirely.

On BULK that is 2,032.9 ha against 3,186.5 ha. Summing them gives 7,811.5 ha of "changed" area
where the published layer says 4,625.0 — a **69% overstatement**. Found in #66 by a conservation
check, not by review: the pooled number is plausible and nothing downstream contradicts it.

**2. The confidence number is computed and then thrown away.**

`pmin(n_before, n_after)` is documented as confidence and runs 1-3 on a seven-year series.
"Sustained" is that number thresholded at `>= 2`. Three pixels a 2017-vs-2023 comparison reports
identically as Trees to Rangeland:

| pixel | the seven years | `n_flips` | `pmin(n_before, n_after)` | today |
|---|---|---|---|---|
| A | T T **R R R R R** | 1 | 3 | sustained |
| B | T T T T T T **R** | 1 | 1 | endpoint-only |
| C | T R T R T R R | 4 | — | flicker |

A and B are both one clean switch and are separated *only* by that number. Collapsing it to a
label loses the distinction between "held for five years" and "held for one".

## What cannot go here, and why

Attribution to an external source — a dated fire, a cutblock — **cannot live in `$summary` at any
vocabulary**, because the grain is wrong. A row there is not a place:

> `Trees -> Rangeland, break, 2019 — 13,480 cells`

Those cells are scattered across the whole floodplain. Some sit inside a mapped fire, most do not.
There is no single fire answer for that row, so there is nowhere to write one. Attribution needs
to know *where*, which means a patch — and #67 already put it there. So `status` will never need
to carry confirmation; it structurally cannot.

## Why not a single weight-of-evidence score

Tempting, and measurably wrong in **both** directions at once:

- **#62 Q4** — the geometric and temporal legs are independent to nearly independent (clean-break
  share 0.494 vs 0.575 bulk, 0.490 vs 0.621 necr, 0.518 vs 0.515 lnth). The note's conclusion:
  *"Neither leg predicts the other well enough to stand in for it — a patch needs both tags."* A
  scalar merges two things that must stay apart.
- **#67** — date agreement and the sustained/endpoint split are **not** independent: *"the split
  is `break_year` thresholded, so agreement on dates and the sustained share are one measurement
  read two ways. Do not report them as two corroborating legs."* A scalar double-counts here.

Coverage is a third problem: #67 measured lag-0/+1 agreement for 86.2% of discriminating fire
patches and 72.0% of harvest, and most patches carry no tag at all. A `confirmed` level would be
`NA` for the large majority and confidently worded for a minority where it is roughly
three-quarters right.

## Proposal — three layers, each at its own grain

| layer | grain | shape | changes over time? |
|---|---|---|---|
| measurements | pixel | `n_flips`, `break_year`, `n_before`, `n_after` | no — meaning is fixed |
| labels | pixel, computed on demand | sustained / endpoint-only / unsettled / stable-flicker | yes — **version the rule** |
| corroboration | **patch** | fire, harvest, width, boundary — one named column per axis | yes — add axes, never blend |

Concretely:

1. **Export the composition as a function**, not a column — something like
   `dft_break_category(x)` taking `$summary` or `$breaks` and returning the label plus the
   strength. A function's return vocabulary can grow behind a version; a data-frame column's
   meaning cannot change without silently breaking every reader. This also fixes the
   "four callers re-derive it" problem better than a column does.
2. **Carry `pmin(n_before, n_after)` through** as its own value, not only its threshold.
3. **Do not widen `status`.** This issue exists *because* `status` pooled two populations;
   widening it repeats the mechanism it was filed against.
4. Leave `$summary` otherwise alone, so nothing currently reading it breaks.

An earlier draft of this issue recommended adding a `changed` logical column to `$summary`.
That is a *fact* rather than a judgement — `from_class != to_class`, binary forever — so it would
be safe, but it is the weaker option: it fixes the pooling and leaves the confidence number
discarded and the composition still duplicated in every caller.

## Who re-derives this today

- `data-raw/break_class_groups.R` — twice (the `summarize` rollup and the `article-bulk` figure
  categories)
- the #66 article and `inst/extdata/temporal-composition/bulk_grid_1km.csv`, as `unsettled` vs
  `stable_flicker`
- NewGraphEnvironment/stac_floodplains_bc#67, which proposes publishing `nge:change_flicker_ha` —
  the pooled reading would be wrong for a consumer differencing it against
  `nge:change_sustained_ha`

## Open at the plan gate

- Function name and return shape — a tibble column set, or a factor plus an integer?
- Does it take `$summary` (aggregate) or `$breaks` (per pixel), or both?
- How is the rule versioned so a later change to the threshold is visible to a reader of old
  output?
- Does `dft_rast_break_class()` gain the labels in a new list element, or stay untouched with the
  function as the only route?

## Acceptance

- One definition of the split in the package; the three re-derivations above call it.
- `pmin(n_before, n_after)` reachable without recomputing it from `$breaks`.
- Existing `$summary` readers unaffected.
- The pooled and unpooled totals both reproducible, and their difference asserted in a test —
  4,625.0 against 7,811.5 ha on BULK is the case to pin.

## Related

#62 (where the split was measured, and Q4), #64 (the corrected series, which must treat the two
flicker populations differently), #66 (where the pooling was found), #73 (needs this settled
first), NewGraphEnvironment/stac_floodplains_bc#67.
Relates to NewGraphEnvironment/sred-2025-2026#16.


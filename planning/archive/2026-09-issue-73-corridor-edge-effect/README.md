# Sliver-shaped patches and where flicker concentrates (#73)

Closed by PR (v0.17.0). Extended the temporal-composition article with the two spatial grains it
never raised — how change patches are shaped, and where in the floodplain the instability sits —
and answered the corridor question **negatively**, which is the outcome worth recording.

The issue framed this as one measured half and one open half. Both premises moved during the work.
The measured half needed its vocabulary corrected (the issue's own boundary-signature numbers were
wrong and the effect reverses in one group), and the open half turned out to be cheap to compute
and to come back the other way from the hypothesis.

## Measurement

Distance from a stable water core (Water in all seven years), eight bands, four floodplains,
169M-204M cells each. Flicker = unsettled + stable_flicker, as a share of scanned cells in band:

| reference | 0-10 m | 30-50 m | >500 m |
|---|---|---|---|
| permanent water | 51.2-59.5% | 21.3-31.8% | 10.1-17.7% |
| **non-water class boundary (the null)** | 37.1-46.4% | 20.0-24.1% | **0.4-2.4%** |

Within Trees alone — the class that cannot be part of the reference — 46.3-59.7% against
3.3-11.1%.

**The gradient is real and it is not about water.** The null produces the same shape and falls
further, to near zero, while the water profile levels off at 10-18% — which is what a cell far
from the river but near some other boundary looks like. Flicker concentrates at class boundaries;
the channel is simply the longest, most sinuous, highest-contrast one a floodplain has. What the
reach figure shows is an edge effect in a river's shape.

`break_year` rules out the reading that would have been most interesting: a migrating bank dates
its switches progressively outward, and these date *later* near the water than far from it, in all
four groups.

Three numbers changed how the work was expressed:

- **`terra::distance()` over 169M cells is 8.3 s.** The whole four-group stage is 671.6 s at 16.6 GiB.
  The issue reserved its caution for this half; the compute was never the constraint, and knowing
  that early is what made room for the null and the break-year arm.
- **The core is 67.0% of kotl's floodplain** against 14.4-33.7% elsewhere. That is Kootenay Lake,
  so "distance to the channel" does not transfer to that group. Reported, not corrected.
- **The boundary-signature range in the issue body was two rows conflated**, and the effect
  reverses in lnth (0.518 against 0.515). Width is the leg that holds in all four.

## Errors worth keeping

- **The reference excises the population it is compared against.** The stable water core is every
  permanent-water pixel, so the near bands are by construction the cells beside permanent water
  that are *not* permanent water — the one band where the modal stable class has been removed. The
  planning file had called that identity the thing that made the reference *non*-circular, which
  was a non-sequitur running the wrong way. Caught by the plan review, verified directly: the
  `Water` stratum reads **0% stable in every band outside the core**, necessarily. The fix was not
  a different reference but a different stratum — Trees, which cannot be in the core.
- **A control is not a null.** A three-way crosstab on `from_class` says the gradient is not an
  artifact of which classes sit near water. It cannot say whether water is special. Only a
  reference with the water removed can, and that is the arm that produced the negative result.
- **`break_sustained` does not mean a walk.** A classifier that changed its mind once and
  permanently produces the same label. An earlier claim that the issue's step 3 "needs no new
  machinery" was withdrawn.
- **"Monotone in every column" was false** and had been written into the planning file from a table
  that contradicts it — `break_sustained` has a local maximum at 200-500 m, which itself argues
  against reading the result as "change concentrates on the channel".
- **A correction was drafted against a claim the issue never made.** The plan scheduled an issue
  edit saying the body "has the cost inverted"; the body never mentions compute. Withdrawn before
  it was filed.
- **A `pgrep -f "break_class_groups.R corridor"` waiter matched nothing**, because the real command
  line is `--file=... --args corridor`. The run was reported finished while still going. Waiting on
  the PID is the form with no failure mode.
- **The null arm's reference leaked outside the AOI, and the comment claimed otherwise.**
  `focal(na.rm = TRUE)` protects an *inside* perimeter cell from being flagged; it does nothing for
  an *outside* one, because `focal()` computes for NA-centred cells too. 3.8-5.2% of the reference
  was beyond the floodplain, tracing its perimeter one cell out. Found by the code review, which
  reconciled the logged reference count against the published band-1 count to measure it.
- **`Clouds` counted as a land-cover class in the null**, and cloud edges flicker by construction —
  contamination in the direction that makes the null look more like the channel, which is the
  direction that would have spuriously supported the conclusion. Excluded.
- **A guard that was vacuous on exactly its own failure case.** `all(x %in% y)` over `na.omit()` is
  TRUE on an empty vector, and `terra::distance()` on an all-NA mask returns NaN everywhere with no
  error and no warning. The guard for "bands outside the declared set" therefore passed on the
  degenerate raster it existed to refuse.
- **The conservation check could not see the loss its error message named.** It counted NA-band
  rows; the published rollup dropped them. A cell lost to the banding conserved in the guard and
  vanished from the table.
- **`terra::tmpFiles(remove = TRUE)` reclaimed nothing** — it only tracks files terra named itself,
  and every intermediate here uses an explicit `tempfile()`. The stage header claimed otherwise.
- **Reading the rendered figure caught an imprecise sentence** that reading the code could not:
  the null line is *lower everywhere*, not merely steeper, and "not weaker but steeper" would have
  implied otherwise.

Two review rounds, both landing after the code was written, which is the useful order: a plan
review that read the implementation rather than the plan, and a code review of the committed diff.
Between them they moved the headline (from an all-class band share to a within-Trees one), added
the null and the break-year arm, and found four guards that could not fail. Nine of the plan
review's findings and eight of the code review's were acted on; the rest were verified as already
satisfied.

## Evidence

`data-raw/logs/break_class_groups/corridor/` (timings, RSS trace, wall clock) and
`data-raw/logs/break_class_groups/*/summary_corridor*.csv`. Shipped copies under
`inst/extdata/temporal-composition/`. Write-up in `inst/notes/temporal-qa-groups.md` Q6; the
public statement is the article's two new sections.

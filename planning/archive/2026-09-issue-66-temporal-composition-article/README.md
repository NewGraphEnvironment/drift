# pkgdown article: temporal composition of published land-cover change (#66)

Closed by PR (v0.15.0). Produced
[What a Land-Cover Change Figure Is Made Of](https://newgraphenvironment.github.io/drift/articles/temporal-composition.html),
which states #62's result for a reader who consumes the published floodplain products and does not
use the package: a two-epoch land-cover comparison contains a large fraction of area whose class
assignment is not stable across the intervening years. BULK is the worked example; the other three
full-series groups test generality. Three figures, 731 words of body prose against a 1000 cap
enforced at render, every quoted value traced to a committed CSV emitted by a committed script.

Two new stages of `data-raw/break_class_groups.R` produce that data into
`inst/extdata/temporal-composition/`: `summarize` gained a per-transition-class temporal
breakdown, and a new `article-bulk` derives the BULK figure data. No existing committed number
moved — the three summarize outputs are byte-identical throughout.

## Measurement

Tree loss (Trees -> non-Trees, excluding Clouds), share of area by temporal category, from
`summary_treeloss_temporal.csv`:

| group | sustained | endpoint-only | unsettled | total |
|---|---|---|---|---|
| bulk | 20.3% | 37.4% | 42.3% | 2,050.4 ha |
| necr | 32.1% | 31.2% | 36.7% | 2,381.0 ha |
| lnth | 15.9% | 27.5% | 56.5% | 439.1 ha |
| kotl | 35.4% | 32.3% | 32.3% | 770.7 ha |

Three numbers changed how the work was expressed:

- **The identity is exact.** Rolling `summary_pixels.csv` up by `break_year in {2018, 2023} =
  endpoint-only` reproduces each group's committed `summary_change.csv` on **integer cell counts,
  delta 0**, in all four groups. That is what let the guard be `identical()` with no tolerance.
- **The 2,050.4 ha in the issue body is real**, and reconciles against the published
  `gross_loss_ha` of 1,565.1 ha at 1.31x — the 1 ha sieve and sub-basin clip #67 established, not
  a disagreement. So the article reports both, with the definition each is computed under.
- **`cat_fun()`'s category 3 pools two populations.** On BULK it carries 2,032.9 ha of
  changed-but-unsettled together with 3,186.5 ha that flickers while reading identical at both
  endpoints. Summing it as one "flicker" overstates changed area by **69%** (7,811.5 against
  4,625.0 ha). Caught by a conservation check, not by review.

## Errors worth keeping

The wrong turns are the evidence of investigation, so they are recorded rather than tidied away:

- A guard asserting the 1 km block count was within 2x of `area / 100` **fired on a correct grid**.
  That ratio holds for a solid blob; a dendritic floodplain touches 2,562 blocks where its area
  implies 411. The proxy was replaced by conservation of three hectare totals.
- `terra::plot(type = "classes", levels =, col =)` maps colours **positionally onto each layer's
  own unique values**, so five of the seven year panels drew Rangeland in Snow/Ice's blue — in the
  figure the article exists to show. Found by reading the rendered PNG, not the source, and fixed
  with a value-keyed `coltab`.
- `terra::wrap()` carries the basename of whatever `filename =` produced, so an `app()` written to
  `tempfile()` leaked a per-process random path into the committed `.rds` and it churned on every
  run while values, extent and CRS all round-tripped identically.
- A malformed row in the registry CSV (26 fields against a 24-field header) put a **phantom layer**
  into the gq registry with no warning; the palette survived by accident because gq groups by
  `layer_key`.
- pkgdown **drops a footnote's body while keeping its marker**, so the two-totals reconciliation was
  invisible on the published page until it was promoted to a block quote.

Three `/code-check` rounds, 16 findings. Round 2 found a defect inside round 1's fix and round 3
found one inside round 2's, so the loop was closed by enumeration rather than by a quiet round —
the mechanism named was *a claim states a scope; the thing that enforces it covers a different
scope; nothing compares the two*, and `claim_audit.py` verifies every path reference and every
numeric claim in the shipped prose against the data.

## Evidence

- `planning/archive/2026-09-issue-66-temporal-composition-article/review-round{1,2,3}.md`
- `inst/extdata/temporal-composition/` — the shipped data, with its own README
- `data-raw/logs/break_class_groups/` — unchanged by this issue, and asserted so

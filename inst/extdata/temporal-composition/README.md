# temporal-composition — data for the pkgdown article (drift#66)

Everything the pkgdown article for drift#66 quotes or plots. The article reads only from this
directory (plus `dft_class_table()`), so it renders with no network and no access to the
gitignored rasters.

Produced by `data-raw/break_class_groups.R`, which is not part of the package build:

| file | stage | what it holds |
|---|---|---|
| `summary_groups.csv` | `summarize` | one row per group — a **column subset of the same in-memory object** that writes `data-raw/logs/break_class_groups/summary_groups.csv`, so the two cannot disagree |
| `summary_class_temporal.csv` | `summarize` | cells and hectares per `group x from_class x to_class x temporal category` |
| `summary_treeloss_temporal.csv` | `summarize` | Trees -> non-Trees composition under two **named** class sets |

Regenerate with `Rscript data-raw/break_class_groups.R summarize`.

## Two things worth knowing before quoting these numbers

**The temporal category is composed here, not by the package.** `dft_rast_break_class()` reports
`break_year`, `n_before`, `n_after` and `n_flips` and applies no threshold; the caller composes.
For a consecutive series, `break_year` is the first year of the new class, so the series' second
year leaves `n_before = 1` and its last leaves `n_after = 1` — both fail
`pmin(n_before, n_after) >= 2` and are **endpoint-only**. Everything between is **sustained**.
`n_flips >= 2` is **unsettled** (`flicker`). The `summarize` stage refuses to write any of these
files unless that rollup reproduces each group's committed `summary_change.csv` on integer cell
counts, and it proves the comparator can fail by perturbing a count and requiring a mismatch.

**`class_set` is a column, not a footnote.** Excluding `Trees -> Water` moves the sustained share
by -1.3 to +6.0 points across the four groups, so a tree-loss share is meaningless without the
class set it was computed over. Both sets are in the file; the article's headline uses
`trees_to_non_trees_excl_clouds`, matching the definition the published `gross_loss_ha` uses.

No patch-size threshold is applied anywhere in this directory. These are pixel-level totals over
the whole published floodplain, so they are **not** comparable to a patch-level figure from
`transition_vector.gpkg`, which carries a 1 ha sieve and a sub-basin clip (drift#67).

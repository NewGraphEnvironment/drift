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
| `bulk_grid_1km.csv` | `article-bulk` | Bulkley floodplain aggregated to 1 km, hectares per category |
| `bulk_window.csv` | `article-bulk` | the selected example patch, its extent, and the selection rule as a literal sentence |
| `bulk_window.rds` | `article-bulk` | `terra::wrap()`ped crops for the patch and reach figures, plus the patch outline |
| `summary_patch_widths.csv` | `summarize` | change patches grouped by width and artifact signature — a reshape of the four committed `summary_patch_groups.csv` files, from the same read that feeds `summary_groups.csv` |
| `summary_corridor.csv` | `corridor` | temporal category by distance band, under **three** references |
| `summary_corridor_class.csv` | `corridor` | the same, kept split by from-epoch class |
| `summary_corridor_breakyear.csv` | `corridor` | `break_year` by distance band, for clean breaks only |
| `summary_patch_sieve.csv` | `article-slivers` | patch counts, area and temporal evidence at 0, 0.5 and 1 ha area sieves |
| `summary_patch_area_bands.csv` | `article-slivers` | the same, split by area band instead — the control a sieve cannot give |
| `bulk_slivers.csv` | `article-slivers` | the two example patches, their measurements and the selection rule |
| `bulk_slivers.rds` | `article-slivers` | `terra::wrap()`ped crops for those two, plus their outlines |
| `watershed_groups.csv` | `article-context` | the four groups' codes and **names**, with the BCDC record they came from |
| `watershed_groups.rds` | `article-context` | BC outline, the four group polygons, and the Bulkley floodplain outline, simplified for a locator |
| `bulk_basemap.tif` | `article-context` | shaded relief behind the floodplain overview, reprojected and JPEG-compressed to 40 KB |

Regenerate with `Rscript data-raw/break_class_groups.R summarize`, then
`Rscript data-raw/break_class_groups.R article-bulk`, then
`Rscript data-raw/break_class_groups.R corridor`, then
`Rscript data-raw/break_class_groups.R article-slivers`, then
`Rscript data-raw/break_class_groups.R article-context`.

## The corridor files carry three references, and which one you read is the finding

`summary_corridor.csv` has a `reference` column with three values. They are not three attempts at
one measurement; the third is the null for the first.

- **`water_core`** — pixels classed Water in **all seven** years. Every core cell is stable by
  construction, and the core count is identical to that group's `Water,Water,stable` row in
  `summary_pixels.csv`, which is the same set by definition.
- **`water_2017`** — the from-epoch Water class. Partly circular: a margin pixel that oscillates
  Water/non-Water is both *near 2017 water* and *unsettled*. Kept as a sensitivity arm.
- **`edge_nonwater`** — a from-epoch class boundary with **no water on either side**. This is the
  null. A share split by `from_class` is a *control* for composition; it cannot say whether water
  is special. This can: if flicker rises toward any edge the way it rises toward the channel, the
  corridor framing is not what is going on.

**Read the null before quoting a corridor number.** It does not separate — flicker rises toward a
non-water class boundary at least as steeply as toward the channel — so these files support an
*edge* effect and not a channel-specific one.

## Two things `summary_corridor*.csv` will mislead you about if you skip this

**The `core` band is a definition, not a measurement.** Under `water_core` it reads 100% stable
because that is what the core is. It is the internal control. Do not plot it and do not quote it.

**The all-class band share is biased against `stable` in the near bands.** The core removes every
permanent-water pixel from the band population, so the 0-10 m ring is by construction the set of
cells beside permanent water that are *not* permanent water — the one band where the modal stable
class has been excised. `summary_corridor_class.csv` is the honest read: restrict to a class that
**cannot** be in the core. `Trees` is the one to use. `Water` there is a tautology — it reads 0%
stable in every band outside the core, necessarily, because a 2017-Water cell that is not core
either changed or flickered.

## A sieve is not a width filter, and the width result does not survive one

`summary_patch_sieve.csv` and `summary_patch_area_bands.csv` exist because narrow and small are
nearly the same thing here. The median sliver is **two cells**. A 1 ha area sieve — which the
published `transition_vector.gpkg` already applies — keeps 2.2-4.1% of patches and 52.9-72.0% of
the changed area, and only 1.9-7.4% of what survives is a sliver.

**Do not quote the unsieved sliver-versus-wider gap as a width effect.** Hold area fixed instead
and it reverses: in the 0.2-0.5 and 0.5-1 ha bands the clean-break share is *higher* for slivers in
6 of 8 group-and-band cells. Below 0.1 ha every patch but three is a sliver, so there is nothing
for width to separate. `summary_patch_area_bands.csv` is the table that shows this;
`summary_patch_widths.csv` is the unsieved comparison and is only safe to read beside it.

## `kotl`'s reference is a lake

Permanent water as a share of the floodplain: bulk 14.4%, necr 25.3%, lnth 33.7%, **kotl 67.0%**.
Kootenay Lake is two thirds of that floodplain, so "distance to the channel" reads as "distance to
a regulated lake shore" for `kotl`. Reported, not corrected.

## Three things worth knowing before quoting these numbers

**The temporal category is `drift::dft_break_category()`, not this script's own rule.**
`dft_rast_break_class()` still reports `break_year`, `n_before`, `n_after` and `n_flips` and
applies no threshold; the composition is a judgement and lives in one exported, versioned place
(drift#72). `strength` is `pmin(n_before, n_after)` — [`dft_break_strength()`] recovers it from
`break_year` — and it is thresholded at 2: a clean switch scoring 1 is **endpoint-only**, one
scoring 2 or more is **sustained**, and `n_flips >= 2` is **unsettled** or **stable_flicker**
depending on whether the endpoints differ. The `rule` column records which rule produced the
label, so a CSV written today identifies itself if the rule ever moves.

For a consecutive series that threshold is exactly an endpoint test — `break_year` is the first
year of the new class, so the series' second year leaves `n_before = 1` and its last leaves
`n_after = 1` — and the `summarize` stage asserts the two agree rather than assuming it. It then
refuses to write any of these files unless the rollup reproduces each group's committed
`summary_change.csv` on integer cell counts, and it proves the comparator can fail by perturbing
a count and requiring a mismatch.

The committed per-group `summary_change.csv` files predate the export and record a run made under
a **four-level** vocabulary, in which `flicker` was every `n_flips >= 2` and the two populations
were told apart only by the `changed` column. They are the record of what was measured and are
not rewritten; `read_change()` maps them on read, and that map is a bijection with
`(changed, four-level)`, so nothing is lost either way.

**`class_set` is a column, not a footnote.** Excluding `Trees -> Water` moves the sustained share
by -1.3 to +6.0 points across the four groups, so a tree-loss share is meaningless without the
class set it was computed over. Both sets are in the file; the article's headline uses
`trees_to_non_trees_excl_clouds`, matching the definition the published `gross_loss_ha` uses.

**Five categories, not four.** The retired four-level vocabulary's `flicker` was every pixel with
`n_flips >= 2` *whether or not the endpoints differ*, so it pooled two populations the article has
to keep apart:
2,032.9 ha that changed and never settled, and 3,186.5 ha that flickers while reading identical
at both endpoints. The raster columns and the `.rds` crops therefore carry `unsettled` and
`stable_flicker` separately. Summing them as one "flicker" overstates changed area by 69% on
BULK, and the stage's conservation checks refuse to write if any of the three totals — floodplain,
changed, stable-flicker — misses its committed value.

No patch-size threshold is applied to any of the three `summary_*.csv` tables: they are
pixel-level totals over the whole published floodplain, and so are **not** comparable to a
patch-level figure from `transition_vector.gpkg`, which carries a 1 ha sieve and a sub-basin clip
(drift#67). The `bulk_window.*` files are the exception and are not a total of anything — they
describe one patch chosen from a 1-4 ha band, for a figure.

`article-bulk` needs ~16 GiB of RAM and the gitignored BULK COGs, so it never runs in CI — same
posture as `data-raw/vignette_data_break.R`. It refuses to proceed unless the scan reproduces
`data-raw/logs/break_class_groups/bulk/summary_change.csv` cell for cell.

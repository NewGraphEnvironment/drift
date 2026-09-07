# Findings — pkgdown article: temporal composition (#66)

## Baseline hashes (Phase 0)

Recorded at `88e64e1` before any edit. These three files are rewritten on **every** `summarize`
run, so they are the "nothing moved" test for Phases 2 and 3.

| file | md5 |
|---|---|
| `data-raw/logs/break_class_groups/summary_groups.csv` | `e4e0fdd2cdf2af7a0292e79462c157ae` |
| `data-raw/logs/break_class_groups/summary_groups.md` | `56ac737da35eac546ee89518dc99e749` |
| `data-raw/logs/break_class_groups/summary_bulk_reconcile.csv` | `c6d86127b82e151bd06482a3137c3d18` |

## The derivation identity, verified

For the consecutive 2017-2023 series, `break_year` is the first year of the new class, `n_before`
is the count of years in the old class and `n_after` the new. With seven years, `break_year` 2018
gives `n_before = 1` and 2023 gives `n_after = 1`, so `pmin(n_before, n_after) >= 2` fails at both
— an **endpoint-only** switch. 2019-2022 gives `pmin >= 2` — a **sustained** break.

Rolling `<group>/summary_pixels.csv` up that way reproduces the committed
`<group>/summary_change.csv` hectares exactly in all four groups:

| group | derived sustained / endpoint | committed sustained / endpoint |
|---|---|---|
| bulk | 909.35 / 1682.69 | 909.35 / 1682.69 |
| necr | 1789.83 / 1698.96 | 1789.83 / 1698.96 |
| lnth | 335.16 / 504.69 | 335.16 / 504.69 |
| kotl | 872.20 / 1169.99 | 872.20 / 1169.99 |

The Plan review confirmed the same holds on integer `n_cells` with **delta 0**, so the guard is
`identical()` on integers with no tolerance to tune.

## The issue's `2,050.4 ha` is real

It is not written to any committed file, which is precisely why the issue requires a script to
emit it. Derived from `bulk/summary_pixels.csv` as `from_class == "Trees"`, `to_class` not in
`Trees`/`Clouds`, summed over every status:

| group | sustained | endpoint | flicker | total |
|---|---|---|---|---|
| bulk | 415.8 (20.3%) | 766.9 (37.4%) | 867.7 (42.3%) | 2050.4 ha |
| necr | 763.4 (32.1%) | 743.0 (31.2%) | 874.6 (36.7%) | 2381.0 ha |
| lnth | 69.9 (15.9%) | 120.9 (27.5%) | 248.3 (56.5%) | 439.1 ha |
| kotl | 273.1 (35.4%) | 248.8 (32.3%) | 248.8 (32.3%) | 770.7 ha |

Excluding Trees -> Water:

| group | sustained | endpoint | flicker | total |
|---|---|---|---|---|
| bulk | 370.2 (20.9%) | 651.6 (36.7%) | 751.8 (42.4%) | 1773.6 ha |
| necr | 730.5 (33.0%) | 690.4 (31.2%) | 795.3 (35.9%) | 2216.3 ha |
| lnth | 54.5 (14.7%) | 94.1 (25.3%) | 223.2 (60.0%) | 371.8 ha |
| kotl | 257.5 (41.4%) | 168.4 (27.1%) | 195.6 (31.5%) | 621.5 ha |

The sustained share moves by +0.6 / +0.9 / -1.2 / +6.0 points — the issue's stated "-1.2 to +6.0",
and kotl's "35.4% to 41.4%", both reproduce exactly.

`2050.4 / 1565.1 = 1.31`, consistent with the ~1.28x sieve-and-clip factor #67 established between
drift's unsieved change layer and the published `transition_vector.gpkg`.

## Errors Encountered

| Error | Resolution |
|-------|------------|

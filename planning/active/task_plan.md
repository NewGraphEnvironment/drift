# Task: Article: sliver-shaped patches and where flicker concentrates — the measured half, then the corridor question (#73)

The temporal-composition article (#66) states what fraction of a two-epoch land-cover comparison
is temporally unstable. It never raises the **spatial** axis: not how the change patches are
shaped, and not where in the floodplain the instability sits. #73 closes both gaps at two grains
— patch width and boundary signature (already measured), and distance to the channel (not
measured anywhere in this repo).

## Decisions taken at the plan gate

- Body-prose cap raised 1000 -> 1200; both sections go in the article rather than one to a note.
- No new export. The distance pass lives in `data-raw/`; #73 is an article issue.
- Corridor work lands as a **new `corridor` stage**, not an edit to the per-group stage, so no
  committed per-group CSV is rewritten by construction.

## What exploration established (2026-09-07, 64 GB machine, terra 1.9.34)

- Phase 1 needs no computation: `summary_patch_groups.csv` is committed for all four groups.
- `terra::distance()` on the full 169M-cell BULK grid is **8.3 s**; the whole band x category
  analysis ran in **108 s**. The issue body has the cost inverted.
- The corridor signal is large and monotone, from a stable-water-core reference whose 591,901
  cells reconcile exactly to `summary_pixels.csv`'s `Water,Water,stable`: unsettled 22.2% in the
  first 10 m ring against 4.6% beyond 500 m (4.8x); combined flicker 4.5x; `break_sustained` 4.0x.
- The issue's sketch step 3 needs no new machinery — `dft_rast_break_category()` already
  separates the directional walk (`break_sustained`) from the oscillation.
- The remaining confound is class composition, controlled with a three-way crosstab.
- The acceptance criterion cites a sentence that does not exist in the article.

## Phase 1: `corridor` stage

- [ ] Extend the arg dispatch to accept `corridor`
- [ ] Per group: read cached COGs, `dft_rast_break_class()`, `dft_rast_break_category()`
- [ ] Stable water core (Water in all seven years); assert its count against the committed
      `summary_pixels.csv` `Water,Water,stable` row
- [ ] `terra::distance()` -> `classify()` into 8 bands (0 / 10 / 30 / 50 / 100 / 200 / 500 / >500 m)
- [ ] Three-way `crosstab(band, from_class, category)`; coerce numeric columns directly
- [ ] 2017-Water sensitivity arm
- [ ] Conservation guard against committed `summary_change.csv`, with a positive control
- [ ] Write per-group `summary_corridor.csv` + root rollup; print `ALL STAGES DONE`
- [ ] Run via `break_class_groups-run.sh corridor`; record timings and peak RSS

## Phase 2: shipped article data

- [ ] `summarize` gains `summary_patch_widths.csv`, read from the committed patch-group CSVs
- [ ] `corridor` emits `summary_corridor.csv` into `inst/extdata/temporal-composition/`
- [ ] Update `inst/extdata/temporal-composition/README.md`
- [ ] Assert every pre-existing committed CSV is untouched

## Phase 3: the article

- [ ] Add the concession sentence to `## What this does not support` first
- [ ] New section: patch width and boundary signature
- [ ] New section: where the instability sits, with the null and the confound stated
- [ ] New figure: category share against distance band, gq palette, no hex literal
- [ ] Raise the `wordcount` guard to 1200 with the reason in the chunk comment

## Phase 4: notes, NEWS, issue reconciliation

- [ ] `inst/notes/temporal-qa-groups.md` corridor section
- [ ] `data-raw/logs/break_class_groups/README.md` stage documentation
- [ ] `NEWS.md` 0.17.0 and the version bump as the final commit
- [ ] Edit the #73 body: the non-existent sentence, and the inverted cost premise

## Validation

- [ ] Tests pass; `pkgdown::check_pkgdown()` clean
- [ ] Article renders; word count under 1200; 12-point cartography self-review on the new figure
- [ ] Restore-the-bug on the conservation guard
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

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
  `flag_sliver` is an effective-width proxy (`2A/P < 1.5` px), not literally "one pixel wide".
- `terra::distance()` on the full 169M-cell BULK grid is **8.3 s**; the whole band x category
  analysis ran in **108 s**. (An earlier draft said the issue had the cost inverted; the issue
  never mentions compute — that correction was withdrawn.)
- The corridor signal is large and monotone, from a stable-water-core reference whose 591,901
  cells reconcile exactly to `summary_pixels.csv`'s `Water,Water,stable`: unsettled 22.2% in the
  first 10 m ring against 4.6% beyond 500 m (4.8x); combined flicker 4.5x; `break_sustained` 4.0x.
- **Withdrawn after review:** `break_sustained` does not establish a walk — a classifier that
  changed its mind permanently produces the same label. The walk signature is `break_year`
  against distance, and it is now measured.
- The remaining confound is class composition, controlled with a three-way crosstab.
- The acceptance criterion cites a sentence that does not exist in the article.

## Phase 1: `corridor` stage

- [x] Extend the arg dispatch to accept `corridor`
- [x] Per group: read cached COGs, `dft_rast_break_class()`, `dft_rast_break_category()`
- [x] Stable water core (Water in all seven years); assert its count against the committed
      `summary_pixels.csv` `Water,Water,stable` row
- [x] `terra::distance()` -> `classify()` into 8 bands (0 / 10 / 30 / 50 / 100 / 200 / 500 / >500 m)
- [x] Three-way `crosstab(band, from_class, category)`; coerce numeric columns directly
- [x] 2017-Water sensitivity arm
- [x] Conservation guard against committed `summary_change.csv`, with **two** positive controls
      (one per comparator arm) and a band-degeneracy check
- [x] Write per-group `summary_corridor.csv` + root rollup; print `ALL STAGES DONE`
- [x] Run via `break_class_groups-run.sh corridor`; record timings and peak RSS
- [x] **Added after review:** the null — a from-epoch class boundary with no water on either
      side, as a third reference arm
- [x] **Added after review:** `break_year` by band, the walk-versus-oscillation test the
      category alone cannot make

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
- [ ] Edit the #73 body: the non-existent sentence, the wrong boundary-signature numbers, and
      the 1000-word cap this PR overrides. **Not** the cost premise — the issue never made it.

## Validation

- [ ] Tests pass; `pkgdown::check_pkgdown()` clean
- [ ] Article renders; word count under 1200; 12-point cartography self-review on the new figure
- [ ] Restore-the-bug on the conservation guard
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

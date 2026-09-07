# Progress — expose the temporal split as a function (#72)

## Session 2026-09-07

- CI scan clean on entry (last five runs green; pkgdown deployed 15:47Z).
- Plan-mode exploration: found **four** re-derivations, not the three the issue names —
  `cat_fun()` (twice), `temporal_category()`, `fig_fun()` and `is_sustained()`.
- Plan agent review returned 8 sections; transcribed to `review-round1.md` with a disposition
  line on each. Two findings not adopted, both with a stated reason.
- Independently reproduced the terra `app()` 2-column transpose trap before adopting the pad
  condition — the highest-risk item, and the existing sweep (widths 4/5/6) cannot reach it.
- User settled four API forks at the gate: split by grain, `dft_rast_` naming, `unsettled`
  vocabulary, `rule` as a column, `$years` only on `dft_rast_break_class()`.
- Created branch `72-break-category-expose-temporal-split` off main (verified 0 behind origin).
- Scaffolded PWF baseline with the approved phases.
- Next: Phase 1 — `dft_break_strength()`, `dft_break_category()`, `$years`.

### Phases 1-4 landed

- Phase 1-2 in `d04e68b`: three exports, `$years`, 998 tests passing (was ~900).
  Both guards proven by restoring the defect they exist for — the `ncol == 2` pad
  (2 failures without it) and the flicker pooling (9 failures across 4 tests).
- Reordered 3 before 2 in execution so every commit is green: the registry
  assertion in `test-dft_break_category.R` needs the `unsettled` rename, which is
  Phase 3's, so the cartography CSV landed with the exports.
- Phase 3 equivalence gate: `dft_break_category()`'s rollup reproduces the committed
  `summary_change.csv` **cell for cell in all four groups**, with the stage's positive
  and structural controls still firing. `summary_class_temporal.csv` — 539 rows in,
  539 out, key sets identical under the 4->5 level map, **zero rows whose `n_cells` or
  `area_ha` moved**. The committed per-group `summary_change.csv` files are not
  rewritten; `read_change()` maps them on read, and the map is a bijection with
  `(changed, four-level)`.
- Phase 4: `is_sustained()` -> `dft_break_strength() >= 2`, proven equivalent on every
  input `discriminates()` can reach, for series lengths 2-9. Its summarize stage
  re-run: outputs byte-identical.
- Code review round 1 (`review-code-round1.md`) found 6; 5 fixed, 1 self-resolved
  (a missing Rd link to a file that was untracked when the reviewer read the tree).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `expect_false(NA)` errors rather than fails, and `tapply()` returns `NA` for an empty factor level | Assert the property (endpoint equality) rather than an arithmetic identity over `tapply()` output |
| `inst/notes/temporal-qa-groups.md does not contain summary_groups.md verbatim` | Expected — the note embeds the generated tables byte for byte, so a renamed column means the note is rebuilt from the new `summary_groups.md`, not hand-edited |
| Two review agents given the same findings path; the first ran ~35 min and wrote after the second was spawned | One file per round is not enough when a round is re-spawned — rescued as `review-code-round1.md` before the collision |

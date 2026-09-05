# Code-check round 1 — Phase 1 of #44 (fixtures + failing tests)

Reviewed the **staged** diff (`helper-artifact.R`, `test-dft_transition_artifact.R`,
PWF checkbox flips). Every fixture premise below was measured with `pkgload::load_all()`
against the source tree, not read off the matrices.

## Verified (no action)

| claim in tests | measured |
|---|---|
| `terra::rast(m)` keeps `m[i, j]` as raster (row i, col j) | yes — `matrix(1:6, 2, 3)` round-trips identically |
| Fixture A: one `Trees -> Rangeland` patch, 40 cells | 1 patch, 40 cells, perim 820, width 9.756 m = 0.9756 px |
| Fixture A `boundary_frac == 1` (focal per to-class, d = 1) | 1 |
| 2-px band `boundary_frac` 0.5 at d = 1, 1 at d = 2 | 0.5 / 1 — and the same under a Euclidean cell-centre or interface-line definition, so the pin is robust to the implementation choice |
| Fixture B: two 40-cell bands, edge-to-edge 40 m | `st_distance` = 40 m; within 50 m yes, within 30 m no; both `boundary_frac` = 1 |
| Fixture B `to_rows = 1:10`: areas 10 / 40, still 40 m apart | 10 / 40 cells, 40 m |
| Fixture C: 4 patches (2 band halves 19 + 20 cells, road 20 + 20) | yes; band halves `boundary_frac` 1, road 0 |
| Fixture D: 400 cells, width 10 px, `boundary_frac` 0 | 400 cells, perim 800, 100 m = 10.0 px; 0 |
| Width shapes 0.50 / 0.95 / 10.0 px | 0.5 / 0.952381 / 10.0 |
| Bundled 2017->2023 `changes_only`: 93 patches, 75 under 1.5 px, sliver area share < 0.25 | 93 / 75 / 0.165. Nearest patch to the 1.5 threshold is 0.058 px away. Counting exterior rings only (dropping the 2 patches with holes) also gives 75, so the pin does not depend on how `st_perimeter` treats holes |
| `patch_area_min = 5000`: one sliver, 0.75 ha, 1.44 px, `Trees -> Rangeland` | 10 survivors; only patch 6 is under 1.5 (1.4423 px, 0.75 ha); the next-thinnest is 2.1154 px |
| No pinned value sits on a threshold (`<` vs `<=`) | 0.9756 vs 1.5 / 0.9; 40 m vs 50 / 30; ratio 0.25 vs 0.5 / 0.2 |
| terra `%in%` on SpatRaster, `terra::mask(touches)`, `expect_match` on empty, `nzchar(NA)` | none used in the diff |

## Findings

- **[fragile]** `tests/testthat/helper-artifact.R:103-112` (Fixture C) and
  `test-dft_transition_artifact.R:287-306` — the "road cutting across classes is not
  boundary-hugging" fixture reaches `boundary_frac == 0` for a degenerate reason, not the
  geometric one it claims. The road goes `-> Bare`, and **Bare does not exist anywhere in the
  from epoch** (`artifact_base_from()` holds only codes 2 and 3), so the to-class mask is
  empty and `boundary_frac` is 0 regardless of where the road lies. Fixture D reaches 0 the
  same way (from epoch is all Trees). An implementation that returned 1 for every patch whose
  to-class is present in the from epoch and 0 otherwise passes A, B, C and D; the only test
  that exercises boundary *geometry* is the 2-px band (`:214-227`, the 0.5). The issue's
  acceptance criterion ("a road cutting across classes is not flagged as boundary-hugging —
  the discriminator earns its place") is therefore carried by one pinned fraction, not by the
  fixture named for it. Measured alternative that does reach the failure mode: a
  `Trees -> Rangeland` road along row 20, cols 1:20 (perpendicular to the col 20|21
  interface) gives 20 cells, 0.952 px, `boundary_frac` = **0.05** under the plan's focal
  definition — thin, same label as the artifact band, crossing rather than tracing.
  Adding that as the road case (or alongside it) makes the discriminator test geometric.
  Sibling of "A fixture that cannot reach the failure mode" in CLAUDE.md.

- **[fragile]** `test-dft_transition_artifact.R` — `flag_boundary` is only ever asserted at
  `boundary_frac` of exactly 0 (FALSE) and exactly 1 (TRUE); the design has no
  `boundary_frac` threshold parameter and the 2-px test at `d1$boundary_frac == 0.5` does not
  assert `d1$flag_boundary` either way. The bundled-tile test asserts only `0 <= frac <= 1`.
  So two implementations that disagree on every fractional patch (`>= 0.5`, `== 1`, `> 0`)
  both pass, and fractional is what real data is. Not a bug in the tests, but the contract
  does not pin the one flag whose rule is not stated in the plan — decide the threshold and
  add the `d1$flag_boundary` assertion so the suite records it.

## Notes (not findings)

- `git status` shows `test-dft_transition_artifact.R` as **`AM`**: the working tree has an
  unstaged edit (two `to <- from; to[...] <- 3L` lines split onto separate lines, lint
  style). Content-identical in effect, but the staged copy is the one that commits — see
  "A file staged and then EDITED commits the version from before the edit" in CLAUDE.md.
  Re-stage before committing or the reformat lands in a later commit. Also untracked in the
  tree: `R/dft_transition_artifact.R`, `man/dft_transition_artifact.Rd`, and an unstaged
  `NAMESPACE` export — Phase 2 has started; none of it is in this diff and none of it was
  reviewed. My probes used `load_all()` and so loaded that file, but never called it.
- Several `expect_true(all(is.na(out$col)))` assertions (stable-rows test, `dist_max = 3`
  test) would pass vacuously on a missing column (`all(is.na(NULL))` is TRUE, `any(NULL)`
  is FALSE). Column presence is pinned in the same file by the zero-row, `reciprocal = FALSE`,
  and opposite-bank tests (`expect_identical(wt$reciprocal_id, tw$patch_id)` fails on NULL),
  so the suite as a whole is not vacuous; only individual tests are.
- `expect_identical(sum(out$width_px < 1.5), 75L)` and `expect_identical(sum(out$flag_sliver), 75L)`
  are one fact twice by design (flag is defined as the metric under `width_max`); fine.
- The premise test binds a data frame to `c`. R skips non-function bindings on call lookup so
  `c(...)` still works, and no `c(` call follows the binding inside that block anyway.

## Verdict

No bugs. Two fragile-contract findings, both about what the boundary tests can and cannot
distinguish; everything pinned numerically follows from the fixtures.

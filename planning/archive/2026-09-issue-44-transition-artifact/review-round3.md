# Code-check round 3 — Phase 2b of #44 (`dft_transition_artifact()`)

Reviewed the **staged** diff (`scratchpad/diff-phase2b.patch`): `NAMESPACE`, `R/dft_transition_artifact.R`,
`man/dft_transition_artifact.Rd`, the two new tests in `tests/testthat/test-dft_transition_artifact.R`,
PWF files. Focus: the two round-2 fixes and whether the tests added for them can go red. Every claim
below was measured with `pkgload::load_all()` (sf 1.1.2, terra 1.9.34, GEOS 3.13.0); restore-the-bug
runs were done on **copies** of the package under the session scratchpad (`pkgcopy_perimeter/`,
`pkgcopy_ctid/`, `pkgcopy_noguard/`), never in the repo. Probe scripts: `r3_probe1.R`, `r3_probe1b.R`,
`r3_probe2.R`, `r3_probe3.sh`, `r3_probe4.R`.

Unstaged edits to `R/dft_transition_vectors.R`, `R/dft_transition_attribute.R`, their `.Rd`, and
`vignettes/land-cover-change.Rmd` are in the working tree but not in this diff; not reviewed here.

## Findings

- **[fragile]** `tests/testthat/test-dft_transition_artifact.R:329` — the second half of
  "levels table is read by position for the id, by name for the label" asserts
  `expect_error(dft_transition_artifact(p, r2), "transition")`, and `"transition"` also appears in
  the abort that fires when the guard is **absent**. With the
  `if (!"transition" %in% names(ct))` block deleted (copy `pkgcopy_noguard`), `ct[["transition"]]`
  is `NULL`, `match()` returns all-`NA`, and the pre-existing "not among the levels" abort fires:

  ```
  with guard:    `transition` has no transition level column.
  without guard: `patches` carries transition not among the levels of `transition`: "Trees -> Rangeland".
  ```

  Both match `"transition"`, so the test file ran **2/2 passing** on the guard-less copy — the guard
  is unpinned. Behaviour is still an error either way (hence fragile, not bug), but the guard exists
  to give a message that points at the cause, and that is exactly the property the test cannot see
  — the "assertion that matches an interpolated value" shape in `code-check.md`. Fix: match the
  claim, not the field name. `"level column"` is `TRUE` on the real tree and `FALSE` on the
  guard-less copy (measured, `r3_probe4.R`), so
  `expect_error(dft_transition_artifact(p, r2), "level column")` turns this into a real pin.

## Verified (no action)

### Fix 1 — `sf::st_length(sf::st_boundary(sf::st_geometry(patches)))` replacing `st_perimeter()`

| probe | result |
|---|---|
| lwgeom loaded? fresh session, `load_all()`, run on the river fixture and on the bundled tile (93 patches: 21 MULTIPOLYGON, 72 POLYGON, 2 with holes) | `"lwgeom" %in% loadedNamespaces()` **FALSE** at every stage; final namespace list holds sf, terra, units, s2-free — no lwgeom (`r3_probe1b.R`). Round 2's earlier probe had contaminated this measurement by calling `requireNamespace("lwgeom")` itself; re-measured clean |
| equals the perimeter? hand-built POLYGON with a hole (400 + 40), MULTIPOLYGON with a hole in one part (40 + 120 + 20), plain square (40) | `440 180 40`, identical to expected; also identical to a perimeter summed from `st_coordinates()` ring by ring |
| bundled 93 patches vs coordinate-derived perimeter (independent of both sf paths) | max abs diff **0**; `width_m` vs `2A/P` computed by hand: max abs diff 0 |
| vs `st_perimeter()` itself (run last, since it loads lwgeom) | max abs diff 0 |
| zero rows | `st_length(st_boundary(gp[0]))` → `units` of length 0 → `as.numeric()` gives `numeric(0)`; the existing zero-row schema test passes |
| empty geometry (`st_polygon()`) | boundary length `0`, so `width_m` → `NA_real_` via the `!(perim_m > 0)` guard; no error |
| GEOMETRYCOLLECTION | `st_boundary()` errors: `IllegalArgumentException: Operation not supported by GeometryCollection` (GEOS), even for a collection of polygons only. **Out of contract**: `dft_transition_vectors()` goes through `terra::as.polygons()` and can only yield POLYGON/MULTIPOLYGON (the bundled `sfc_GEOMETRY` is those two types mixed, and works). Loud, not silent |
| **restore the bug**: `perim_m <- as.numeric(sf::st_perimeter(patches))` on a copy | "does not pull in lwgeom" test goes **red** — `Failure at :312: Expected "lwgeom" %in% loadedNamespaces() to be FALSE; actual TRUE`. All 19 other tests still pass (lwgeom is installed here), so this test is the only thing in the suite that sees the defect on this machine |
| can the test's skip branch fire silently in CI? | `unloadNamespace("lwgeom")` succeeds after `st_perimeter()` loaded it. Only **tmaptools** (via tmap) imports lwgeom on this machine; neither is in `Imports`/`Suggests`, no `R/` file references tmap, and no test loads it — so the unload cannot be blocked by a dependent namespace in a drift test session. If lwgeom is not installed at all, the bug variant errors and the test is red anyway |

### Fix 2 — `ct[[1]]` for the id, `"transition"` by name

| probe | result |
|---|---|
| is `ct[[1]]` always the id? | terra enforces it: `set.cats()` with a non-numeric first column aborts `[set.cats] the first column of 'value' must be numeric`. `levels<-` names it `value`; a three-column table with `active = 2` still has the id first in `cats()`; a factor raster written to GeoTIFF and read back keeps `id transition` with the id first; a `double` id column divides with `%/% 1000L` correctly |
| **restore the bug**: `ids <- ct$id[lab_idx]` on a copy | "levels table is read by position" **errors** at `:323`: `replacement has 0 rows, data has 1` — the exact round-2 symptom. Red, as it should be. (n = 1 patch, so the silent zero-row path noted in round 2 is not what the fixture exercises) |
| `set.cats()` reference semantics in the new test | `r2 <- res$raster; set.cats(r2, ...)` mutates `res$raster` too (measured TRUE). Harmless here: `res` is local to the test and `p` was vectorized before the rename |

### Restore-the-bug summary

| variant (copy) | mutation asserted took | test file result |
|---|---|---|
| `pkgcopy_perimeter` | `perim_m <- as.numeric(sf::st_perimeter(patches))` present | 1 failure, lwgeom test |
| `pkgcopy_ctid` | `ids <- ct$id[lab_idx]` present | 1 error, levels test |
| `pkgcopy_noguard` | guard block absent, `ct[[1]]` still present | **0 failures** — finding above |

## Notes (not findings)

- The `"transition"` regex in the pre-existing "errors on bad inputs" test (`p_missing$transition <- NULL`)
  has the same interpolated-name shape, but that guard was reviewed in round 1 and is not in this diff.
- `sf::st_length()` on projected data goes through GEOS (`CPL_length`), `st_area()`, `st_distance()`
  and `st_is_within_distance()` likewise; `dft_check_crs()` rejects lon/lat with `is.lonlat(perhaps = TRUE)`,
  so no path in the function can reach sf's lon/lat branches that consult `sf_use_s2()` or lwgeom.
- The roxygen comment on line 230-232 ("Measured identical on the bundled patches (multipolygons
  and holes included)") is accurate.

## Verdict

Both round-2 fixes are correct and each is pinned by a test that goes red when its bug is restored.
One fragile finding: the new guard on the `transition` level column is **not** pinned — its test
passes with the guard deleted because the fallthrough error also contains the word `transition`;
one regex change (`"level column"`) closes it. No bugs.

# Review round 4 — Phase 3 (documentation) of #44

Scope: staged diff `diff-phase3.patch` — new `## Geometric Artifacts` section in
`vignettes/land-cover-change.Rmd`, `@seealso` edits in `R/dft_transition_vectors.R`
and `R/dft_transition_attribute.R`, regenerated `man/*.Rd`.

## Verdict: Clean

No bugs, security issues, or false claims found.

## What was checked, and how

All numbers below were re-derived by running the new chunk code against the
source tree (`pkgload::load_all()`), not read from the issue or prior rounds.

| claim in prose | how verified | result |
|---|---|---|
| `r sum(tagged$flag_sliver)` of `r nrow(tagged)` slivers | computed | 75 of 93 |
| slivers hold `r round(...)`% of change area | computed | 16% (5.61 / 34.03 ha) |
| `r sum(flag_sliver & flag_boundary)` / `r sum(flag_sliver & !flag_boundary)` | computed | 48 / 27 |
| `r sum(tagged$flag_reciprocal)` patches have a partner | computed | 5 |
| single pixel 0.5 px, one-pixel band just under 1 px, 20x20 block 10 px | `2ab/(2(a+b))` | 0.5, 0.95 (1x20), 10 |
| 1-px band along 5 km at 30 m is 15 ha | 30 x 5000 / 1e4 | 15 ha |
| surviving sliver: `Trees -> Rangeland`, 0.75 ha, under 1.5 px | survivors table | patch 6: 0.75 ha, 1.44 px, `flag_sliver` TRUE — the only sliver among 10 survivors |
| "traces the 2017 forest edge" | `boundary_frac` = share of cells adjacent to from-epoch cells of the *to* class (Rangeland); patch is 2017 Trees, so the interface is the 2017 Trees/Rangeland edge | 0.71, `flag_boundary` TRUE |
| trajectory vignette reads an outline with no red as a label change | `vignettes/trajectory-break-detection.Rmd` l.82-84: "An outline with no red is a mapped transition not backed by a spectral drop — likely a borderline pixel changing label rather than trees coming off" | matches |
| "cannot separate riparian deciduous trees from grass in peak summer" | same vignette l.172-175 | matches |
| vignette title quoted in italics | `title:` in trajectory Rmd | "Trajectories as a Check on Land-Cover Change" — exact |

Structural checks:

- **Variable definition order.** `result` (l.127), `changed` (l.134), `patch_min`
  (l.225), `aoi_proj` (l.273) are all defined before the new section (starts l.319).
  `changes`, `tagged`, `large`, `by_sliver`, `pal` introduced by the new chunks are
  not reused by the only later section (Interactive Map, l.433+), so no shadowing.
- **`case_when` NA handling.** `changes` is built with `changes_only = TRUE`; measured
  0 stable rows and 0 `NA` in `flag_sliver`, `flag_boundary`, `flag_reciprocal`.
  Every row lands in one of the four `pal` names (18 / 43 / 27 / 5), so
  `pal[tagged$evidence]` has no `NA` colours.
- **kable `col.names`.** `by_sliver` has 5 columns / 5 names; survivors selection has
  7 columns / 7 names.
- **Rd validity.** `tools::checkRd()` on both files returns only `(-1)` non-ASCII
  notes; every flagged line is an em dash, and the same notes fire on lines the diff
  did not touch (e.g. vectors.Rd l.25, l.49; attribute.Rd l.37, l.65). `DESCRIPTION`
  declares `Encoding: UTF-8`, so `R CMD check` accepts them. Not new.
- **`m²` escape.** Prose uses literal `m²` (l.222, l.252 existing; l.400 new); R
  strings use `"²"` (l.264, l.272, l.282 existing; l.419 new). Consistent.
- **pkgdown.** `pkgdown::check_pkgdown()`: no problems. `dft_transition_artifact` is
  exported (NAMESPACE l.20).

## Checked, not flagged

Two prose points that are true for the bundled data but worth knowing about;
neither is a defect and neither is being asked for.

- l.327 "through every threshold in the comparison table above" — that table carries
  one threshold (5,000 m²). True, vacuously.
- `plot-artifact` fig.cap says "patches with a reciprocal partner (purple)", while the
  `case_when` colours only *slivers* with a partner purple; a wide patch with a
  partner would render grey. On this data all 5 reciprocal patches are slivers, so
  the rendered figure matches its caption.

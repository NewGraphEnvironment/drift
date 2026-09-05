# Code-check round 2 — Phase 2 of #44 (`dft_transition_artifact()`)

Reviewed the **staged** diff: `NAMESPACE` export, `R/dft_transition_artifact.R`,
`man/dft_transition_artifact.Rd`, PWF checkbox flips. Every claim below was measured with
`pkgload::load_all()` against the source tree (sf 1.1.2, terra 1.9.34, cli 3.6.6), not read
off the code. Probe scripts are in the session scratchpad (`probe1.R` .. `probe4.R`).

## Findings

- **[bug]** `R/dft_transition_artifact.R:222` — `sf::st_perimeter()` on a projected CRS
  delegates to **lwgeom** (`if (!requireNamespace("lwgeom")) stop("package lwgeom required, please
  install it first"); lwgeom::st_perimeter_lwgeom(x)` — sf 1.1.2 source, projected branch).
  lwgeom is in neither `Imports` nor `Suggests` of `DESCRIPTION`, and is not a transitive
  hard dependency of any Import (measured: `tools::package_dependencies()` recursive over
  Depends/Imports/LinkingTo of all ten Imports → `lwgeom` absent; sf's own hard deps are
  `classInt DBI graphics grDevices grid methods s2 stats tools units utils`). Since
  `dft_check_crs()` rejects lon/lat, **every** accepted input takes the lwgeom branch, so on
  any install without lwgeom the exported function errors on its first line of real work.
  Confirmed by mocking `requireNamespace("lwgeom")` to `FALSE`: the function fails with
  `package lwgeom required, please install it first`. The suite is green here only because
  lwgeom happens to be installed on this machine — "a fixture that cannot reach the failure
  mode", supplied by the environment. Consequences: the pkgdown workflow (`setup-r-dependencies`
  with `needs: website`, i.e. Imports + Suggests + Config/Needs/website) runs `@examples`
  and will fail on `dft_transition_artifact(patches, result$raster)`; the Phase 3 vignette will
  fail the same way; users installing from GitHub hit it immediately.

  **Remedy, measured:** `sf::st_length(sf::st_boundary(sf::st_geometry(patches)))` (or
  `sf::st_length(sf::st_cast(g, "MULTILINESTRING"))`) reproduces `st_perimeter()` with
  **max abs diff 0** across all 93 bundled change patches, including the 21 MULTIPOLYGONs and
  the 2 patches with holes (patch 16 = 360 m both ways), and returns `numeric(0)` on the
  zero-row path. Neither needs lwgeom. Do **not** substitute bare `sf::st_length()` on the
  polygons — on sf 1.1.2 that returns `0` for every polygon (the old NEWS-1135 behaviour is
  gone). The alternative — adding lwgeom to `Imports` — works but drags a compiled
  system-library dependency into the install for one line.

- **[fragile]** `R/dft_transition_artifact.R:203-216` — the from/to codes are read as
  `ct$id` by **name**, while terra's contract is that the *first* column of the cats table is
  the ID column, whatever it is called (`levels<-`/`set.cats()` on a user raster commonly yield
  `value` or `ID`). The roxygen says the function "works on any factor transition raster".
  With a cats table named `value`/`transition`: `ct$id` is `NULL`, `ids` is `NULL`,
  `from_code`/`to_code`/`is_change` are length 0, and the failure surfaces three sections
  later as `replacement has 0 rows, data has 2` from `out$flag_reciprocal <- logical(0)` — a
  message pointing nowhere near the cause. On a zero-row `patches` the same input returns
  silently. Not reachable from `dft_rast_transition()$raster` (always `id`/`transition`), so
  low severity; `ct[[1]]` for the ID column, or a named-column assertion with its own message,
  closes it. (`ct$transition` failing the same way is already caught by the "not among the
  levels" abort, so only the ID column is exposed.)

## Verified (no action)

| probe | result |
|---|---|
| `terra::rasterize(vect(patches), field = "patch_id")` round-trip on the bundled tile | 93/93 patches present, per-patch cell count `==` `area / cell_area` exactly, incl. 21 MULTIPOLYGON and 2 holed patches; total 3403/3403. Default is cell-centre (`touches = FALSE`), which is the inverse of `as.polygons()`, so no double-assignment where patches share edges |
| `zonal()` zone typing | zone raster is `INT`; `z[[1]]` comes back `num`; `match()` on integer `patch_id` works. Double `patch_id` → `reciprocal_id` typed double, correct values; non-contiguous ids (`1000L, 7L`) → correct partners and fractions |
| NA leakage into `boundary_frac` | Band whose to-class side is entirely NA → `0`, not NA. Band whose only interface column is NA → `0` at d=1, `1` at d=2 (k found further out). `focal(fun="max", na.rm=TRUE)` on an all-NA window → NA, never `-Inf`, and never reached at a patch cell (centre is 0/1). Band on raster column 1 → `1` (edge padding ignored) |
| `patches` with renamed geometry column (`geom`) | all eight columns appended, `sf_column` preserved and last, values unchanged |
| CRS check WKT vs EPSG | `st_crs(32609) == st_crs(terra::crs(<GeoTIFF>))` TRUE; patches `st_crs<- 32609` vs fixture raster TRUE; raster carrying GeoTIFF WKT vs EPSG sfc TRUE (`Ops.crs` uses GDAL IsSame) |
| `terra::vect()` on carried-over column types | Date, POSIXct, list, factor, units, all-NA logical columns on `patches` → runs, fractions unchanged |
| `st_is_within_distance` inclusivity | `<=`: gap 40 m matches at `dist = 40`, not at `39.999`; `reciprocal_dist_max = 4` on the 40 m river fixture flags both |
| reciprocal loop | `rkey[fwd[1]]` is the reverse key of the group (all `fwd` share one key); `rev` restricted to `is_change`; self-match impossible (`key != rkey` for change rows); sparse index `hits[[a]]` indexes `rev`; tie → larger via `order(d, -area)`; `id` typed from `patch_id` |
| cli pluralisation | all three messages render correctly at n = 1 and n = 2 (`column{?s} {.val {x}}` takes the quantity from the *following* substitution; `{cli::qty(length(bad))}transition{?s}` sits immediately before its marker; `[{lower}, {upper}]` renders `[0, Inf]`) |
| `ifelse` on length 0 | `width_m[!(perim_m > 0)] <- NA` avoids it; both `flag_*` `ifelse()`s return `logical(0)` on zero rows and `logical` otherwise (test pins the types) |
| `$` partial matching | every `$` key is either guarded by `cols_req` or exists exactly (`rec$id`, `rec$dist`); the one unguarded name is `ct$id` — finding 2 |
| terra `%in%` / `mask(touches)` | neither used |
| holes and width | `st_perimeter` includes hole rings, consistent with the documented `2A/P`. Bundled holed patches: 16 → 1.111 px (1.250 exterior-only), 82 → 4.872 (4.932); neither crosses 1.5, matching round 1 |
| memory contract | no `values()`/full-grid vectors; `ifel`, `focal`, `rasterize`, `zonal` streamed; one focal per distinct to-class; the only in-memory object is `vect(patches_chg)` |

## Notes (not findings)

- Non-grid-aligned `patches` (not from `dft_transition_vectors()`): a sub-cell polygon that
  rasterizes to no cell gets `boundary_frac = NA` (documented as meaning "stable"); polygons
  offset by half a cell get `0`. Outside the documented input contract; the round-trip above
  shows the contract's inputs are exact.
- `boundary_dist_max = Inf` passes `check_num1()` (`upper = Inf`) and `Inf == round(Inf)`,
  then `as.integer(Inf)` warns and `focal` fails. Loud, not silent.
- A multi-layer `transition` fails at `if (!terra::is.factor(transition))` with
  `the condition has length > 1`. Loud, unhelpful.
- Local `rev` shadows `base::rev()`; no `rev()` call in scope, so harmless (R skips
  non-function bindings on call lookup).
- Probe hygiene worth recording: `r2 <- r; terra::set.cats(r2, ...)` mutates `r` — a
  SpatRaster is a reference. My first pass at the cats probe corrupted the fixture and two
  later probes ran on it; `terra::deepcopy()` fixed it. Nothing in the diff does this.

## Verdict

One real bug: the new export depends on **lwgeom** through `sf::st_perimeter()` on every
accepted input, and the package does not declare it — will break pkgdown/examples in CI and
any install without lwgeom. A one-line, measured-equivalent replacement exists. One low
fragile finding on cats-column naming.

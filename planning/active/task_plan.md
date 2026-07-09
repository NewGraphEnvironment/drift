# Task: LULC transition/classify OOMs on large-floodplain AOIs (#34, closes #28)

`dft_rast_transition()` → `dft_transition_vectors()` OOM on large-floodplain AOIs
(NECR, 551 km²) even solo with ~30 GB free. Two independent memory drivers:
(1) the **producer** builds 6+ full-grid R vectors incl. two full-grid character
vectors (ncell-driven ~13 GB floor — this is #28); (2) the **vectorizer**
polygonizes the whole floodplain's *stable* mosaic before the caller discards it
(floodplain-area-driven — the field OOM that kills NECR). Fix both on one branch,
close #34 + #28, single 0.4.0 release. drift-only; `floodplains` caller wiring is a
documented follow-up.

Full design + verified terra semantics in `findings.md`.

## Phase 1: Empirical gate + profiling harness (data-raw/, zero DESCRIPTION footprint)
- [x] `data-raw/benchmark_transition_oom.R`: (a) semantics smoke — assert `*1L`
  factor-strip/NA/no-mutation, NA propagation through `*/+/!=/&/ifel/%in%`,
  `freq(integer)` value==code + NA-excluded + `sum(count)==n_nonNA`, empty-RHS
  `%in%`/`classify`/`subst` guarded, `p %in% small_ids` FALSE at `p==NA`, `set.cats`
  on double-arith raster → factor (run on installed terra; bump floor if 1.8-10
  differs). (b) profiling — synthetic classified pair with independently-tunable
  ncell and transition-density; profile `classify → transition(±patch_area_min) →
  vectors(±changes_only)` peak RSS via `/usr/bin/time -l`; before/after table
  attributing the two drivers. Proceed only if semantics gates pass.

## Phase 2: Golden-output correctness harness (capture current behavior first)
- [x] Extend `tests/testthat/test-dft_rast_transition.R` with a byte-identical golden
  capture on the packaged fixture across: default; `from_class="Trees"`; both filters;
  `patch_area_min ∈ {NULL,0,500,1000,1e9}`; impossible-filter. Snapshot `summary`,
  `raster` cats + `freq(value,count)`, `removed` cats. This is the rewrite's contract.

## Phase 3: Producer terra-native rewrite (#28)
- [x] Rewrite `R/dft_rast_transition.R`: `code_from/code_to <- r_from/r_to * 1L`;
  `r_trans <- code_from*1000L + code_to`; `apply_codeset()` `@noRd` for from/to filters
  (empty-set guard); streamed `patch_area_min` via `ifel`/`patches`/`subst`/`ifel`
  (empty-id guard); freq-derived codes + `total_valid`; removed raster via `ifel` +
  freq cats; preserve empty-return `removed=NULL`. No `terra::values()`, no `rep(NA,ncell)`.
  (subst, not `%in%`: SpatRaster `%in%` isn't dispatched when terra is imported.)
- [x] Green: full `test-dft_rast_transition.R` + Phase-2 golden byte-identical; full
  suite 303 pass / 4 skip; lint clean; `/code-check` round 1 Clean (old-vs-new
  byte-identical across 14 cases incl. ESA 3-digit codes). Producer-only peak RSS at
  16M cells: 2.66 GB (old) → 1.63 GB (new).

## Phase 4: Vectorizer working-set cap (#34 core)
- [ ] `R/dft_transition_vectors.R`: add `changes_only = FALSE` (raster-level stable
  drop before `as.polygons`); add small-patch raster pre-filter (keep trailing
  `st_area` filter). Roxygen: document `changes_only`; note `patch_id` densening
  under filtering.
- [ ] New tests: `changes_only=TRUE` drops stable / keeps changes / survivor `area_ha`
  unchanged; existing 185/123.11/57 stay green on the default path; `as.polygons`
  peak drops on the Phase-1 synthetic high-patch grid.

## Phase 5: Docs, NEWS, release, close #34 + #28
- [ ] `devtools::document()`; `lintr::lint_package()` clean; full `devtools::test()`.
- [ ] `NEWS.md` 0.4.0: producer terra-native rewrite (no full-grid R vectors, OOM);
  vectorizer `changes_only` + small-patch pre-filter; behavior-preserving defaults;
  `patch_id` densening note.
- [ ] Document `floodplains` follow-up (caller passes `changes_only=TRUE`, drops the
  `:115` `from!=to` post-filter) in progress.md / a floodplains issue.
- [ ] Bump `DESCRIPTION` 0.3.0 → 0.4.0 as the **final** commit; terra floor bump only
  if Phase 1 required it.

## Validation
- [ ] Tests pass (`devtools::test()`); network/bfast tests skip cleanly
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

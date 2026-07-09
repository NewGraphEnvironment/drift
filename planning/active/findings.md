# Findings — LULC transition/classify OOMs on large-floodplain AOIs (#34, closes #28)

## Issue context (#34)

The land-cover step (`dft_rast_classify` → `dft_rast_transition` →
`dft_transition_vectors`) OOMs on a large-floodplain AOI even solo with ~30 GB free.
#27 fixed the per-class loop in the vectorizer, but the pass still materializes
full-grid rasters into R vectors and builds one polygon per transition patch.

Decisive field clue: **UFRA has a *larger* bounding box (1.8×0.8°, 102.6M-cell grid)
than NECR (1.4×0.6°) but a *smaller* floodplain (188 vs 551 km²), and UFRA completes
while NECR is SIGKILLed.** So the field driver is floodplain-area / transition-patch
count, not raster grid extent. (UFRA peaked ~13 GB at 188 km²; NECR at 3× the
floodplain exceeds ~30 GB.) #28 is the precise producer diagnosis; #34 is the field
report — same OOM class, resolved together here.

## Two independent memory drivers (exploration 2026-07-09)

Resolves the apparent contradiction (NECR OOMs on a *smaller* grid than UFRA):

1. **Producer, ncell-driven (~13 GB floor at 102.6M cells) = #28.**
   `R/dft_rast_transition.R:89–109` builds 6 persistent full-grid R vectors —
   `v_from`, `v_to` (double), **`name_from`, `name_to` (CHARACTER, ~800 MB each)**,
   `trans_code` (double), `keep` (logical) — plus transient `as.character()` spikes.
   The two character vectors are consumed ONLY by the optional `from_class`/`to_class`
   filters, so they are **pure waste when both are NULL (the default)**. The
   `patch_area_min` path adds `rep(NA_integer_, ncell)` (`:122`, `:191`) + full-grid
   `terra::values()` reads (`:131`) + a full-grid `terra::patches()` (`:125`). Scales
   with grid cells → matches UFRA's ~13 GB. Present every call, survivable at 30 GB.

2. **Vectorizer, floodplain-area-driven = the field OOM that kills NECR.**
   The producer's transition raster is **non-NA over the *entire* floodplain** — it
   encodes stable `from==to` transitions too (never filtered; the `keep` mask only
   filters by from/to-class and NA, `:102–109`). The field caller
   `floodplains/scripts/floodplain_lcc/03_lulc_classify.R:107` calls
   `dft_transition_vectors(trans_all$raster, zones=…)` **with no `patch_area_min`**, so
   `terra::as.polygons()` polygonizes the whole floodplain's stable mosaic, then the
   caller discards stable patches (`from_class != to_class`, `:115`) *after* paying the
   cost. `as.polygons` scales with patch/vertex count = floodplain area → NECR (551 km²,
   3× UFRA) blows past 30 GB.

**`dft_rast_classify` and `dft_rast_summarize` are already terra-native** (no
`terra::values()`; `terra::unique`/`classify`/`freq` only). #34's claim that classify
participates in the OOM is **not founded** at the R level.

## Current producer structure (R/dft_rast_transition.R, v0.3.0)

- Signature: `dft_rast_transition(x, from, to, class_table=NULL, source="io-lulc",
  from_class=NULL, to_class=NULL, unit="ha", patch_area_min=NULL)`.
- Encoding: `trans_code = from_code * 1000L + to_code`.
- Returns `list(raster, summary, removed)`; summary cols `from_class, to_class,
  n_cells, area, pct`; raster factor levels `"from -> to"`; `removed` is NULL unless
  `patch_area_min` filtered.
- Summary already uses `terra::freq(r_trans)` (native); only full-grid R op there is
  `total_valid <- sum(!is.na(trans_code))` (`:171`) + `valid` (`:140`).

## Vectorizer (R/dft_transition_vectors.R, post-#27)

- Signature: `dft_transition_vectors(x, zones=NULL, zone_col=NULL, patch_area_min=NULL)`.
- Single pass `terra::patches(x, directions=8, values=TRUE)` → `as.polygons` → sparse
  pid→label via `terra::cells()`/`terra::extract()`; filters `patch_area_min` by
  `st_area` AFTER polygonizing.
- Returns sf: `patch_id` (scan-order), `transition`, `area_ha` (+ zone col). Does NOT
  filter stable transitions — caller does.

## Terra semantics — empirically verified (Plan agent, terra 1.9.11 in-memory)

Load-bearing facts the rewrite rests on:
- `r_from * 1L` **strips the factor** → new non-factor raster of raw codes, NA
  preserved, and **does not mutate `r_from`** (stays factor) — critical: inputs are
  references into the caller's list; no `deepcopy` needed.
- NA propagates through `* / + / != / & / ifel / %in%`.
- `code_r %in% c(...)` returns a boolean raster, **FALSE (not NA) at NA cells** →
  reproduces base-R `name %in% sel` NA behavior exactly.
- `terra::freq(integer_raster)`: `value == code`, NA excluded, `sum(count) ==
  global(!is.na)` → both `unique_codes` and `total_valid` come free from one `freq`.
- `set.cats()` on a double-valued arithmetic raster (ids like 2005) → `is.factor==TRUE`.
- **terra SpatRaster `%in%` ERRORS on an empty RHS** (`[%in%] no matches supplied`),
  unlike base R → every `p %in% ids` / `code %in% keep` needs a `length()>0` guard or
  all-NA shortcut.

**Gate before trusting:** re-verify facts 1–5 at the DESCRIPTION floor **terra 1.8-10**
(bump floor if any differ). Verified on installed 1.9.11 only.

## Correctness contract (existing tests the rewrite must keep green)

- `test-dft_rast_transition.R`: return shape `c("raster","summary","removed")`; summary
  cols; `pct` sums 100 (±0.1; ±0.5 with `patch_area_min`); sorted by `n_cells` desc;
  labels contain `" -> "`; ha = 100×km2; `patch_area_min` NULL≡0≡default; raster non-NA
  count == `sum(summary$n_cells)`; validation errors "non-negative"; `$removed`
  conservation law `n_kept + n_removed == n_changed_unfiltered`.
- `test-dft_transition_vectors.R`: **pinned regression 185 patches / 123.11 ha / 57 at
  `patch_area_min=1000`**; `sum(area_ha)==sum(summary$area)`; every `transition` in
  `cats(raster)`; `patch_id` unique; all-NA → empty sf.
- Fixtures: no precomputed goldens; tests re-read `inst/extdata/example_2017|2020|2023.tif`
  (326×314, EPSG:32609, raw io-lulc codes) and re-run classify/transition inline. Reusable
  synthetic builder `transition_test_rast(m)` at `test-dft_transition_vectors.R:113`.

## Vectorizer mitigation design (Plan agent)

- **`changes_only`** (NECR-saving lever): stable ids are `id %/% 1000L == id %% 1000L`;
  NA-mask at raster level (`classify`/`subst` on `x*1L`) before `patches`/`as.polygons`.
  Opt-in default FALSE → pinned 185/123.11/57 untouched.
- **Small-patch raster pre-filter**: `classify` small pids→NA before `as.polygons`, KEEP
  the trailing `st_area` filter. The raster pre-filter's `count*cell_area < min` drops
  are a **strict subset** of the `st_area` `< min` drops → output provably byte-identical
  (57 preserved). `patch_id` densens under filtering (not test-pinned; NEWS note).

## Cross-repo follow-up (drift-only decision)

After the drift 0.4.0 release, wire the field caller:
`floodplains/scripts/floodplain_lcc/03_lulc_classify.R` → pass `changes_only = TRUE` to
`dft_transition_vectors()` (`:107`) and drop the post-hoc `from_class != to_class`
filter (`:115`). Only then does NECR complete end-to-end. Separate floodplains PR/issue.

## Git base note

Branch `34-lulc-transition-classify-ooms-on-large-f` is off `origin/main` (6ba10bb), NOT
local main — local main carries an unpushed memory-audit doc commit (`a5ef052`,
CLAUDE.md + inst/notes/) kept out of this PR's diff. User pushes `a5ef052` to main
separately.

# Issue #34 (closes #28) — LULC transition/classify OOMs on large-floodplain AOIs

## Outcome

Fixed the remaining OOM class in the categorical pipeline (#27 fixed the vectorizer's
per-class loop; this fixed the two drivers left). Exploration found **two independent
memory drivers**, resolving the issue's apparent contradiction (NECR OOMs on a *smaller*
grid than UFRA, which completes): (1) the **producer** `dft_rast_transition()` built 6+
full-grid R vectors incl. two full-grid *character* vectors — ncell-driven, this was #28;
(2) the **vectorizer** polygonized the whole floodplain's *stable* (`from==to`) mosaic
before the caller discarded it — floodplain-area-driven, the field OOM that kills NECR.

**Fixes, both behavior-preserving:**
- `dft_rast_transition()` rewritten to stream through terra (`* 1L` factor-strip →
  `code_from*1000L+code_to` arithmetic → `subst` code-set filters → `patches`/`freq`/`ifel`
  for `patch_area_min`). Zero full-grid R vectors; peak memory is O(#codes + #patches).
  Byte-identical to the old version (golden snapshot across 8 param combos, plus an
  independent old-vs-new comparison across 14 cases incl. ESA WorldCover 3-digit codes).
  Producer-only peak at 16M cells: 2.66 GB → 1.63 GB.
- `dft_transition_vectors()` gained opt-in `changes_only` (drop stable patches at the
  raster level before `as.polygons`) + a small-patch raster pre-filter (keeps the trailing
  `st_area` filter → byte-identical). NA-ing stable cells can't merge/split a change patch,
  so `changes_only=TRUE` == default filtered to non-stable rows (proven by test). On a
  fragmented NECR-like synthetic (9M cells, 415k patches, as.polygons-dominated): default
  3.83 GB → changes_only 1.71 GB (55% peak cut).

Released as **v0.4.0**. Full suite 314 pass / 4 skip; `R CMD check` 0/0/0; lint clean.

**Key learnings (durable):**
- SpatRaster `%in%` is NOT dispatched when terra is *imported* (package context) — only
  when *attached* (`library(terra)`); use `terra::subst()` for code-set masks.
- `terra::freq()` **errors** on an all-NA raster (does not return 0 rows) → guard with
  `tryCatch`.
- The changes_only memory win only appears when `as.polygons` is the peak driver —
  fragmented/braided floodplain geometry (NECR), not blocky synthetics.
- `/code-check` round 1 caught a pre-existing empty-return schema gap (zone column dropped)
  that `changes_only` amplifies in the per-sub-basin field loop; fixed.

**Follow-up (drift-only decision, NOT done here):** the `floodplains` caller must opt in
for NECR to complete end-to-end — pass `changes_only = TRUE` in
`scripts/floodplain_lcc/03_lulc_classify.R:107` and drop the `from!=to` post-filter at
`:115`. Left to the user (separate floodplains PR).

Closed by: PR for branch `34-lulc-transition-classify-ooms-on-large-f` (commits
845ff11..8d804f4), release v0.4.0.

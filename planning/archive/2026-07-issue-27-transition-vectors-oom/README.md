# Issue #27 — dft_transition_vectors OOMs on large-extent rasters

## Outcome

Fixed the OOM by replacing the per-class/per-patch loop in `dft_transition_vectors()` with a
single `terra::patches(x, directions = 8, values = TRUE)` pass (8-connected components of
same-valued cells) plus a sparse pid→label map via `terra::cells()`/`terra::extract()`. The old
code scaled as ncell × n_patches — the sleeper was the per-patch remap allocating two full-grid
logicals per patch — extrapolating to ~18+ GB on the 102.6M-cell UFRA floodplain. Approach chosen
by empirical benchmark during planning: single-pass was behavior-identical (pinned by a
regression test captured from the old implementation: 185 patches / 123.11 ha / 57 at
`patch_area_min = 1000`) and 55× faster (1.9 s vs 122 s at 24M cells); the issue's tiling and
sparse-window options were behavior-changing or degenerate on mainstem-shaped data, and
polygonize+explode was disqualified (GDAL is 4-connected). Key learnings: terra ≥ 1.8-10 is a
correctness floor (`values = TRUE` edge-wraparound bug); `patch_id` ordering became scan-order
(docs only promised "connected component ID"); the producer `dft_rast_transition()` has the same
disease (6+ full-grid vectors incl. two character) — filed as #28 rather than scope-creeping.
Released as v0.2.4.

Closed by: commits 157c66c / baa45c3 / 69f2578, PR pending (branch
`27-dft-transition-vectors-ooms-on-large-ext`)

# Plan review — #115 (Plan agent, spawned 2026-11-13T16:12:37Z, read at b78dd2a)

Findings as returned; dispositions in task_plan.md "Review fold-in".

- **B1 Blocker** — MODIS asset names start with a digit; gdalcubes lower-cases the apply_pixel expression and tinyexpr reads a leading digit as a number, so `250m_16_days_red_reflectance` is `250` then an unknown name: "Invalid expression(s)" after the full query. Hits dft_index_expr, the composite's reflectance exprs, and the exported dft_index_expr(). Fix: rename non-identifier bands to role names (gdalcubes::rename_bands) in one helper; mask band untouched; check the count path. Offline fixture test. (Reproduced live before the review arrived: `Cannot parse expression for kndvi ... error at token 39`.)
- **G1 Gap** — composite needs missing(res) too. (Already in e120390.)
- **G2 Gap** — composite default bands include green, which MODIS lacks; document. aggregation = "count" on MODIS counts clear 16-day composites, not days; document.
- **G3 Gap** — kndvi in [0,1) and an EVI range cannot fail; an all-band -1000 fill gives ndvi/evi exactly 0. Assert composite reflectance in [0,1]; better, an offline fixture with -1000 and 255/3 pixels.
- **G4 Gap** — gdalcubes source: reflectance NoData taken from GDAL (stac nodata ""), -1000 -> NaN; mask band read with empty nodata list so raw 255 reaches value_mask and values = 255 masks it.
- **G5 Gap** — docs still describing S2 as the only cube source / assuming eo:cloud_cover: dft_stac_cube.R header and stac_cube_items doc, drift-package.R, dft_stac_composite.R header, dft_index_expr.R roles list (no blue), trajectory-break-detection vignette, floodplain-change-dating article :336.
- **G6 Gap** — with months = NULL, window-only items whose midpoint lies outside [t0, t1] pass the item gate and gdalcubes skips them; all skipped gives a misleading drift_empty_cube. Drop them in stac_cube_items (window-only items only).
- **O1 Ordering** — resolve res before tile_size_check. (Done in e120390.)
- **O2 Ordering** — B1 and its offline test before Phase 4.
- **A1** — S2 keys byte-identical: confirmed.
- **A2** — no caller refused; accept explicit NULL on any source and say so in the refusal.
- **A3** — midpoint agrees with gdalcubes' dt truncation and both filters; test under an off-UTC timezone.
- **A4** — 250 is nominal; MOD13Q1 grid is 231.656 m. Reword or use it.
- **A5** — month_times() labels layers monthly whatever dt; MODIS invites P16D. Pre-existing.
- **A6** — check the collection's real end vs the fixed 2025-12-31.
- **S1** — dft_stac_fetch refuses cube sources generically; no test enumerates sources; `evi` name and substitution safe.
- **AC1/AC2** — acceptance items for B1, the fill fixture, composite defaults; live test asserts reflectance in [0,1].

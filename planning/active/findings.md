# Findings — Trajectory vignette redo (#30, continued)

**Continues** `planning/archive/2026-07-issue-30-index-trajectory/findings.md` — read that for the
full empirical journey. Condensed carry-forward below, then this cycle's findings.

## Journey so far (carried from the archived #30 cycle)

- **`gdalcubes::filter_geom()` segfaults / all-NA cube** (0.7.3) → cube spans the AOI bbox; clip the
  reduced raster with `terra::mask()`. (drift#32)
- **`reduce_time` R-callback runs in spawned workers** where closures fail → moot after the terra pivot.
- **gdalcubes can't read a terra-written NetCDF** → `dft_stac_cube()` returns a terra SpatRaster stack;
  `dft_rast_break()` reduces it via forked `parallel::mclapply` (fast: 102k px ~8 s).
- **Sentinel-2 +1000 DN offset flips at 2022-01-25** (baseline 04.00). A uniform offset makes a false
  whole-AOI break at 2022 (kNDVI `tanh` hides it; 99% of pixels "broke" at 2022.42). Fixed by a
  **baseline-conditional item split** (`offset_boundary`/`offset_before`), coalesced with `terra::cover`.
  Validated: per-year kNDVI aligns across 2022; breaks fell to 25% of pixels.
- **Growing-season focus** (`months = 6:9` + snow mask + `order` knob) sharpens signal and cuts data ~3×.
- Shipped v0.3.0, `R CMD check` 0/0/0, PR #33 open. Follow-ups #31 (label breaks), #32 (AOI-polygon clip).

## Why the redo (review of the shipped vignette)

- The 2018–2023 / monitor-from-2022 example is dominated by a **region-wide 2023 kNDVI decline**
  (~96% of breaks negative, most dated 2023.4–2023.7; per-year mean 2022≈0.53 → 2023≈0.43). Most
  plausibly a **2023 dry/wildfire-smoke year** — smoke depresses kNDVI and is NOT an SCL class, so it
  leaks through the cloud mask. This swamps localized change.
- The reach is **mostly rangeland with a riparian tree corridor** (from the LULC vignette), so the
  broad dip is largely rangeland; **logging = the subset where the green tree corridor drops sharply**.
- User ground truth: the LULC vignette shows **Trees → Rangeland** transitions; a cut is visible at the
  **north confluence** changing 2020→2023; **some cuts are 2022–2023** (inside our monitoring window).
- Key method note carried into this cycle: `bfastmonitor` treats everything before `start` as stable
  history, so a pre-`start` cut is invisible; 2022–2023 cuts with `start = 2022` ARE catchable.

## This cycle's findings

(to be appended as the redo runs — cube stats, break-vs-LULC agreement, cut date, reducer choice)

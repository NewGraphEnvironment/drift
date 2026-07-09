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

**2017–2023 fetch** (2026-07-09): offset split fired 87 pre / 85 post; 84 monthly layers;
per-year gs kNDVI 2017=0.476 … 2021=0.524, 2022=0.529, 2023=0.429 (aligns across 2022, real 2023
dip). Cube built in **11 min**, cached in `data-raw/.break_cache`. Breaks: 13,112 finite (vs 25,550
on the 2018-start run — the longer 2017–2021 history is a more robust baseline, fewer false breaks),
88% negative, dated 2022.42–2023.67.

**LULC validation** (bfast break map vs IO LULC Trees→Rangeland/Bare, 2020→2023): tree-loss pixels
(n=2132) break at **25% vs 13% background** (2×) and with **median mag −0.054 vs −0.020** (2.7×).
So the trajectory method genuinely picks up LULC tree loss. Break dates on tree-loss pixels cluster
at **median 2023.58 (91% in 2023)** — consistent with "cuts 2022–2023", and the value-add: annual
LULC can only bracket "2020–2023", bfast dates it to summer 2023.

**Caveats (honest):** the signal is statistical, not a dramatic clearcut. (a) LULC "tree-loss" pixels
sit ~0.1 BELOW intact forest throughout 2017–2021 — IO LULC "Trees" at 10 m is generous (open /
riparian / edge canopy), so they don't start from a high forest baseline; (b) they end ~0.35 in 2023
(thinned / regrowth, not bare-soil ~0.15); (c) 75% of LULC tree-loss pixels register no bfast break
(below significance in noisy monthly data, or cut pre-2022 = in history). Intact forest (n=4301) stays
~0.5–0.6 and dips only slightly in 2023, so the tree-loss-below-intact divergence IS visible in 2023.

**Verdict:** the 2017–2023 redo is clearly better than the shipped 2018-start example — more selective
breaks, a real (if modest) LULC agreement, and honest timing. Recommended vignette framing: "the
trajectory method flags the same stands LULC maps as lost, ~2× the rate and stronger, and dates it to
summer 2023 — timing annual LULC cannot give," with the regional 2023 dip acknowledged, not hidden.

**Reducer decision:** keep `bfastmonitor(start = c(2022,1))` — cuts are 2022–2023 (in-window), and the
2017–2021 history is a strong baseline. Full `bfast()` not needed for this example.

## Pivot: categorical-vs-continuous reconciliation → the real value (QA + trend)

User pushed on why bfast's gentle signal disagrees with LULC's dramatic Trees→Rangeland *inside* the
floodplain. Diagnosed with the cached cube: the LULC "tree-loss" pixels had kNDVI baseline **0.43**
(vs 0.50 intact), only **14%** forest-like (>0.5), dropped a median of **0.037** by 2023, only **2%**
a genuine high→low crash. So on this **deciduous-riparian** reach, IO LULC "Trees" is a loose label
and its "Trees→Rangeland" is largely **borderline pixels flipping category on a tiny greenness
change** — the categorical product **overstates** forest loss. In peak summer, deciduous riparian
trees and grass are both green (~0.43), so kNDVI/bfast structurally cannot separate them the way the
structure-based classifier can → the trajectory tools are **weak** on this landscape for tree-vs-grass,
but valuable as a **QA check** on the categorical change and for **gradual degradation/recovery**.

**Added `dft_rast_trend()`** (Theil-Sen slope + Mann-Kendall p, robust to the 2023 dip). AOI-restricted
trend by group: tree-loss median **~0** (6% sig-declining), intact forest **+0.0026** (2%), open
background **+0.013** (17% recovering). → floodplain is **stable-to-recovering**, and the mapped
"forest loss" is **not backed by a real greenness decline** — an evidence-based "leave it standing"
result and the honest, goal-aligned framing the vignette now uses.

**Palette bug caught in self-review:** `hcl.colors("Blue-Red 3")` puts red at the HIGH end, so
red = recovering by default; captions said red = declining. Fixed with `rev = TRUE` on both maps so
red = declining/loss (intuitive), consistent across the trend and break maps.

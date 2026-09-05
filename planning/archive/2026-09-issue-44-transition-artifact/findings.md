# Findings — Detect geometric edge/misregistration artifacts in transitions (#44)

## Issue context

## Problem

Year-to-year classified land cover carries geometric artifacts that look like real transitions but are misalignment, not change:

- **One-sided edge shift.** A forest stand reads as Trees in 2017 and Rangeland in 2023 along a thin band on one side, because the boundary moved by a pixel between epochs (co-registration offset, mixed-pixel resampling, differing overpass geometry). The stand did not change.
- **Reciprocal / compensating shift.** Along a river, one bank maps Trees -> Water while the opposite bank maps Water -> Trees. Net area change is ~zero. The channel did not migrate; the grid shifted.

Both inflate reported change, and both concentrate exactly where riparian/floodplain work is focused — on long linear boundaries (banks, forest edges, field margins).

## Why the existing tools do not cover this

**`dft_rast_consensus()` (#8) is temporal only.** #8's own Problem section names this exact failure ("slight geometric shifts between satellite passes (edge pixels flip classes)", "inflates apparent change, especially at class boundaries") but shipped a per-pixel mode filter. Mode across years only helps when a pixel flips *randomly* year to year. A **systematic** co-registration offset between epochs is preserved by the modal class in each window — consensus cannot remove it. #8 closed the temporal half of its own motivation and left the spatial half open. #9 (weighted mode / categorical breakpoints) is likewise on the time axis.

**The spectral check (#30, `dft_rast_break()` + the "Trajectories as a Check on Land-Cover Change" vignette) already covers part of this and should not be duplicated.** It explicitly flags "an outline with no red" as "likely a borderline pixel changing label rather than trees coming off". It does not reach:

1. **Forest <-> rangeland edges** — the vignette's own caveat: "in peak summer, deciduous riparian trees and grass are both green, so kNDVI cannot cleanly separate them — weakest at telling riparian tree from rangeland". This is the most common edge artifact in the AOIs we run.
2. **The reciprocal case** — kNDVI over water is uninformative, and more fundamentally "these two patches compensate, so it is a shift" is a *geometric relationship between two patches*. A per-pixel spectral test structurally cannot express it.
3. **Categorical-only workflows** — the check costs a Sentinel-2 cube (10-30 min stream) plus bfast. No S2, no check.
4. **Scale** — it is read by eye off a map. There is no per-patch value to sort or filter hundreds of thousands of patches by.

**`patch_area_min` is the wrong axis.** Area is a product of width and length. A threshold on the product cannot constrain either factor. Slivers are pathological in *width*; their area is driven by *length*, which is a property of how long that boundary runs — not of whether the change is real.

One pixel at 30 m is 0.09 ha, so a 1-pixel-wide band needs very little boundary to clear any sane threshold:

| Threshold | 1-px band length needed @ 30 m | @ 10 m |
|---|---|---|
| 0.5 ha | 167 m | 500 m |
| 1 ha | 333 m | 1.0 km |
| 5 ha | 1.7 km | 5.0 km |

A 5 km river bank at 30 m, one pixel wide, is **15 ha** — through every threshold in the land-cover vignette's comparison table.

The trap is symmetric, which is why no threshold value fixes it:

- Raise `patch_area_min` enough to kill a long sliver and it also deletes genuinely small real changes (a 0.5 ha cutblock, a fresh bar).
- Lower it to keep those and long slivers walk through.

A 15 ha sliver (~0.5 px wide) and a 15 ha real clearing (~40 px wide) are identical on the area axis and ~80x apart on the width axis. It is a 2-D problem filtered with a 1-D test. Width is **orthogonal and composable** with `patch_area_min`, not a replacement — and adding it lets `patch_area_min` be lowered, recovering small real changes currently discarded as speckle.

## Evidence

Probe on the bundled Neexdzii Kwa tile (`example_2017.tif` / `example_2023.tif`, IO LULC, 10 m, 2017->2023, `changes_only = TRUE`): 93 change patches, 34 ha total.

Effective width metric `2 * area / perimeter`, validated against known shapes at 10 m: single pixel -> 0.50 px, 10 x 200 m sliver -> 0.95 px, 200 x 200 m blob -> 10.0 px.

- 75 / 93 patches (81%) are under 1.5 px effective width, but only 16% of change *area*.
- At `patch_area_min = 5000`, one sliver still survives: 7,500 m2, 1.44 px wide, `Trees -> Rangeland`.
- Reciprocal transitions are present (`Trees -> Rangeland` 21.11 ha vs `Rangeland -> Trees` 0.85 ha) but no forward patch touches a reverse patch on this tile.

Honest caveat: this test reach is small, so `patch_area_min` mostly does work here. The probe demonstrates the *mechanism* (a sliver surviving the area filter) but not the magnitude. The magnitude shows up on long-boundary AOIs — the `restoration_wedzin_kwa_2024` floodplain (12,960 ha of Trees->Trees, ~1,100 ha of change, per #22) is the case to measure against.

## Proposed solution

A new `dft_transition_artifact()` that tags patches with geometric artifact evidence. Domain-free and cheap: **every signature below is derivable from the transition raster alone**, no extra fetch, because the transition raster already encodes both epochs (`from_code = id %/% 1000`, `to_code = id %% 1000`).

Three signatures:

1. **Sliver width** — effective width `2 * area / perimeter`, reported in metres and pixels.
2. **Boundary-hugging** — share of the patch lying within N cells of the pre-existing from/to class interface. This is the disambiguator width alone cannot provide: **a real road or harvested strip cuts *across* class boundaries; a registration artifact *traces* an existing one.** Likely `terra::boundaries()` on the from-class mask.
3. **Reciprocity** — does an `A -> B` patch share a substantial boundary with a `B -> A` patch of comparable area? Records the partner `patch_id`. This is the river case, and it is unavailable to any per-pixel method.

### Tag, do not drop

Unlike `patch_area_min`, this must **add columns and let the caller decide** — real changes are sometimes genuinely thin (harvested riparian buffer strips, new roads, real channel migration). Returning evidence rather than silently deleting also matches the `$removed` precedent from #17.

### API sketch (to be refined at planning time)

```r
dft_transition_artifact(patches,
                        transition,               # SpatRaster from dft_rast_transition()
                        width_max = 1.5,          # pixels; below this flags a sliver
                        boundary_dist_max = 1,    # pixels from the from/to interface
                        reciprocal = TRUE)
```

Adds to `patches`: `width_m`, `width_px`, `flag_sliver`, `boundary_frac`, `flag_boundary`, `reciprocal_id`, `flag_reciprocal`. Whether to also emit a single composed `flag_artifact` is an open design question — composition may be better left to the caller.

Params follow the noun-first convention (`width_max`, `boundary_dist_max`), matching `patch_area_min`.

## Out of scope

- **Correcting** the artifact (co-registration / warping). This detects and tags only.
- Anything on the temporal axis — that is #9.
- Duplicating the spectral route — #30 shipped it; this is the free categorical-only complement, and the two should be cross-referenced as alternative confirmation routes.
- BC/domain-specific knowledge, per drift's generic-by-design stance.

## Acceptance

- Works on any factor transition raster, not just IO LULC.
- Synthetic fixtures with a known 1-px shift reproduce both the one-sided and reciprocal signatures.
- A real thin change (a road cutting across classes) is *not* flagged as boundary-hugging — the discriminator earns its place.
- Documented in the land-cover vignette alongside `patch_area_min`, with a pointer to the trajectory vignette as the independent spectral confirmation route.

Relates to #8 (temporal half), #9, #22, #30.


## Plan-mode probes (2026-09-04)

- sf 1.1.2 exports `st_perimeter()`; terra 1.9.34.
- Shared boundary between two raster-cell polygons: `st_length(st_intersection(st_boundary(a), st_boundary(b)))` is 10 m for an edge share and 0 for a corner touch — corner-only contact is distinguishable.
- `terra::rasterize(vect(patches), transition, field = "patch_id")` round-trips the `dft_transition_vectors()` output exactly: 3403 cells rasterized, 3403 cells of patch area.
- Bundled tile 2017→2023, `changes_only = TRUE`: 93 patches, width `2A/P` quantiles 0.50 / 0.50 / 0.75 / 1.19 / 6.78 px; 75/93 (80.6%) under 1.5 px — reproduces the issue's evidence.
- `_pkgdown.yml` carries no `reference:` index, so a new export needs no pkgdown edit.

## Errors Encountered

| Error | Resolution |
|-------|------------|

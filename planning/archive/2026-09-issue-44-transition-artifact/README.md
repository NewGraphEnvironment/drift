# Issue #44 — dft_transition_artifact(): sliver width, boundary-hugging, reciprocal pairs

## Outcome

Added `dft_transition_artifact()`, which tags the patches from `dft_transition_vectors()` with
geometric misregistration evidence and drops nothing: effective width `2 * area / perimeter`
(`width_m`, `width_px`, `flag_sliver`), the share of a patch adjacent to the from-epoch
interface with its to-class (`boundary_frac`, `flag_boundary`), and the nearest reverse-
transition partner of comparable area (`reciprocal_id`, `reciprocal_dist_m`, `flag_reciprocal`).
Every signature is read from the transition raster alone, streamed (one `terra::focal()` pass
per to-class, `rasterize` + `zonal`), so it costs no extra fetch and works on any factor
transition raster — the tests use a synthetic 4-class table, not IO LULC. No composed
`flag_artifact` is returned; the caller composes. Documented in the land-cover vignette as a
new *Geometric Artifacts* section beside `patch_area_min`, with the trajectory vignette named
as the independent spectral route.

One deliberate deviation from the issue: reciprocity is a proximity test
(`reciprocal_dist_max`, default 5 px) rather than "shares a boundary". The two bands of a shifted
channel sit on opposite banks with the stable channel between them and touch only when the
river is one pixel wide — which is also why the issue's own probe found no touching pairs.

## Measurement

Bundled Neexdzii Kwa tile, 2017 -> 2023, `changes_only = TRUE`: 93 change patches, 34 ha.
75 (80.6%) are under 1.5 px effective width and hold 16.5% of the change area; 48 of those
also trace a pre-existing boundary (12% of area); 5 have a reciprocal partner. With
`patch_area_min = 5000`, 10 patches survive and exactly one is a flagged sliver — a
`Trees -> Rangeland` band, 0.75 ha, 1.44 px wide, `boundary_frac` 0.71 — the mechanism the
issue described, reproduced. Runtime 0.19 s on the tile. Magnitude on a long-boundary AOI
(`restoration_wedzin_kwa_2024`, ~1,100 ha of change per #22) is the follow-up measurement;
it is a floodplains-driver run, not a drift change.

Two review findings changed the code, both caught by a fresh-eyes round rather than by tests:
`sf::st_perimeter()` delegates to lwgeom on projected data (not a dependency — every install
without it would have failed on first call, suite green only because lwgeom was installed
locally), replaced by `st_length(st_boundary())`, identical on all 93 patches; and Fixtures C/D
originally reached `boundary_frac == 0` only because the to-class was absent from the from
epoch, so a degenerate implementation would have passed — fixed by placing stable blocks of
the to-class elsewhere and pinning a fractional 4/20.

## Evidence

`planning/archive/2026-09-issue-44-transition-artifact/review-round{1,2,3}.md` — three
review rounds with every numeric pin independently re-measured; `tests/testthat/test-dft_transition_artifact.R`
pins the bundled-tile numbers above.

Closed by: branch `44-detect-geometric-edge-misregistration-art` (commits 7bbb86e, 4716154, a776cf8, 3b575ea) / PR #60

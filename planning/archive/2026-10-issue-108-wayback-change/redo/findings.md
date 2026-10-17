# Findings: article redo (#108)

## STAC item (measured 2026-10-16)
- `bulk_co_ff04` is gone from the catalogue; its S3 files return 403. Current: `bulk_all_ff04`,
  processing:datetime 2026-10-14T13:33:49Z, drift 0.20.0, flooded 0.7.0, link 0.50.0.
- Assets: floodplain.gpkg (layers all_ff02/all_ff04/all_ff06/all_ff04_by_blue_line_key, EPSG:3005),
  classified_2017..2023 (10 m, EPSG:32609, NA outside the floodplain), transition_vector.gpkg (layer
  `transition`, no break year).
- Over the box: 39,362 floodplain cells. dft_break_category: break_sustained 36.6 ha, break_endpoint 31.8,
  unsettled 52.7, stable_flicker 63.6. Largest clean switches: Trees->Rangeland 2023 21.0 ha,
  Crops->Rangeland 2020 17.4, Trees->Rangeland 2019 8.4, 2021 4.2, 2018 4.0, 2022 2.8.
- A switch in 2018 or 2023 is `break_endpoint` by construction (one year on one side), so the imagery is
  what confirms those.

## Code folding under pkgdown 2.2.0
- `code_folding: hide` is ignored (code shown unfolded).
- `<details>` from a knitr `source` hook works.
- `knitr::read_chunk("../../data-raw/x.R")` breaks the build: rmarkdown tries to copy the path as a
  resource, and knitr pre-evaluates read_chunk calls. Reading the script with readLines() and passing
  `code = from_script("label")` works.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `read_chunk(p)`: object 'p' not found | knitr pre-evaluates read_chunk; use `code =` with readLines |
| Wayback metadata HTTP 502 after 25/182 releases (32.9 min cold) | Transient; the run was cold only because the box corners were rounded differently from the old script's, so every cache key missed. Used the old full-precision corners: 182 releases in 0.5 min warm |
| bcdata: `No known SQL translation` for `INTERSECTS(sf::st_transform(aoi, 3005))` | Compute the geometry before `filter()` |

## The change areas against the imagery (2026-10-16)

Ten areas of 1 ha or more (A-J). A-E (2018-2020) have Wayback 2016-09-11 before and 2020-09-18 after, each
covering the whole view. Looked at full size: only C (2019, Trees to Rangeland) is a change on the ground
(creekside forest opened up, new trails). A, D, E are touching parts of one meadow, the same in both images (E runs into a farmyard) (Crops to
Rangeland; D striped by cutting or tilling in 2016, grassed in 2020); B is the same stand of trees.
Sentinel-2 brightening alone would have misled: A brightens 64 display units in 2018 while the box
moves 1. F, H, I, J (2021-2023) are forest in the 2020 image and G is an open wet meadow along a channel (my first read called it forest; review r1 measured it brighter and smoother than its ring); all five and brighten by 47-110 units in their year
against -4 to 30 for the box. I is 27% inside a 2023 cutblock; no other area is 10% or more in one.
2019 is pale across the box (+63 over 2018) and 2017 is a single scene.

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

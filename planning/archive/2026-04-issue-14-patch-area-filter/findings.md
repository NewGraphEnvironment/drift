# Findings: min_patch_area filter

## Test Data Properties
- Rasters: 314x326, 10m resolution, UTM zone 9 (EPSG:32609)
- Cell area: 100 m² (10m x 10m)
- Changed pixels (2017→2020): 2974 of 12311 valid pixels
- Files: example_2017.tif, example_2020.tif, example_2023.tif

## Patch Size Distribution (2017→2020 test data, 8-connected)
- 15 total patches, no single-pixel patches
- Min: 4 px (400 m²), Max: 6258 px (625,800 m²), Median: 49 px (4,900 m²)
- 2 patches <= 5 px (500 m²): sizes 4 and 5
- 5 patches in [5,10) px range
- Good test thresholds: 500 m² (removes 2 patches), 1000 m² (removes 7 patches), 50000 m² (removes 11 patches)
- Largest 3: 6258, 3412, 1606 pixels

## Implementation Notes
(pending Phase 2)

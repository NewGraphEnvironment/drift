## Outcome

Added `patch_area_min` parameter to `dft_rast_transition()` for filtering classification noise, `$removed` raster for visual QA of filtered patches, and `dft_check_crs()` guard against geographic CRS inputs. Updated vignette with filtering demo.

## Key Learnings

- Patch filtering must operate on actual changes only (from != to), not same-class pixels
- CRS check needed on both from and to rasters (code review caught the mismatch gap)
- `$removed` raster enables iterative threshold tuning without leaving R
- Test data has few small patches — 5,000 m² threshold needed to show meaningful visual difference in vignette
- `terra::freq()` on factor rasters returns labels not IDs — pre-existing behavior, works with current terra 1.9.1

## Closed By

PR #20 merging branch 14-patch-area-filter. Closes #14, #15, #17.
Also filed #16 (cellSize for geographic CRS), #18 (transition vectors), #19 (arbitrary factor raster support).

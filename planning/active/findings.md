# Findings — Dated reference imagery (#79)

## Issue context

## Problem

Checking a land-cover label or a detected change needs **dated reference imagery for windows we choose**: the same season in different years, or early vs late season within a year. The basemaps in `dft_map_interactive()` (Esri, Google, and Bing in #78) are high resolution but have no date, so they can say what a place is and not when it changed.

drift already fetches Sentinel-2 L2A cubes (`dft_stac_cube()`, with cloud masking, a `months` filter and median aggregation), but only as a **single-index stack** (`ndvi`, `kndvi`, `ndmi`). Three pieces are missing to use it as a reference-imagery source. floodplains#93 needs them for a stratified accuracy assessment of IO LULC in BC floodplains.

## Scope

1. **True-colour (and false-colour) composites.** Return a multi-band composite (e.g. B04/B03/B02, or B08/B04/B03 for vegetation) for a `datetime` window and `months`, through the same cloud mask, cache and tiling path as `dft_stac_cube()`. The new_graphiti post `2026-01-08-stac-ortho-mosaics` did this outside drift with rstac + gdalcubes (June–July, `eo:cloud_cover <= 20`, median). That code is the starting point, and should not become a second copy.
2. **Water and wetness indices.** Add NDWI (green/NIR) and MNDWI (green/SWIR16) to `dft_index_table()`. `ndmi` is there already. These are the direct indices for wetland drying and water extent.
3. **RGB layers in `dft_map_interactive()`.** Today `x` is classified rasters coloured through `class_table`. Accept RGB composites as switchable overlays too, with labels such as `"2017 Jun–Jul"` and `"2023 Aug–Sep"`, alongside the classified layers and transitions.
4. **HLS as a second cube source (can split off).** Harmonized Landsat Sentinel-2 through NASA Earthdata (`earthdatalogin`): 30 m, from 2013, 2–3 day revisit. It gives a pre-2017 baseline and the seasonal density Sentinel-2 alone lacks. It needs an auth path distinct from Planetary Computer's `sign_fn`.

## Acceptance

- A documented call returns a cloud-masked, median true-colour composite for an AOI, a year and a set of months. It is cached, and the cache key includes the bands and months.
- `dft_index_table()` includes `ndwi` and `mndwi`, with tests against known band values.
- `dft_map_interactive()` shows at least two dated RGB composites as switchable layers over the Esri/Google basemaps.
- HLS is either delivered or filed as its own issue, with the auth path worked out.

## Related issues re-read at the plan gate (2026-09-28)

- **drift#80:** gdalcubes was archived on CRAN on 2026-09-16. Upstream `appelmar/gdalcubes` master (0.7.5, `ed68331`) has merged our `filter_geom` fix (their PR #111). Handled in its own PR first.
- **drift#81:** the Olofsson 2014 sampler and estimators. It supplies the sample points that the reference imagery is reviewed at, and lists the review UI as out of scope (it points to #79).
- **floodplains#93:** "for each sample point: a map zoomed to the point, the dated composites as switchable layers". The review runs over whole floodplains, not a reach, which is why this issue has to hold at floodplain scale.
- The new_graphiti post `2026-01-08-stac-ortho-mosaics` is the starting point: rstac, bbox search, `eo:cloud_cover <= 20`, B04/B03/B02, `dt = P2M`, median, `leafem::addRasterRGB(quantiles = c(0.02, 0.98))`. It has no cloud mask and no offset handling, and stretches each layer on its own.

## Errors Encountered

| Error | Resolution |
|-------|------------|

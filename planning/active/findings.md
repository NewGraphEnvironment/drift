# Findings — Promote Esri Wayback capture index + chip fetch to dft_wayback_* (#101)

## Issue context

**If we do it:** any floodplain AOI can get Esri Wayback imagery at the **capture** nearest a date, per point or per patch, from one package call. Today that code lives only as two driver scripts in floodplains.
**If we never do:** the next consumer (another area's accuracy review, a change-patch check, rtj) re-derives the release-vs-capture trap and the QGIS redirect workaround from scratch.

That has started to happen: a third script, which frames one site at a dated capture for a figure, already carries its own copy of the release lookup and the GDAL WMS block (2026-10-14).

## What exists (NewGraphEnvironment/floodplains#115, proven on NECR)

`scripts/landcover_accuracy/wayback_index-capture.R` and `wayback_build-chips.R`, plus helpers in `fp_accuracy.R`: `fp_acc_wayback_pick`, `fp_acc_wayback_wms_xml`.

- **Release list.** Read from `waybackconfig.json`, which held 197 releases on 2026-10-08. Release ids are not ordered by date.
- **A release date is not a capture date.** Each release's metadata MapServer has one layer per scale band, and layer `L` describes tile zoom `23 - L`. Query layers 4-6 once per release over a bbox, page the results, request `geometryPrecision=1` (one release-layer answers HTTP 500 at full precision), and join locally.
- **Selection.** The capture nearest a target date, ranked by whole years, then days from 1 July, then finer `SRC_RES`, then the later release.
- **Fetch.** A GDAL WMS (TMS) XML per release and zoom, with a tile cache. GDAL follows the relative 301 that QGIS cannot (qgis/QGIS#54161). A 404 tile becomes zeros: test for empty, but **not** for flat, since open water is flat.
- **Mosaicking per-point chips.** A VRT ignores a source's mask band when it composites but honours its nodata. So overlapping chips must be clipped with nodata (Voronoi cells), not with masks.

## Proposal

Product-specific, named for the product: `dft_wayback_*`. The second word of a drift name is a family (`stac`, `rast`, `accuracy`, `transition`), and "wayback" is what someone with this problem searches for.

```r
dft_wayback_releases()                        # release id, release date, metadata URL; sorted by date
dft_wayback_captures(aoi, zoom)               # one row per (feature, release, capture): capture_date, res_m, source, release_id
dft_wayback_pick(captures, date)              # per feature, the capture nearest `date`
dft_wayback_fetch(aoi, release, zoom)         # local raster for that release, clipped to aoi
```

- **`dft_wayback_captures()` takes `zoom`, not metadata `layers`.** The layer-to-zoom mapping (layer `L` describes zoom `23 - L`) is the quirk the function exists to hide, so it is mapped internally. So are `geometryPrecision=1` and paging.
- **`dft_wayback_pick()` takes a target `Date`, not an endpoint year.** It ranks by distance from that date, then finer `res_m`, then the later release. The floodplains rank (whole years from the endpoint, then days from 1 July) is a study-design choice from the NECR labelling key, and the driver expresses it by passing `as.Date("<year>-07-01")`. If the whole-year banding turns out to matter, it becomes an argument, not a default.
- **`dft_wayback_fetch()` takes `aoi`, like `dft_stac_composite()`,** so the per-point pattern carries over unchanged: one call per buffered point, each cached separately. The GDAL WMS (TMS) XML builder stays internal.
- **Output shape is the general contract, not the function names.** Captures come back as (feature, source, capture_date, res_m, handle), the same shape as floodplains' dated-imagery index for orthophoto and air photos. So the pick works on any dated source's rows, and a later generalisation is a wrapper, not a rewrite.

### Not a general `dft_imagery_*(source = )`

The dated sources share a table shape and nothing in access, and the others already have owners:

| source | access | owner |
|---|---|---|
| BC air photos | DataBC centroids → thumbnail → georeference | `fly` (`fly_fetch`, `fly_georef`, `fly_coverage`) |
| orthophoto | STAC catalogue of COGs | `dft_stac_*` with `stac_url =` |
| Sentinel-2 | STAC + gdalcubes | `dft_stac_composite()` |
| Esri Wayback | tile service + per-release metadata MapServer | this issue |

drift's `source =` pattern works because every source goes down one STAC path. A Wayback source would need its own backend, and it would be the only implementation. Revisit if a second source in drift ever needs the same index → pick → fetch steps.

The floodplains scripts then become thin drivers. Promote once the NECR review has used the chips. That is the "once proven" from floodplains#115's decisions.

_Body edited 2026-10-14: signatures revised (`zoom` for `layers`, a target `Date` for the pick, `aoi` for `extent, crs`) and the case against generalising recorded._



## Exploration (2026-10-14)

- Source: floodplains `scripts/landcover_accuracy/wayback_index-capture.R` (172 lines), `wayback_build-chips.R`
  (258), helpers `fp_acc_wayback_pick` / `fp_acc_wayback_wms_xml` in `fp_accuracy.R` (floodplains a91acdb).
- floodplains#115 closed 2026-10-09; no NECR labels exist yet, so the issue's "once the NECR review has used
  the chips" gate is not met. Proceeding on the user's invocation.
- `waybackconfig.json`: 197 releases; `itemTitle` "World Imagery (Wayback YYYY-MM-DD)"; keys are release ids.
- Metadata MapServer layers 0-13: 0 = 1.9 cm (zoom 23) ... 13 = 150 m (zoom <= 10, maxScale 0). Valid zoom 10:23.
- floodplains takes the DEEPEST of layers 4-6 per (point, release); NECR wayback.csv is mostly zoom 18.
- floodplains pick ranks whole years from the endpoint, then days from 1 July; drift ranks days from a target
  Date (issue decision). Equivalence run in Phase 5 measures where those differ.

## Errors Encountered

| Error | Resolution |
|-------|------------|

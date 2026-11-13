# Findings — MODIS vegetation indices (MOD13Q1) as a cube source from Planetary Computer (#115)

## Issue context

**If we do it:** drift gives a vegetation index for any year from 2000, at 250 m every 16 days, from the same Planetary Computer catalogue and signing it already uses. **If we never do:** an index before 2017 needs another tool. Today that is `MODISTools`, which reads one point at a time from a single web service; during one run in November 2026 that service took longer than R's 60 s limit and then returned HTTP 502.

## Problem

`dft_stac_cube()` has one source, `sentinel-2-l2a`, available from 2017. A site-level covariate for a survey run before 2017 (here, camera stations surveyed every year from 2008 to 2017) has no index from drift for most of its years. MODIS Terra/Aqua vegetation indices (MOD13Q1 v6.1) cover 2000 to the present, and Planetary Computer holds them as the STAC collection `modis-13Q1-061`, as Cloud Optimized GeoTIFFs. #82 (HLS) is the 30 m route from 2013 and needs Earthdata Login; this one needs no account.

## What a probe established (2026-11-13, one item, `MOD13Q1.A2017113.h09v07.061`)

- **Temporal extent:** 2000-02-18 to open. 16-day composites at 250 m.
- **Assets** (all COGs, `int16` unless noted): `250m_16_days_NDVI` and `250m_16_days_EVI` (scale 1e-4, already computed); `250m_16_days_red_reflectance`, `_NIR_reflectance`, `_blue_reflectance`, `_MIR_reflectance` (scale 1e-4); `250m_16_days_pixel_reliability` (`int8`); `250m_16_days_VI_Quality`; plus `hdf` and `metadata`.
- **Mask:** `pixel_reliability` is a class band with values 0 good, 1 marginal, 2 snow/ice and 3 cloudy, listed in the asset's `classification:classes`. That fits drift's existing `mask_values` shape, unlike HLS's bit mask. The product's fill value, -1, is not among the listed classes and needs checking.
- **Three ways it differs from `sentinel-2-l2a` that the read path may trip on:**
  - `properties$datetime` is `null`; each item carries `start_datetime` and `end_datetime` (the 16-day window). A search for 2017-01-01/2017-04-30 returned an item for 2017-04-23 to 2017-05-08, so the search matches by window overlap.
  - There is no `eo:cloud_cover`, so a `cloud_cover_max` filter has nothing to read: it may drop every item or be skipped silently. Which one happens needs checking.
  - The grid is MODIS sinusoidal, given as `proj:wkt2` with no `proj:epsg`.
- **Band roles:** red, nir and blue map directly. The MIR band is 2105–2155 nm, the `swir22` range, so the indices that use the `swir16` role (`ndmi`, `mndwi`) have no MODIS band.

## Proposed Solution

1. A `modis-13Q1-061` cube source in `dft_stac_config()`: roles `red`, `nir`, `blue` and `mask = "250m_16_days_pixel_reliability"`; scale 1e-4, no offset; `mask_values` defaulting to `c(2L, 3L)` plus the fill value; available from `2000-02-18`.
2. A decision, offered here and not yet made: compute `ndvi`/`kndvi` from the red and NIR roles as for Sentinel-2, or read the published `NDVI`/`EVI` assets directly. EVI saturates less than NDVI under dense canopy, and the index table has no EVI today.
3. Make the read path handle an item with only `start_datetime`/`end_datetime`, and refuse `cloud_cover_max` for a source without `eo:cloud_cover` instead of passing it through.
4. A test that takes a fixture item with these three properties (null `datetime`, no `eo:cloud_cover`, WKT-only CRS) through item selection, and one live read of a small AOI over a 16-day window.

Relates to #82

## Probe 2026-11-13 (plan mode, packaged AOI, 2017-06-01/2017-09-30)

Script: `/private/tmp/claude-501/-Users-airvine-Projects-repo-drift/7b6be7fe-e891-4f33-94a3-c89a67f00b5e/scratchpad/probe115.R` (scratch, not committed). Results are in task_plan.md, "What exploration found".

## Errors Encountered

| Error | Resolution |
|-------|------------|

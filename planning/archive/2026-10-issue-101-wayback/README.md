## Outcome

Promoted floodplains' Esri Wayback scripts (floodplains#115) to four drift exports. `dft_wayback_releases()`
lists the releases. `dft_wayback_captures()` reads each release's capture metadata per feature: the
deepest zoom covering the feature whole, the top-drawn capture at a point, and visible `cover` for a
polygon. `dft_wayback_pick()` takes the capture nearest a target date, and `dft_wayback_fetch()` warps
one release at one zoom to a cached, nodata-masked RGB COG.

The plan review reshaped polygon handling (DrawOrder occlusion, a zoom rule for polygons) and paging.
Measurement then changed the fetch: there is no GDAL tile cache, `-ovr NONE` is passed, and zoom is
capped at 22. Code review found sf's default `st_make_valid()` dropping touching parts of multi-part
footprints (floodplains has the same parse) and an sf version floor. The NECR equivalence reproduced
every floodplains pick and chip. The floodplains drivers become thin wrappers in floodplains#134.
Durable verdicts are in [`research/esri-wayback.md`](../../../research/esri-wayback.md).

## Measurement

- **NECR picks:** 960 of 960 (point, endpoint) picks are identical to floodplains' `wayback.csv`, both
  with the default make_valid parse and with the fixed one. So the parse bug moved no NECR pick, and
  ranking by days from `<endpoint>-07-01` reproduced the whole-year banding.
- **NECR chips:** 20 random chips re-fetched on floodplains' grids: at least 99.998% of cells identical,
  largest band difference 1.
- **NECR cost:** captures for 480 points over 197 releases took 39.9 min, then 49.3 min on the fixed
  parse. Both were network-bound, with metadata answers slowing from about 2.6 s to about 30 s per
  release. Peak RSS was 1.8-2.2 GB.
- **BULK cost:** captures over 21,701 change patches for one release took 36.2 s cached at first, then
  12.7 s after preparing the footprints rather than the patches and dropping the CRS inside the join,
  then 18.7 s once the parse runs on every read. Peak RSS 0.82-1.43 GB. All 197 releases at that scale is
  about an hour.
- **GDAL 3.13.0:** zoom 23 fails with `Invalid dataset dimensions`. A WMS `<Cache>` reports each 404
  tile as two read errors. gdalwarp reads a shallower zoom from the WMS overviews at a coarse `-tr`. Each
  of these changed the fetch's design.

## Evidence

Run scripts and logs lived in the session scratchpad (`necr_equiv*.R`, `bulk_*.R`, `fetch_probe.R`) and
were not committed. Their numbers are in `findings.md` here and in `research/esri-wayback.md`. The review
reports are `review-plan.md` and `review-round{1,2,3}.md` in this directory.

Closed by: PR (drift#101)

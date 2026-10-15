# Esri World Imagery Wayback: what the service and GDAL actually do

**Verified:** 2026-10-14 · **Issues:** drift#101 (from floodplains#115), floodplains#134 ·
**Produced by:** live probes of `waybackconfig.json`, the per-release metadata MapServers and the tile
service, and the NECR equivalence run recorded in
`planning/archive/2026-10-issue-101-wayback/` (README, `findings.md`) · **drift:** `dft_wayback_*`

## The service

- **A release date is not a capture date.** A release is the World Imagery mosaic as published that day,
  and it mosaics captures of many years. Choose by capture, from the metadata. 197 releases on 2026-10-14;
  release ids are not ordered by date.
- **Metadata layers 0-13, layer `L` describes tile zoom `23 - L`**, with layer 13 covering every zoom at or
  below 10. That holds on releases from 2014 to 2026, and matches Esri's own client (`getLayerId()`:
  `23 - zoom`, capped at 13).
- Each metadata layer supports pagination and `orderByFields`, with a `maxRecordCount` of 1000.
  `SRC_DATE` is an integer `YYYYMMDD`, and a base layer's is `null`. Some release-layers answer HTTP 500
  to a full-precision geometry request every time, and answer at `geometryPrecision=1`.
- **Footprints overlap.** The tiles draw the highest `DrawOrder` on top. In practice `DrawOrder` is
  constant within a layer, and real overlaps between different captures are slivers.
- **Tiles are deduplicated across releases.** A release that has not changed a tile 301-redirects, with a
  relative `Location`, to the release that last did. GDAL follows it and QGIS does not (qgis/QGIS#54161).
  A tile a release lacks answers HTTP 404.

## GDAL (3.13.0) over the tile service

- **Zoom 23 cannot be opened.** The world at zoom 23 is 2^31 pixels wide, which fails with
  `Invalid dataset dimensions : -2147483648 x -2147483648`. Zoom 22 opens.
- **A `<Cache>` element turns every 404 tile into two read errors.** GDAL raises `No such file or
  directory` on the cache path, then `GDALWMS: Unable to open downloaded block`, both as warnings, while
  the values are still the zeros `ZeroBlockHttpCodes` promises. Without `<Cache>`, the same tiles come
  back as clean zeros. A fetch that treats GDAL warnings as failures therefore needs no `<Cache>`. Not
  reported upstream as of this date.
- **`gdalwarp` uses WMS overviews unless told not to.** At a `-tr` coarser than the zoom's ground
  resolution it reads a shallower zoom, which can show another capture. `-ovr NONE` forces the zoom asked
  for.
- A zoom's ground resolution is `156543.03392 / 2^z * cos(lat)`: 0.70 m at zoom 17 and 0.35 m at zoom 18,
  both at 54 N.

## Parsing footprints (sf 1.1.2 / GEOS 3.13.0)

- **`sf::st_make_valid()` defaults to `valid_structure`**, which takes ring 1 as the shell and every
  later ring as a hole. On a multi-part Esri footprint it drops a part that touches the first (two
  squares sharing an edge parse to half their area) and fills a hole in any later part. Use
  `geos_method = "valid_linework"`, which sorts the rings by parity. This needs sf >= 1.0-8.
- Live, over BC, 17 of 101 multi-ring footprints in one 2014 release parse differently under the two
  methods. On the NECR sample the difference moved no pick (960 of 960 identical either way).

## NECR equivalence (drift against floodplains' driver scripts)

- **Picks:** with captures at zoom 17:19 and the pick at `<endpoint>-07-01`, 960 of 960 (point,
  endpoint) picks are identical to `reference/necr/wayback.csv`. Ranking by days from a mid-season
  date reproduces the whole-year banding there.
- **Chips:** 20 chips re-fetched on floodplains' Voronoi cells all land on the same grid, with at least
  99.998% of cells identical and a largest band difference of 1.
- **Cost:** about 40-50 min for 480 points over 197 releases, all of it network time (the service
  slowed from about 2.6 s to about 30 s per release mid-run). Over the BULK floodplain's 21,701 change
  patches, captures cost about 19 s per release once the metadata is cached.

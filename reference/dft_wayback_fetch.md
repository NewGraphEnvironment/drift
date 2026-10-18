# Fetch an Esri Wayback release as a local raster around an AOI

Reads one Wayback release's tiles at one zoom over `aoi` and returns a
three-band (red, green, blue) 8-bit raster, cached as a COG. Take the
`release_id` and `zoom` from
[`dft_wayback_pick()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_pick.md),
so the raster shows the capture you chose.

## Usage

``` r
dft_wayback_fetch(
  aoi,
  release,
  zoom,
  crs = NULL,
  res = NULL,
  clip = TRUE,
  empty_max = 0.05,
  cache_dir = NULL,
  force = FALSE
)
```

## Arguments

- aoi:

  An `sf`, `sfc` or
  [`terra::SpatVector`](https://rspatial.github.io/terra/reference/SpatVector-class.html)
  of polygons. Several features are fetched as their union.

- release:

  A Wayback `release_id` (from
  [`dft_wayback_releases()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_releases.md)
  or
  [`dft_wayback_pick()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_pick.md)).

- zoom:

  One tile zoom level in 10 to 22, normally the `zoom` that
  [`dft_wayback_pick()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_pick.md)
  returns with the release.

- crs:

  Output CRS (e.g. `"EPSG:3005"`). When `NULL`, the UTM zone of the AOI
  centroid.

- res:

  Output cell size in CRS units. When `NULL`, the tiles' own ground
  resolution at the AOI's latitude (Web Mercator pixels shrink by the
  cosine of the latitude), rounded to 0.05 m: zoom 17 is 0.70 m at 54
  degrees north. Required for a geographic `crs`.

- clip:

  Logical. Set cells whose centre is outside `aoi` to nodata (default
  `TRUE`). `FALSE` keeps the whole bounding box.

- empty_max:

  Numeric in 0 to 1. The largest share of the AOI's cells that may come
  back empty before the call aborts (default 0.05).

- cache_dir:

  Character. Cache directory. When `NULL`, uses
  [`dft_cache_path()`](https://www.newgraphenvironment.com/drift/reference/dft_cache_path.md).

- force:

  Logical. Re-build the raster even if cached (default `FALSE`).

## Value

A
[terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with layers `red`, `green`, `blue` (INT1U, nodata 0), backed by the
cached COG.

## Details

GDAL reads the tiles. It follows the redirect a release answers with for
a tile it shares with an older release, which QGIS does not
(qgis/QGIS#54161), so a cached local raster is also the way to draw a
Wayback capture in QGIS. Tiles are always read at `zoom` itself, never
from a shallower level GDAL would otherwise substitute for a coarse
`res`, since a shallower level can show another capture.

The finished raster is cached; the tiles are not. GDAL's own tile cache
turns every missing (404) tile into a pair of read errors (measured on
GDAL 3.13.0), and a fetch that treats GDAL errors as failures cannot
tell those from a real one. A cache hit downloads nothing; a new grid
re-downloads.

**Empty tiles.** A tile the release does not have (HTTP 404) reads as
zeros. A pixel that is zero in all three bands is treated as empty and
becomes nodata, and the call aborts (class `drift_wayback_empty`) when
more than `empty_max` of the AOI is empty: the release has no imagery at
that zoom there. A FLAT area is not empty: open water is flat. Elsewhere
a band value of 0 is raised to 1, because 0 is the nodata value.

**Per point, one call each.** For chips around sample points, buffer
each point and call once per buffered point, as for
[`dft_stac_composite()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_composite.md);
each chip is cached separately. Points themselves are refused. With
`clip = TRUE` a cell belongs to the AOI when its centre does, so AOIs
that tile the ground without overlap, such as Voronoi cells around the
points, produce chips that share no cell. A VRT over such chips then
shows each point's own capture at the point: it composites over nodata,
which is why these are nodata-masked and not alpha-masked.

**Mosaics need one grid.** The default `crs` is the UTM zone of the AOI
and the default `res` follows its latitude, so chips spread over a large
area can differ in both. Pass the same `crs` and `res` to every call
whose outputs will be mosaicked.

A polygon's fetch shows whatever the release draws there, which can be
several captures (see `cover` in
[`dft_wayback_captures()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_captures.md)).

## See also

[`dft_wayback_captures()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_captures.md),
[`dft_wayback_pick()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_pick.md),
[`dft_map_interactive()`](https://www.newgraphenvironment.com/drift/reference/dft_map_interactive.md)
(`rgb =`) to display it.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
pts <- sf::st_as_sf(sf::st_sample(aoi, 5, type = "regular"))
cap <- dft_wayback_captures(pts)
pick <- dft_wayback_pick(cap, as.Date("2017-07-01"))

# One chip per point, +/-150 m, on one grid so they can be mosaicked
buf <- sf::st_buffer(pts, 150, endCapStyle = "SQUARE")
chips <- lapply(seq_len(nrow(pick)), function(i) {
  dft_wayback_fetch(buf[pick$feature[i], ], pick$release_id[i], pick$zoom[i],
                    crs = "EPSG:3005", res = 0.7)
})
terra::plotRGB(chips[[1]])
} # }
```

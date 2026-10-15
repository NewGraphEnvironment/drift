# Find the Esri Wayback captures that image each feature

For every feature of `aoi` and every Wayback release, reads the
release's capture metadata and returns the capture (acquisition date,
resolution, sensor) the release's tiles show there. A release date is
not a capture date (see
[`dft_wayback_releases()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_releases.md)),
so this is the table to choose imagery from: pass it to
[`dft_wayback_pick()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_pick.md)
for the capture nearest a date, then fetch it with
[`dft_wayback_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_fetch.md).

## Usage

``` r
dft_wayback_captures(
  aoi,
  zoom = 17:19,
  releases = NULL,
  cache_dir = NULL,
  force = FALSE
)
```

## Arguments

- aoi:

  An `sf`, `sfc` or
  [`terra::SpatVector`](https://rspatial.github.io/terra/reference/SpatVector-class.html)
  of `POINT`, `POLYGON` or `MULTIPOLYGON` features, in any CRS.

- zoom:

  Integer vector of tile zoom levels, each in 10 to 22 (default `17:19`;
  zoom 17 is about 0.7 m on the ground at 54 degrees north). Zoom 10
  stands for every zoom at or below 10. The metadata describes zoom 23
  too, but GDAL cannot open the tile service there (the world is 2^31
  pixels wide, one past its limit), so a capture at 23 could not be
  fetched.

- releases:

  A release table from
  [`dft_wayback_releases()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_releases.md),
  possibly filtered, to search only some releases. When `NULL`, every
  release.

- cache_dir:

  Character. Cache directory. When `NULL`, uses
  [`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md).

- force:

  Logical. Re-read the metadata even if cached (default `FALSE`).

## Value

A tibble with one row per (feature, release, capture): `feature` (the
row of `aoi`), `release_id`, `release_date`, `capture_date` (Date),
`res_m` (the source's resolution in metres), `source` (provider and
sensor, e.g. `"Maxar WV02"`), `zoom` and `cover`. Sorted by feature,
release date and capture date. Zero rows, with a warning, when no
capture covers any feature.

## Details

Each release's metadata service has one layer per scale band, and layer
`L` describes the tiles at zoom `23 - L`. That mapping is handled here:
pass the tile `zoom` levels you would fetch at. For each feature and
release one zoom is kept, and the `zoom` column is the zoom to fetch at:
the **deepest** zoom whose footprints cover the whole feature, since its
tiles are the sharpest that leave no hole. Where no zoom covers a
polygon whole, the zoom covering most of it is kept. For a point this is
simply the deepest zoom that covers it.

Footprints overlap, and the tiles draw the one with the highest
`DrawOrder` on top (then the finer source). **Points and polygons are
answered differently:**

- A point gets the one capture drawn on top at it. `cover` is 1.

- A polygon can show several captures in one release. Every distinct
  capture visible over it is returned, with `cover` the share of the
  polygon's area where that capture is the one drawn on top. A capture
  wholly hidden under another earns no row, and the covers of one
  release sum to at most 1 (less where a base layer or no imagery
  shows).
  [`dft_wayback_pick()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_pick.md)
  prefers the larger cover only among captures equally near the date, so
  filter on it first (for example `cover >= 0.5`) when a capture must
  image most of a patch. A fetch over a polygon is a mosaic of whatever
  its release shows there, not one capture.

A footprint with no capture date is a base layer, not a capture, and
yields no row. A feature that no capture covers is absent from the
result.

One metadata query is made per release and zoom over the bounding box of
all of `aoi` (paged), not one per feature. Responses are cached under
[`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md);
a past release's metadata does not change, so only `force = TRUE`
re-reads them. A new query bounding box (a grown or moved `aoi`) is a
new cache entry.

## See also

[`dft_wayback_pick()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_pick.md),
[`dft_wayback_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_fetch.md).

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
pts <- sf::st_as_sf(sf::st_sample(aoi, 10, type = "regular"))

# Every capture over the points, in releases from 2017 on
rel <- dft_wayback_releases()
cap <- dft_wayback_captures(pts, releases = rel[rel$release_date >= "2017-01-01", ])
table(format(cap$capture_date, "%Y"))

# The capture nearest mid-July 2017 at each point
dft_wayback_pick(cap, as.Date("2017-07-01"))
} # }
```

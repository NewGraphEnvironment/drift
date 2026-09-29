# Fetch dated, cloud-masked reflectance composites from a STAC catalog

Reference imagery for windows you choose. For each year, streams every
scene in the chosen calendar months, masks clouds per pixel, and reduces
them to one median composite of the requested bands. A true-colour
composite of the same season in different years, or of early against
late season within one year, says **when** a place changed. The Esri and
Google basemaps in
[`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md)
carry no capture date, so they cannot.

## Usage

``` r
dft_stac_composite(
  aoi,
  years,
  months = 6:7,
  bands = c("red", "green", "blue"),
  source = "sentinel-2-l2a",
  res = 10,
  crs = NULL,
  aggregation = "median",
  resampling = "bilinear",
  clip = FALSE,
  cloud_cover_max = 20,
  mask_values = NULL,
  tile_size = NULL,
  parallel = NULL,
  cache_dir = NULL,
  force = FALSE,
  sign_fn = rstac::sign_planetary_computer()
)
```

## Arguments

- aoi:

  An `sf` polygon defining the area of interest. A multi-feature `aoi`
  is read as its union; for sample points, see the chips section.

- years:

  Integer vector of years. One composite is returned per year.

- months:

  Integer vector of calendar months (1-12) to composite (default `6:7`,
  June and July). Each year's window runs from the first day of the
  earliest month to the last day of the latest; scenes from months not
  listed are dropped, so `c(6, 8)` composites June and August and skips
  July.

- bands:

  Character vector of band **roles** from
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  (default `c("red", "green", "blue")`, true colour). Any roles and any
  number of them; `c("nir", "red", "green")` is the standard vegetation
  false colour. Layers are named by role, in the order given.

- source:

  Character. A cube source name for
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  (default `"sentinel-2-l2a"`).

- res:

  Numeric. Output pixel size in CRS units (default 10).

- crs:

  Character. Target CRS as an EPSG string. When `NULL`, auto-detected
  from the AOI centroid's UTM zone.

- aggregation:

  Character. How scenes within a window are reduced (default
  `"median"`).

- resampling:

  Character. Spatial resampling (default `"bilinear"`).

- clip:

  Logical. Clip the output to the AOI polygon (default `FALSE`).
  Reference imagery is read around a place, not only inside it, so the
  default keeps the whole AOI bounding box. `TRUE` uses the same rule as
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md):
  every cell the polygon touches is kept.

- cloud_cover_max:

  Numeric. Scene-level `eo:cloud_cover` maximum percent (default 20,
  stricter than the cube's 60 because a composite of few clear scenes
  looks better than one of many cloudy ones).

- mask_values:

  Integer vector of mask-band classes to exclude. When `NULL`, taken
  from
  [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md).

- tile_size:

  Numeric or `NULL` (default). Read-tiling edge length in CRS units;
  only tiles intersecting the AOI are streamed. A memory knob, not a
  speed one; see
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md).

- parallel:

  Integer or `NULL`. gdalcubes worker processes; see
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md).

- cache_dir:

  Character. Cache directory. When `NULL`, uses
  [`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md).

- force:

  Logical. Re-fetch even if cached (default `FALSE`). The replacement is
  atomic.

- sign_fn:

  A signing function for STAC assets. Default is
  [`rstac::sign_planetary_computer()`](https://brazil-data-cube.github.io/rstac/reference/items_sign_planetary_computer.html).

## Value

A named list of
[terra::SpatRaster](https://rspatial.github.io/terra/reference/SpatRaster-class.html)s,
one per year, each with one layer per band. Names label the window, e.g.
`"2017 Jun–Jul"`, and become layer labels in
[`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md).
Each raster's
[`terra::time()`](https://rspatial.github.io/terra/reference/time.html)
is the window start. A year with no usable scenes is dropped with a
warning; if every year is empty, the call aborts.

## Details

This is the multi-band sibling of
[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
and shares its read path: the same STAC query (paginated, `intersects`
the AOI, scene-level `eo:cloud_cover` pre-filter), the same per-pixel
mask, the same Sentinel-2 offset correction at the 2022-01-25
processing-baseline boundary, the same tiling and the same AOI clip.
Where the cube returns one index per month, this returns the bands
themselves, one time step per window.

Values are **surface reflectance** (the source's `scale` and `offset`
applied), stored as floating point rather than display bytes. That keeps
a composite usable as data, for an index or as classifier input, and
leaves contrast stretching to display time.
[`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md)
applies one shared stretch to every composite it is given, so a
brightness difference between years is a real one.

## Caching

Each year's composite is written once under
[`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md)
as `<source>/composite_<key>.tif`, a Cloud Optimized GeoTIFF. The key
hashes the AOI geometry and every parameter that changes the pixels:
bands (in order), months, the year's window, resolution, CRS,
aggregation, resampling, cloud cover, mask values, reflectance scale and
offset, `clip` and `tile_size`. Because the file is a COG, it can be
copied to object storage and served through titiler unchanged, which is
how a floodplain-wide composite reaches
[`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md):
`rgb` accepts COG URLs as well as rasters.

## Floodplain scale and per-point chips

A composite over a whole floodplain streams the floodplain's bounding
box and produces a raster the size of it. When the purpose is reviewing
sample points, call this **once per buffered point** instead (see the
examples). Each chip is small, streams only the COG blocks under it, and
is cached on its own, so adding a point to the sample fetches one chip
rather than invalidating the rest. Passing all the points as one
multi-feature `aoi` does not do this: the output spans the points'
combined bounding box, and one cache entry covers every point.

## Windows and the Sentinel-2 offset boundary

A window is one calendar year's run of `months`, so a winter window that
crosses the new year (December to February) cannot be expressed;
`c(12, 1, 2)` composites January, February and December of the **same**
year, and the label says so. Sentinel-2 changed its reflectance offset
on 2022-01-25. A window with scenes on both sides of that date cannot be
reduced to one true median, because gdalcubes aggregates before the
per-side offset is applied, so such a window is refused rather than
returned as something that is not a median. Only a January 2022 window
can straddle it.

## See also

[`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md)
(`rgb =`) to display them,
[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
for index time series.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))

# True colour, same season in two years
tc <- dft_stac_composite(aoi, years = c(2017, 2023), months = 6:7)
names(tc)
terra::plotRGB(tc[[1]], stretch = "lin")

# Vegetation false colour, late season
fc <- dft_stac_composite(aoi, years = 2023, months = 8:9,
                         bands = c("nir", "red", "green"))

# Chips around sample points: one small, separately cached composite each
pts <- sf::st_as_sf(sf::st_sample(aoi, 20))
buf <- sf::st_buffer(pts, 300)
chips <- lapply(seq_len(nrow(buf)), function(i) {
  dft_stac_composite(buf[i, ], years = c(2017, 2023))
})

dft_map_interactive(rgb = c(tc, fc[1]), aoi = aoi)
} # }
```

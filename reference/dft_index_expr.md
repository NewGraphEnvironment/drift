# Apply a spectral index to a data cube

Resolve a named spectral index (e.g. `"kndvi"`) into a per-pixel
arithmetic expression over a source's band roles and apply it to a
`gdalcubes` data cube, returning a single-band cube named after the
index.

## Usage

``` r
dft_index_expr(
  cube,
  index = "kndvi",
  source = "sentinel-2-l2a",
  roles = NULL,
  scale = NULL,
  offset = NULL
)
```

## Arguments

- cube:

  A `gdalcubes` data cube (e.g. the lazy cube built inside
  [`dft_stac_cube()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_cube.md))
  whose bands are the source's assets.

- index:

  Character. An index name present in
  [`dft_index_table()`](https://www.newgraphenvironment.com/drift/reference/dft_index_table.md)
  (default `"kndvi"`).

- source:

  Character. Source name passed to
  [`dft_stac_config()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_config.md)
  to resolve the role→asset map and reflectance scale/offset (default
  `"sentinel-2-l2a"`).

- roles:

  Named list mapping roles to asset names. When `NULL`, taken from
  `dft_stac_config(source)$roles`.

- scale, offset:

  Numeric reflectance affine transform. When `NULL`, taken from the
  source config (falling back to `1` / `0`).

## Value

A single-band `gdalcubes` cube with the band named `index`.

## Details

Index formulas are stored in a shipped registry
([`dft_index_table()`](https://www.newgraphenvironment.com/drift/reference/dft_index_table.md))
written over band **roles** (`red`, `green`, `blue`, `nir`, `swir16`),
not literal asset names. The roles are resolved to per-source asset
names via
[`dft_stac_config()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_config.md),
so the same `"kndvi"` works against Sentinel-2 (`B04`/`B08`) and MODIS
(`250m_16_days_red_reflectance`/`..._NIR_...`) without changing the
formula. A band whose asset name is not a valid expression identifier
(the MODIS names start with a digit) is renamed to its role in the cube
before the expression is applied.

Reflectance `scale`/`offset` are folded **into** the expression as a
per-band affine transform `(asset * scale + offset)`. This matters for
ratio indices: a non-zero offset does not cancel in
`(nir - red)/(nir + red)`, so computing NDVI on raw digital numbers is
wrong for sources with an offset (Landsat C2 L2, or Sentinel-2
processing baseline 04.00).

## See also

[`dft_index_table()`](https://www.newgraphenvironment.com/drift/reference/dft_index_table.md)
for the registry,
[`dft_stac_cube()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_cube.md)
for the caller that builds the input cube.

## Examples

``` r
# The registry the resolver reads:
dft_index_table()
#> # A tibble: 6 × 4
#>   index formula                                              roles   description
#>   <chr> <chr>                                                <chr>   <chr>      
#> 1 ndvi  (nir - red) / (nir + red)                            nir,red Normalized…
#> 2 kndvi tanh(pow((nir - red) / (nir + red), 2))              nir,red Kernel NDV…
#> 3 ndmi  (nir - swir16) / (nir + swir16)                      nir,sw… Normalized…
#> 4 ndwi  (green - nir) / (green + nir)                        green,… Normalized…
#> 5 mndwi (green - swir16) / (green + swir16)                  green,… Modified N…
#> 6 evi   2.5 * (nir - red) / (nir + 6 * red - 7.5 * blue + 1) nir,re… Enhanced V…

if (FALSE) { # \dontrun{
# Applied to a lazy Sentinel-2 cube (requires network + gdalcubes):
aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
cube <- dft_stac_cube(aoi, index = "kndvi")  # dft_stac_cube calls this internally
} # }
```

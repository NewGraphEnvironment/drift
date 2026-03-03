# Extract class table from STAC item metadata

Parses the `classification:classes` extension from STAC item properties
to build a class lookup table with codes, names, and colors.

## Usage

``` r
dft_stac_classes(items = NULL, source = "io-lulc")
```

## Arguments

- items:

  An `rstac` items collection returned by
  [`rstac::get_request()`](https://brazil-data-cube.github.io/rstac/reference/request.html)
  or
  [`rstac::items_sign()`](https://brazil-data-cube.github.io/rstac/reference/items_functions.html).
  Uses the first item's properties.

- source:

  Character. Source name for CSV fallback lookup. One of `"io-lulc"` or
  `"esa-worldcover"`. Only used when STAC metadata lacks classification
  info.

## Value

A tibble with columns `code` (integer), `class_name` (character),
`color` (character, hex), and `description` (character, may be NA).

## Details

Falls back to a shipped CSV if STAC metadata is missing or incomplete.

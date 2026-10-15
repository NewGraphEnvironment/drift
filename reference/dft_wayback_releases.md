# List the Esri World Imagery Wayback releases

Reads Esri's Wayback configuration, which lists every archived release
of the World Imagery basemap, and returns one row per release, sorted by
date.

## Usage

``` r
dft_wayback_releases()
```

## Value

A tibble with one row per release: `release_id` (character, the tile
service's release number), `release_date` (Date) and `meta_url` (the
release's capture-metadata MapServer). Sorted by `release_date`.

## Details

**A release date is not a capture date.** A release is the World Imagery
mosaic as published on that date, and it mosaics captures of many years:
over the Neexdzii Kwa floodplain the 2017-11-16 release serves
WorldView-2 captures from 2013 and 2016. The release date bounds the
capture from above and says nothing more. To find the capture a feature
was actually imaged at, use
[`dft_wayback_captures()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_captures.md),
which reads each release's capture metadata.

Release ids are not ordered by date, so sort or filter on
`release_date`, never on `release_id`.

## See also

[`dft_wayback_captures()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_captures.md),
[`dft_wayback_pick()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_pick.md),
[`dft_wayback_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_wayback_fetch.md).

## Examples

``` r
if (FALSE) { # \dontrun{
rel <- dft_wayback_releases()
nrow(rel)
range(rel$release_date)

# Only the releases from 2020 on, to query fewer of them
rel_recent <- rel[rel$release_date >= as.Date("2020-01-01"), ]
} # }
```

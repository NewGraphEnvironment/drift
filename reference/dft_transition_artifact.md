# Tag transition patches with geometric misregistration evidence

Year-to-year classified land cover carries geometric artifacts that read
as real transitions but are misalignment: a boundary that moved by a
pixel between epochs leaves a thin band of "change" along one side of
it, and a channel that shifted leaves `Trees -> Water` on one bank and
`Water -> Trees` on the other. Both inflate reported change, and both
concentrate on the long linear boundaries (banks, forest edges, field
margins) that riparian work is about. `patch_area_min` cannot separate
them from real change — a one-pixel band along a 5 km bank is 15 ha —
because area is width times length and the artifact is pathological in
*width*.

## Usage

``` r
dft_transition_artifact(
  patches,
  transition,
  width_max = 1.5,
  boundary_dist_max = 1,
  reciprocal = TRUE,
  reciprocal_dist_max = 5,
  reciprocal_area_ratio_min = 0.5
)
```

## Arguments

- patches:

  An `sf` object of transition patches from
  [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md),
  with columns `patch_id` (unique), `transition` and `area_ha`. Run this
  **before** zone attribution or
  [`dft_transition_attribute()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_attribute.md)
  with `match_mode = "all"`: zone intersection splits patch geometry and
  `"all"` mode duplicates `patch_id`, and both change what "a patch"
  means to the metrics below.

- transition:

  The factor `SpatRaster` the patches were vectorized from (the
  `$raster` element of
  [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)).
  Must be the **unfiltered** raster — one produced without `from_class`
  / `to_class` — because the boundary signature reads the from-epoch
  class of the cells *around* each patch, and a filtered raster is `NA`
  there.

- width_max:

  Numeric, in pixels. A patch whose effective width
  `2 * area / perimeter` is below this is flagged as a sliver. The
  default `1.5` catches a one-pixel band (0.5–1 px by this metric) and
  clears a two-pixel-wide strip.

- boundary_dist_max:

  Positive whole number, in pixels. A patch cell counts as
  boundary-hugging when a from-epoch cell of the patch's *to* class lies
  within this many cells of it (a square window). `1` means 8-neighbour
  adjacency.

- reciprocal:

  Logical. Search for reciprocal partners? `FALSE` skips the pairwise
  step and returns `NA` in the three `reciprocal*` columns, for very
  large patch sets where the search is not wanted.

- reciprocal_dist_max:

  Numeric, in pixels. How far from an `A -> B` patch to look for a
  `B -> A` partner. Opposite-bank bands are separated by the stable
  channel between them, so this must exceed the channel width in pixels;
  the default `5` covers a 50 m river at 10 m.

- reciprocal_area_ratio_min:

  Numeric in `[0, 1]`. A candidate partner must have
  `min(area) / max(area)` at least this large — a compensating shift
  moves about the same area in each direction.

## Value

`patches` with eight columns appended (geometry stays last):

- `width_m`, `width_px` (numeric) — effective width
  `2 * area / perimeter`

- `flag_sliver` (logical) — `width_px < width_max`

- `boundary_frac` (numeric, 0–1) — share of cells within
  `boundary_dist_max` of the from-epoch interface; `NA` for stable
  patches

- `flag_boundary` (logical) — `boundary_frac >= 0.5`; `NA` for stable

- `reciprocal_id` — `patch_id` of the partner, or `NA`

- `reciprocal_dist_m` (numeric) — distance to it (`0` when touching)

- `flag_reciprocal` (logical) — a partner was found; `NA` for stable
  patches or when `reciprocal = FALSE`

## Details

This function adds evidence columns to the patches from
[`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
and lets the caller decide. It drops nothing. Every signature is derived
from the transition raster alone, so it costs no extra fetch and works
on any factor transition raster.

Three signatures, each reported as a measurement plus a flag:

**Sliver width.** Effective width `2 * area / perimeter` — for a
rectangle of sides `a << b` this is close to `a`. On a 10 m grid a
single pixel scores 0.5 px, a 1 x 20 pixel band 0.95 px, a 20 x 20 block
10 px. Width is orthogonal to `patch_area_min`: a 15 ha sliver and a 15
ha clearing are identical on the area axis and ~80x apart on this one.

**Boundary-hugging.** The share of a patch's cells that lie within
`boundary_dist_max` cells of a from-epoch cell of the patch's *to* class
— that is, of the pre-existing interface between the two classes. This
is the disambiguator width alone cannot supply: a registration artifact
*traces* an existing boundary, while a real thin change (a new road, a
harvested buffer strip) *cuts across* one and scores near zero.
`flag_boundary` is `boundary_frac >= 0.5`.

**Reciprocity.** Whether an `A -> B` patch has a `B -> A` partner of
comparable area within `reciprocal_dist_max`. Along a channel that
shifted by a pixel, one bank maps `Water -> Trees` and the other
`Trees -> Water`; the net change is ~zero and the two bands are
separated by the stable channel, so the test is proximity rather than
adjacency. The partner recorded is the nearest one that meets the area
criterion (ties to the larger). This is a geometric relationship between
two patches and is unavailable to any per-pixel method, including the
spectral check.

Stable patches (`A -> A`, present when `changes_only = FALSE`) get the
width columns — those are geometry only — and `NA` for everything else.
`NA` there means *not applicable*, not "checked and clean".

No composed `flag_artifact` is returned: which signatures matter depends
on the AOI, and real changes are sometimes genuinely thin. Compose it
yourself, e.g. `flag_sliver & (flag_boundary | flag_reciprocal)`.

The independent confirmation route is spectral:
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
on a Sentinel-2 index cube, described in the *Trajectories as a Check on
Land-Cover Change* vignette, where a mapped transition with no spectral
break is read as a label change rather than real change. That route
needs a cube and cannot see the reciprocal relationship; this one is
free and categorical-only. They are complements.

## Memory

The boundary signature is computed with streamed `terra` operations —
`segregate` into one layer per distinct *to* class among the change
patches, a single `focal` pass over that stack, `rasterize` + `zonal`
for the per-patch fraction — with every intermediate written to a
temporary file so nothing full-grid is held in memory or pulled into R.
Measured on a 169M-cell floodplain grid (the BULK watershed group at 10
m). The reciprocal search is an `sf` spatial-index query per transition
pair.

## See also

[`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
for producing the input patches and its `patch_area_min` for the area
axis;
[`dft_transition_attribute()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_attribute.md)
to tag patches from an overlay layer once artifacts are flagged;
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
for the spectral confirmation route.

## Examples

``` r
r17 <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
r23 <- terra::rast(system.file("extdata", "example_2023.tif", package = "drift"))
classified <- dft_rast_classify(list("2017" = r17, "2023" = r23), source = "io-lulc")
result <- dft_rast_transition(classified, from = "2017", to = "2023")
patches <- dft_transition_vectors(result$raster, changes_only = TRUE)

tagged <- dft_transition_artifact(patches, result$raster)

# most patches are slivers, but they hold a minority of the change area
table(tagged$flag_sliver)
#> 
#> FALSE  TRUE 
#>    18    75 
tapply(tagged$area_ha, tagged$flag_sliver, sum)
#> FALSE  TRUE 
#> 28.42  5.61 

# a sliver that also traces a pre-existing boundary is the artifact shape;
# compose the verdict yourself and keep the evidence
tagged$flag_artifact <- tagged$flag_sliver &
  (tagged$flag_boundary | tagged$flag_reciprocal)
head(sf::st_drop_geometry(tagged[tagged$flag_artifact, ]))
#>    patch_id              transition area_ha  width_m width_px flag_sliver
#> 1         1      Trees -> Rangeland    0.41 10.78947 1.078947        TRUE
#> 2         2      Rangeland -> Trees    0.01  5.00000 0.500000        TRUE
#> 3         3      Trees -> Rangeland    0.01  5.00000 0.500000        TRUE
#> 4         4      Trees -> Rangeland    0.01  5.00000 0.500000        TRUE
#> 10       10      Trees -> Rangeland    0.01  5.00000 0.500000        TRUE
#> 11       11 Built Area -> Rangeland    0.08 10.00000 1.000000        TRUE
#>    boundary_frac flag_boundary reciprocal_id reciprocal_dist_m flag_reciprocal
#> 1      0.8536585          TRUE            NA                NA           FALSE
#> 2      1.0000000          TRUE             3                30            TRUE
#> 3      1.0000000          TRUE             2                30            TRUE
#> 4      1.0000000          TRUE            NA                NA           FALSE
#> 10     1.0000000          TRUE            NA                NA           FALSE
#> 11     0.7500000          TRUE            NA                NA           FALSE
#>    flag_artifact
#> 1           TRUE
#> 2           TRUE
#> 3           TRUE
#> 4           TRUE
#> 10          TRUE
#> 11          TRUE

# the sliver that walks through patch_area_min = 5000 (0.75 ha, 1.4 px wide)
large <- dft_transition_vectors(result$raster, changes_only = TRUE,
                                patch_area_min = 5000)
large <- dft_transition_artifact(large, result$raster)
sf::st_drop_geometry(large[large$flag_sliver, ])
#>   patch_id         transition area_ha  width_m width_px flag_sliver
#> 6        6 Trees -> Rangeland    0.75 14.42308 1.442308        TRUE
#>   boundary_frac flag_boundary reciprocal_id reciprocal_dist_m flag_reciprocal
#> 6     0.7066667          TRUE            NA                NA           FALSE
```

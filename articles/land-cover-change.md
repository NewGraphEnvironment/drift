# Land Cover Change Detection for Floodplains

This vignette demonstrates the drift pipeline using a small floodplain
reach on Neexdzii Kwa (Upper Bulkley River) in northern BC. We compare
Esri IO LULC land cover across 2017, 2020, and 2023 to track vegetation
and land use change in the riparian zone.

The AOI polygon was delineated using the
[flooded](https://github.com/NewGraphEnvironment/flooded) package, which
identifies floodplain extents from DEMs and stream networks.

The example data ships with the package — no STAC queries or database
connections needed.

## Load Data

``` r

library(drift)
#> 
#>  'It's feeling confident I'm going to go up with the music, but I'm down every day. It's the challenge of trying to be the best at your worst times.' - Offset
#>   source
library(terra)
#> terra 1.9.46
library(sf)
#> Linking to GEOS 3.12.1, GDAL 3.8.4, PROJ 9.4.0; sf_use_s2() is TRUE

# AOI polygon (floodplain delineated via flooded package)
aoi <- sf::st_read(
  system.file("extdata", "example_aoi.gpkg", package = "drift"),
  quiet = TRUE
)

# IO LULC rasters for 3 years
years <- c(2017, 2020, 2023)
rasters <- lapply(years, function(yr) {
  terra::rast(system.file("extdata", paste0("example_", yr, ".tif"),
                          package = "drift"))
})
names(rasters) <- years
```

## Classify

Apply IO LULC class names and colors from the shipped class table.

``` r

classified <- dft_rast_classify(rasters, source = "io-lulc")

# Check factor levels
terra::levels(classified[["2020"]])[[1]]
#>   id class_name
#> 1  1      Water
#> 2  2      Trees
#> 3  5      Crops
#> 4  7 Built Area
#> 5  9   Snow/Ice
#> 6 11  Rangeland
```

## Classified Rasters

The figure below shows the three classified time steps side by side.

``` r

stacked <- terra::rast(classified)
names(stacked) <- names(classified)
terra::plot(stacked, axes = FALSE, mar = c(1, 1, 2, 1))
```

![Classified land cover for the Neexdzii Kwa floodplain reach across
three time
steps.](land-cover-change_files/figure-html/plot-classified-1.png)

Classified land cover for the Neexdzii Kwa floodplain reach across three
time steps.

## Area Summary

The following table shows area by class for each year and the net change
between 2017 and 2023, sorted by magnitude of change.

``` r

summary_tbl <- dft_rast_summarize(classified, source = "io-lulc", unit = "ha")
```

``` r

library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:terra':
#> 
#>     intersect, union
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
library(tidyr)
#> 
#> Attaching package: 'tidyr'
#> The following object is masked from 'package:terra':
#> 
#>     extract

change <- summary_tbl |>
  dplyr::select(year, class_name, area) |>
  tidyr::pivot_wider(names_from = year, values_from = area, values_fill = list(area = 0)) |>
  dplyr::mutate(
    change = `2023` - `2017`,
    pct_change = round(change / `2017` * 100, 1)
  ) |>
  dplyr::arrange(dplyr::desc(abs(change)))

knitr::kable(change, digits = 2, caption = "Net land cover change 2017--2023 (ha), sorted by absolute change.")
```

| class_name         |  2017 |  2020 |  2023 | change | pct_change |
|:-------------------|------:|------:|------:|-------:|-----------:|
| Rangeland          | 31.86 | 53.38 | 61.67 |  29.81 |       93.6 |
| Trees              | 71.27 | 55.42 | 50.07 | -21.20 |      -29.7 |
| Crops              |  9.98 |  1.47 |  0.00 |  -9.98 |     -100.0 |
| Water              |  9.41 | 10.89 | 11.11 |   1.70 |       18.1 |
| Built Area         |  0.55 |  0.10 |  0.26 |  -0.29 |      -52.7 |
| Flooded Vegetation |  0.02 |  0.00 |  0.00 |  -0.02 |     -100.0 |
| Snow/Ice           |  0.02 |  1.85 |  0.00 |  -0.02 |     -100.0 |

Net land cover change 2017–2023 (ha), sorted by absolute change.
{.table}

## Vegetation Change

Trees and Rangeland show the clearest signal below — tree cover
declining while rangeland expands.

``` r

library(ggplot2)

summary_tbl |>
  dplyr::filter(class_name %in% c("Trees", "Rangeland")) |>
  ggplot(aes(x = year, y = area, fill = year)) +
  geom_col() +
  facet_wrap(~class_name, scales = "free_y") +
  scale_fill_brewer(palette = "YlGnBu") +
  labs(y = "Area (ha)", x = NULL, fill = "Year",
       title = "Vegetation cover in Neexdzii Kwa floodplain") +
  theme_minimal()
```

![Dominant vegetation classes over time in the Neexdzii Kwa
floodplain.](land-cover-change_files/figure-html/plot-vegetation-1.png)

Dominant vegetation classes over time in the Neexdzii Kwa floodplain.

## Transition Detection

[`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
compares two rasters cell-by-cell and returns a transition raster plus a
summary table. The first table below shows the area that remained in the
same class (stable pixels), while the second shows pixels that changed
class. Only transitions representing more than 1% of the total area are
shown.

``` r

result <- dft_rast_transition(classified, from = "2017", to = "2023")

stable <- result$summary |>
  dplyr::filter(from_class == to_class) |>
  dplyr::filter(pct >= 1) |>
  dplyr::arrange(dplyr::desc(area))

changed <- result$summary |>
  dplyr::filter(from_class != to_class) |>
  dplyr::filter(pct >= 1) |>
  dplyr::arrange(dplyr::desc(area))
```

``` r

knitr::kable(stable, digits = 2,
             caption = "Stable land cover 2017--2023 (only transitions >1% of total area shown).")
```

| from_class | to_class  | n_cells |  area |   pct |
|:-----------|:----------|--------:|------:|------:|
| Trees      | Trees     |    4918 | 49.18 | 39.95 |
| Rangeland  | Rangeland |    3026 | 30.26 | 24.58 |
| Water      | Water     |     938 |  9.38 |  7.62 |

Stable land cover 2017–2023 (only transitions \>1% of total area shown).
{.table}

``` r

knitr::kable(changed, digits = 2,
             caption = "Land cover transitions 2017--2023 (only transitions >1% of total area shown).")
```

| from_class | to_class  | n_cells |  area |   pct |
|:-----------|:----------|--------:|------:|------:|
| Trees      | Rangeland |    2111 | 21.11 | 17.15 |
| Crops      | Rangeland |     998 |  9.98 |  8.11 |

Land cover transitions 2017–2023 (only transitions \>1% of total area
shown). {.table}

### Grouping Classes for Domain-Specific Analysis

Fine-grained LULC classes can be grouped into categories relevant to a
specific analysis. Here we demonstrate grouping Crops, Rangeland, and
Bare Ground as “Agriculture” — at 10 m resolution these classes can
represent different phases of the same land use depending on satellite
overpass timing.

The table below shows the area of Trees in 2017 that transitioned to
agriculture-related classes by 2023.

``` r

ag_classes <- c("Crops", "Rangeland", "Bare Ground")

# All transitions from Trees to get total Trees-origin pixel count
all_from_trees <- dft_rast_transition(classified, from = "2017", to = "2023",
                                       from_class = "Trees")
total_tree_cells <- sum(all_from_trees$summary$n_cells)

# Filter to agriculture classes
tree_loss <- dft_rast_transition(classified, from = "2017", to = "2023",
                                  from_class = "Trees",
                                  to_class = ag_classes)

# Relabel as Agriculture and compute pct of all Trees-origin pixels
tree_loss_tbl <- tree_loss$summary |>
  dplyr::mutate(to_class = "Agriculture") |>
  dplyr::group_by(from_class, to_class) |>
  dplyr::summarize(n_cells = sum(n_cells), area = sum(area), .groups = "drop") |>
  dplyr::mutate(pct_of_trees = round(n_cells / total_tree_cells * 100, 2))

knitr::kable(tree_loss_tbl, digits = 2,
             caption = "Tree loss to agriculture (Crops + Rangeland + Bare Ground) 2017--2023. Percent is of all pixels classified as Trees in 2017.")
```

| from_class | to_class    | n_cells |  area | pct_of_trees |
|:-----------|:------------|--------:|------:|-------------:|
| Trees      | Agriculture |    2111 | 21.11 |        29.62 |

Tree loss to agriculture (Crops + Rangeland + Bare Ground) 2017–2023.
Percent is of all pixels classified as Trees in 2017. {.table}

### Transition Raster

The figure below maps pixels that changed class between 2017 and 2023.
Only transitions representing more than 1% of the total area are shown;
minor transitions are masked. The AOI outline is shown in red.

``` r

trans_vals <- terra::values(result$raster)[, 1]
lvls <- terra::cats(result$raster)[[1]]

# Get codes for transitions >= 1% (excluding stable)
sig_labels <- changed$from_class  # already filtered to >1% and from != to
sig_transitions <- paste0(changed$from_class, " -> ", changed$to_class)
sig_codes <- lvls$id[lvls$transition %in% sig_transitions]

# Mask everything except significant transitions
change_vals <- rep(NA_integer_, length(trans_vals))
change_vals[trans_vals %in% sig_codes] <- trans_vals[trans_vals %in% sig_codes]
r_change <- terra::rast(result$raster)
terra::values(r_change) <- change_vals

# Keep only significant factor levels
change_lvls <- lvls[lvls$id %in% sig_codes, , drop = FALSE]
terra::set.cats(r_change, layer = 1, value = change_lvls)

terra::plot(r_change, main = "Land cover transitions 2017\u20132023",
            axes = FALSE, mar = c(1, 1, 2, 6))
plot(sf::st_geometry(sf::st_transform(aoi, terra::crs(r_change))),
     add = TRUE, border = "red", lwd = 2)
```

![Spatial distribution of land cover transitions 2017--2023 (only
transitions \>1% of total area
shown).](land-cover-change_files/figure-html/plot-transition-1.png)

Spatial distribution of land cover transitions 2017–2023 (only
transitions \>1% of total area shown).

## Filtering Classification Noise

At 10 m resolution, many detected transitions are single-pixel or
small-cluster noise from field-forest edge effects, seasonal canopy
variation, or sensor timing differences. The `patch_area_min` parameter
removes connected patches of changed pixels smaller than a threshold (in
m²) before computing the summary.

``` r

patch_min <- 5000
n_pixels <- patch_min / prod(terra::res(classified[[1]]))

result_filtered <- dft_rast_transition(classified, from = "2017", to = "2023",
                                       patch_area_min = patch_min)

changed_filtered <- result_filtered$summary |>
  dplyr::filter(from_class != to_class) |>
  dplyr::filter(pct >= 1) |>
  dplyr::arrange(dplyr::desc(area))

# Comparison table: unfiltered vs filtered
comparison <- changed |>
  dplyr::select(from_class, to_class, n_cells, area) |>
  dplyr::left_join(
    changed_filtered |>
      dplyr::select(from_class, to_class,
                    n_cells_filtered = n_cells, area_filtered = area),
    by = c("from_class", "to_class")
  ) |>
  dplyr::mutate(
    dplyr::across(c(n_cells_filtered, area_filtered), ~tidyr::replace_na(.x, 0)),
    cells_removed = n_cells - n_cells_filtered,
    area_removed = area - area_filtered
  )
```

Filtering at 5,000 m² (50 pixels at 10 m resolution) removed 481 pixels
(4.81 ha) of small isolated changes. The table below compares unfiltered
and filtered results.

``` r

knitr::kable(comparison, digits = 2, col.names = c(
  "From", "To", "Cells", "Area (ha)", "Cells (filtered)",
  "Area (filtered)", "Cells removed", "Area removed"
), caption = paste0(
  "Land cover transitions 2017--2023: unfiltered vs filtered (min patch area ",
  format(patch_min, big.mark = ","), " m\u00b2)."))
```

| From | To | Cells | Area (ha) | Cells (filtered) | Area (filtered) | Cells removed | Area removed |
|:---|:---|---:|---:|---:|---:|---:|---:|
| Trees | Rangeland | 2111 | 21.11 | 1632 | 16.32 | 479 | 4.79 |
| Crops | Rangeland | 998 | 9.98 | 996 | 9.96 | 2 | 0.02 |

Land cover transitions 2017–2023: unfiltered vs filtered (min patch area
5,000 m²). {.table style="width:100%;"}

The figure below shows three views: unfiltered transitions, what the
filter removed (`$removed`), and the filtered result. The `$removed`
raster is returned directly by
[`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
when `patch_area_min` is set.

``` r

aoi_proj <- sf::st_geometry(sf::st_transform(aoi, terra::crs(r_change)))

par(mfrow = c(1, 3))
terra::plot(r_change, main = "Unfiltered", axes = FALSE, mar = c(1, 1, 2, 6))
plot(aoi_proj, add = TRUE, border = "red", lwd = 2)
terra::plot(result_filtered$removed, main = "Removed patches", axes = FALSE,
            mar = c(1, 1, 2, 6))
plot(aoi_proj, add = TRUE, border = "red", lwd = 2)
terra::plot(result_filtered$raster, main = paste0("Filtered (min ",
            format(patch_min, big.mark = ","), " m\u00b2)"),
            axes = FALSE, mar = c(1, 1, 2, 6))
plot(aoi_proj, add = TRUE, border = "red", lwd = 2)
```

![Transition raster before and after minimum patch area filtering (5,000
m²). Centre panel shows removed
patches.](land-cover-change_files/figure-html/plot-patch-filter-1.png)

Transition raster before and after minimum patch area filtering (5,000
m²). Centre panel shows removed patches.

## Vector Patches

[`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
converts the transition raster into `sf` polygons — one row per
connected patch. This is the format needed for GIS QA (click patches,
filter by size) and spatial attribution to management zones.

``` r

patches <- dft_transition_vectors(result$raster)

# Only actual changes (exclude same-class "transitions")
patches_changed <- patches[grepl("->", patches$transition) &
  !sapply(strsplit(patches$transition, " -> "), \(x) x[1] == x[2]), ]

knitr::kable(
  head(sf::st_drop_geometry(patches_changed[order(-patches_changed$area_ha), ]), 10),
  digits = 2,
  caption = "Ten largest change patches (same-class transitions excluded)."
)
```

|     | patch_id | transition          | area_ha |
|:----|---------:|:--------------------|--------:|
| 35  |       35 | Crops -\> Rangeland |    9.96 |
| 139 |      139 | Trees -\> Rangeland |    7.99 |
| 55  |       55 | Trees -\> Rangeland |    2.41 |
| 129 |      129 | Trees -\> Rangeland |    1.51 |
| 27  |       27 | Trees -\> Rangeland |    0.94 |
| 130 |      130 | Trees -\> Rangeland |    0.81 |
| 109 |      109 | Trees -\> Rangeland |    0.75 |
| 9   |        9 | Trees -\> Rangeland |    0.70 |
| 38  |       38 | Trees -\> Water     |    0.55 |
| 164 |      164 | Trees -\> Rangeland |    0.53 |

Ten largest change patches (same-class transitions excluded). {.table}

When `zones` is supplied, each patch is intersected with the zone
polygons. Here we use the floodplain AOI as a single zone — in practice
this would be sub-basins, parcels, or management units.

``` r

aoi$zone <- "Neexdzii Kwa floodplain"
patches_zoned <- dft_transition_vectors(result$raster, zones = aoi,
                                        zone_col = "zone")
cat("Patches inside AOI:", nrow(patches_zoned), "of", nrow(patches), "total\n")
#> Patches inside AOI: 165 of 165 total
```

## Geometric Artifacts

`patch_area_min` is a one-dimensional test on a two-dimensional problem.
Area is width times length, and the classification artifacts that
inflate change on a floodplain are pathological in *width*: a class
boundary that moved by one pixel between epochs leaves a one-pixel band
of “change” along its whole length, and a channel that shifted leaves
`Trees -> Water` on one bank and `Water -> Trees` on the other. A
one-pixel band along a 5 km bank at 30 m is 15 ha — thirty times the
5,000 m² threshold used above — while a genuine 0.5 ha cutblock is
discarded as speckle. No value of `patch_area_min` fixes both.

[`dft_transition_artifact()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_artifact.md)
adds evidence for three geometric signatures to the patches from
[`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
and drops nothing — the caller decides. All three are read from the
transition raster alone, so they cost no extra fetch.

``` r

changes <- dft_transition_vectors(result$raster, changes_only = TRUE)
tagged <- dft_transition_artifact(changes, result$raster)

by_sliver <- sf::st_drop_geometry(tagged) |>
  dplyr::mutate(width = ifelse(flag_sliver, "Under 1.5 px", "1.5 px or wider")) |>
  dplyr::group_by(width) |>
  dplyr::summarise(n_patches = dplyr::n(), area_ha = sum(area_ha), .groups = "drop") |>
  dplyr::mutate(pct_patches = 100 * n_patches / sum(n_patches),
                pct_area = 100 * area_ha / sum(area_ha))

knitr::kable(by_sliver, digits = 1, col.names = c(
  "Effective width", "Patches", "Area (ha)", "% of patches", "% of area"
), caption = "Change patches 2017--2023 by effective width (2 x area / perimeter).")
```

| Effective width | Patches | Area (ha) | % of patches | % of area |
|:----------------|--------:|----------:|-------------:|----------:|
| 1.5 px or wider |      18 |      28.4 |         19.4 |      83.5 |
| Under 1.5 px    |      75 |       5.6 |         80.6 |      16.5 |

Change patches 2017–2023 by effective width (2 x area / perimeter).
{.table}

**Sliver width.** Effective width `2 * area / perimeter` is about the
short side of a thin rectangle: a single pixel scores 0.5 px, a
one-pixel band just under 1 px, a 20 x 20 block 10 px. On this reach 75
of 93 change patches are under 1.5 px wide, but they hold only 16% of
the change area — many patches, little ground.

**Boundary-hugging.** Width alone cannot tell a misregistration band
from a new road or a harvested buffer strip, which are also thin. The
discriminator is *where* the thin patch sits: a registration artifact
traces a boundary that already existed in the earlier epoch, while a
real thin change cuts across one. `boundary_frac` is the share of a
patch’s cells adjacent (within `boundary_dist_max` cells) to a
from-epoch cell of the patch’s *to* class. Here 48 of the 75 slivers
trace a pre-existing boundary; the other 27 do not, and deserve a look
before being dismissed.

**Reciprocity.** An `A -> B` patch with a `B -> A` partner of comparable
area nearby is the channel-shift signature — the net change is close to
zero. The two bands sit on opposite banks with the stable channel
between them, so the search is by proximity (`reciprocal_dist_max`, in
pixels) rather than adjacency. This is a relationship between two
patches, which no per-pixel test can express. 5 patches here have a
partner.

``` r

tagged$evidence <- dplyr::case_when(
  tagged$flag_sliver & tagged$flag_reciprocal ~ "Sliver, reciprocal partner",
  tagged$flag_sliver & tagged$flag_boundary ~ "Sliver on a pre-existing boundary",
  tagged$flag_sliver ~ "Sliver, crosses classes",
  TRUE ~ "1.5 px or wider"
)
pal <- c(
  "Sliver on a pre-existing boundary" = "#d7301f",
  "Sliver, reciprocal partner" = "#7b3294",
  "Sliver, crosses classes" = "#fdae61",
  "1.5 px or wider" = "#9e9e9e"
)
par(mar = c(0, 0, 0, 0))
plot(sf::st_geometry(tagged), col = pal[tagged$evidence],
     border = pal[tagged$evidence], lwd = 2)
plot(aoi_proj, add = TRUE, border = "black", lwd = 1)
legend("topleft", fill = pal, legend = names(pal), bty = "n", cex = 0.8)
```

![Change patches 2017--2023 by artifact evidence. Slivers on a
pre-existing boundary (red) are the misregistration shape; slivers that
cross class boundaries (orange) are thin but not explained by a shift;
patches with a reciprocal partner (purple) are the channel-shift
shape.](land-cover-change_files/figure-html/plot-artifact-1.png)

Change patches 2017–2023 by artifact evidence. Slivers on a pre-existing
boundary (red) are the misregistration shape; slivers that cross class
boundaries (orange) are thin but not explained by a shift; patches with
a reciprocal partner (purple) are the channel-shift shape.

The two axes compose. Below are the change patches that survive the
5,000 m² area filter used above, with their artifact evidence: one of
them is a `Trees -> Rangeland` band 0.75 ha in area and under 1.5 px
wide that traces the 2017 forest edge — exactly the patch the area
filter exists to remove, walking through it on length alone. With width
and boundary evidence in hand, `patch_area_min` can be lowered to
recover small real changes without readmitting the slivers.

``` r

large <- dft_transition_vectors(result$raster, changes_only = TRUE,
                                patch_area_min = patch_min)
large <- dft_transition_artifact(large, result$raster)

knitr::kable(
  sf::st_drop_geometry(large)[, c("patch_id", "transition", "area_ha", "width_px",
                                  "boundary_frac", "flag_sliver", "flag_boundary")],
  digits = 2,
  col.names = c("Patch", "Transition", "Area (ha)", "Width (px)",
                "Boundary frac.", "Sliver", "On boundary"),
  caption = paste0("Change patches surviving patch_area_min = ",
                   format(patch_min, big.mark = ","), " m\u00b2, with artifact evidence.")
)
```

| Patch | Transition | Area (ha) | Width (px) | Boundary frac. | Sliver | On boundary |
|---:|:---|---:|---:|---:|:---|:---|
| 1 | Trees -\> Rangeland | 0.70 | 2.41 | 0.10 | FALSE | FALSE |
| 2 | Trees -\> Rangeland | 0.94 | 2.35 | 0.00 | FALSE | FALSE |
| 3 | Crops -\> Rangeland | 9.96 | 6.78 | 0.01 | FALSE | FALSE |
| 4 | Trees -\> Water | 0.55 | 2.12 | 0.49 | FALSE | FALSE |
| 5 | Trees -\> Rangeland | 2.41 | 3.71 | 0.00 | FALSE | FALSE |
| 6 | Trees -\> Rangeland | 0.75 | 1.44 | 0.71 | TRUE | TRUE |
| 7 | Trees -\> Rangeland | 1.51 | 2.19 | 0.10 | FALSE | FALSE |
| 8 | Trees -\> Rangeland | 0.81 | 2.79 | 0.21 | FALSE | FALSE |
| 9 | Trees -\> Rangeland | 7.99 | 4.87 | 0.11 | FALSE | FALSE |
| 10 | Trees -\> Rangeland | 0.53 | 2.41 | 0.00 | FALSE | FALSE |

Change patches surviving patch_area_min = 5,000 m², with artifact
evidence. {.table}

The independent check is spectral. The *Trajectories as a Check on
Land-Cover Change* vignette runs
[`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
on a Sentinel-2 kNDVI cube over the same reach and reads a mapped
`Trees -> Rangeland` outline with no spectral break as a label change
rather than trees coming off. That route confirms or refutes individual
patches but needs a cube, cannot separate riparian deciduous trees from
grass in peak summer, and cannot see the reciprocal relationship at all.
The geometric tags are the free, categorical-only complement — use them
to rank what to look at, and the trajectories to settle it.

## Temporal Evidence: Switch or Flicker?

The area filter and the geometric tags both work on the two-epoch
comparison, and a two-epoch comparison cannot see time. A
boundary-hugging sliver that is `Rangeland` in every year but one is
label noise; one that has been `Rangeland` every year since 2020 is a
real conversion; the geometry is identical. IO LULC is annual, so the
third leg is free: scan each pixel’s class sequence across every year
and ask whether it *settled*.

[`dft_rast_break_class()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break_class.md)
reports, per pixel, whether the series is stable, a clean switch (one
class for N years, then another for M years, and nothing else) or
flicker (more than one change), and dates the clean switches. Its
`$raster` is the same `from -> to` transition layer
[`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
produces for the two endpoints, so the patch tools above take it
unchanged. The bundled tile ships all seven years.

``` r

years_all <- 2017:2023
series <- lapply(years_all, function(yr) {
  terra::rast(system.file("extdata", paste0("example_", yr, ".tif"),
                          package = "drift"))
})
names(series) <- years_all
series <- dft_rast_classify(series, source = "io-lulc")

bc <- dft_rast_break_class(series)

changed <- bc$summary |>
  dplyr::filter(from_class != to_class) |>
  dplyr::group_by(status) |>
  dplyr::summarise(n_cells = sum(n_cells), area_ha = sum(area), .groups = "drop") |>
  dplyr::mutate(pct_area = 100 * area_ha / sum(area_ha))

knitr::kable(changed, digits = 1, col.names = c(
  "Status", "Cells", "Area (ha)", "% of changed area"
), caption = "Pixels that differ between 2017 and 2023, by what the years in between say.")
```

| Status  | Cells | Area (ha) | % of changed area |
|:--------|------:|----------:|------------------:|
| break   |  2138 |      21.4 |              62.8 |
| flicker |  1265 |      12.7 |              37.2 |

Pixels that differ between 2017 and 2023, by what the years in between
say. {.table}

37% of the ground the two-epoch comparison reports as changed never
settled: the label switched back and forth across the seven years. That
is the categorical-only reading of the trajectory vignette’s “outline
with no red” — a borderline pixel changing label, not trees coming off —
and it needs no cube.

The clean breaks are dated, and the date matters as much as the count. A
switch whose new class holds for a single year is a clean break with
`n_after == 1`: the last year alone differs, and one more year of data
could turn it into flicker. Confidence is `min(n_before, n_after)`.

``` r

brk <- bc$summary |>
  dplyr::filter(status == "break") |>
  dplyr::group_by(break_year) |>
  dplyr::summarise(area_ha = sum(area), .groups = "drop")

ev <- terra::values(bc$breaks)
one <- !is.na(ev[, "n_flips"]) & ev[, "n_flips"] == 1
n_sustained <- sum(one & pmin(ev[, "n_before"], ev[, "n_after"]) >= 2)
n_endpoint <- sum(one & pmin(ev[, "n_before"], ev[, "n_after"]) == 1)

knitr::kable(brk, digits = 2, col.names = c("Break year", "Area (ha)"),
             caption = "Clean switches by the first year of the new class.")
```

| Break year | Area (ha) |
|-----------:|----------:|
|       2018 |      2.64 |
|       2019 |      1.65 |
|       2020 |      7.12 |
|       2021 |      0.39 |
|       2022 |      1.82 |
|       2023 |      7.76 |

Clean switches by the first year of the new class. {.table}

Of the 2138 clean-break pixels, 1098 hold the new class for at least two
years on each side of the switch and 1040 have 2017 or 2023 as the odd
year out — 776 of them are `2023` alone differing. The 2017 -\> 2023
change on this reach is therefore three different things: a sustained,
dated conversion (32% of the changed area), an endpoint that may itself
be the noisy year, and flicker.

The scan also finds what no two-epoch comparison can: pixels that
switched and switched back read as *stable* on the endpoints and are
flicker here — 2,791 cells on this reach, none of them in any transition
table.

``` r

codes <- terra::deepcopy(bc$raster)
levels(codes) <- NULL
is_changed <- (codes %/% 1000L) != (codes %% 1000L)
flick <- terra::ifel(is_changed & bc$breaks[["n_flips"]] >= 2, 1L, NA)
pal_yr <- hcl.colors(6, "Viridis")
par(mar = c(0, 0, 0, 0))
plot(aoi_proj, border = "black", lwd = 1)
terra::plot(flick, col = "#bdbdbd", legend = FALSE, add = TRUE)
terra::plot(bc$breaks[["break_year"]], col = pal_yr, type = "classes",
            legend = FALSE, add = TRUE)
# terra::plot(add = TRUE) leaves a coordinate system in which a keyword
# position can land off-frame, so anchor the legend in the empty lower right
u <- par("usr")
legend(x = u[1] + 0.74 * (u[2] - u[1]), y = u[3] + 0.42 * (u[4] - u[3]),
       title = "First year of new class", fill = c(pal_yr, "#bdbdbd"),
       legend = c(2018:2023, "Flickers"), bty = "n", cex = 0.8, xpd = NA)
```

![Break year for pixels with a clean switch (one class, then another,
nothing else). Grey pixels changed between 2017 and 2023 but flicker in
between.](land-cover-change_files/figure-html/plot-break-year-1.png)

Break year for pixels with a clean switch (one class, then another,
nothing else). Grey pixels changed between 2017 and 2023 but flicker in
between.

Per patch, the three legs compose.
[`terra::zonal()`](https://rspatial.github.io/terra/reference/zonal.html)
gives each change patch the share of its cells that are a clean break,
alongside the width and boundary evidence from the section above.

``` r

patches7 <- dft_transition_vectors(bc$raster, changes_only = TRUE)
patches7 <- dft_transition_artifact(patches7, bc$raster)
pid <- terra::rasterize(terra::vect(patches7), bc$raster, field = "patch_id")
is_break <- terra::ifel(bc$breaks[["n_flips"]] == 1, 1L, 0L)
z <- terra::zonal(c(is_break, bc$breaks[["n_flips"]]), pid, fun = "mean", na.rm = TRUE)
names(z) <- c("patch_id", "break_frac", "n_flips_mean")
patches7 <- dplyr::left_join(patches7, z, by = "patch_id")

by_evidence <- sf::st_drop_geometry(patches7) |>
  dplyr::mutate(geometry = ifelse(flag_sliver & (flag_boundary | flag_reciprocal),
                                  "Artifact signature", "Other")) |>
  dplyr::group_by(geometry) |>
  # weighted mean first: a summarised `area_ha` would shadow the column
  dplyr::summarise(break_frac = stats::weighted.mean(break_frac, area_ha),
                   n_patches = dplyr::n(), area_ha = sum(area_ha),
                   .groups = "drop") |>
  dplyr::select(geometry, n_patches, area_ha, break_frac)

knitr::kable(by_evidence, digits = 2, col.names = c(
  "Geometric evidence", "Patches", "Area (ha)", "Clean-break share of cells"
), caption = "Change patches by geometric signature, with the area-weighted share of their cells that are a clean temporal break.")
```

| Geometric evidence | Patches | Area (ha) | Clean-break share of cells |
|:-------------------|--------:|----------:|---------------------------:|
| Artifact signature |      48 |      4.07 |                       0.45 |
| Other              |      45 |     29.96 |                       0.65 |

Change patches by geometric signature, with the area-weighted share of
their cells that are a clean temporal break. {.table}

Neither leg is proof. A patch that traces a pre-existing boundary *and*
never settled is the artifact shape twice over; one that is thin but
holds a dated break for three years is thin for a reason worth finding.
The spectral route in the trajectory vignette is the third witness where
it matters.

## Interactive Map

Toggle between classified time periods and overlay tree loss transition
layers to ground-truth change against multiple satellite basemaps.

``` r

tree_trans <- dft_rast_transition(classified, from = "2017", to = "2023",
                                  from_class = "Trees")
dft_map_interactive(classified, aoi = aoi, transition = tree_trans,
                    legend_position = "bottomleft")
```

Classified land cover by year (radio toggle) with tree loss transitions
overlaid as toggleable layers. Use the fullscreen button (top left) to
expand the map and access transition toggles in the layer control (top
right).

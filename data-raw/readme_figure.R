# Build the README map, man/figures/readme-change.png (drift#105).
#
# NOT part of the package build. Needs network for the imagery basemap (Esri
# World Imagery through gq/maptiles); the land cover is the bundled Neexdzii Kwa
# reach in inst/extdata, so the change layer itself needs nothing else.
#
# What it shows: where land cover differs between 2017 and 2023 on the reach,
# coloured by what changed to what, at half opacity. Unchanged ground is left
# transparent so the imagery shows through. Colours come from inst/cartography/drift_readme.csv.
#   Rscript data-raw/readme_figure.R

pkgload::load_all(quiet = TRUE)  # the source tree, not an installed drift
library(tmap)

d <- system.file("extdata", package = "drift")
aoi <- sf::st_read(file.path(d, "example_aoi.gpkg"), quiet = TRUE)
lulc <- list(`2017` = terra::rast(file.path(d, "example_2017.tif")),
             `2023` = terra::rast(file.path(d, "example_2023.tif")))
classified <- dft_rast_classify(lulc, source = "io-lulc")
result <- dft_rast_transition(classified, from = "2017", to = "2023")

# Group the transitions so the map carries four colours, not fourteen. The named
# groups are the three largest kinds of change on the reach; the assertion
# fails if the data no longer says so.
s <- result$summary
s <- s[s$from_class != s$to_class, ]
s$group <- ifelse(s$to_class == "Water", "to_water",
           ifelse(s$from_class == "Trees" & s$to_class == "Rangeland", "trees_rangeland",
           ifelse(s$from_class == "Crops" & s$to_class == "Rangeland", "crops_rangeland",
                  "other")))
by_group <- sort(tapply(s$area, s$group, sum), decreasing = TRUE)
print(round(by_group, 2))
stopifnot(identical(names(by_group)[1:3], c("trees_rangeland", "crops_rangeland", "to_water")))

# transition id is from_code * 1000 + to_code
ct <- dft_class_table("io-lulc")
code <- stats::setNames(ct$code, ct$class_name)
s$id <- code[s$from_class] * 1000 + code[s$to_class]
grp_levels <- c("trees_rangeland", "crops_rangeland", "to_water", "other")
id_raster <- result$raster
levels(id_raster) <- NULL
grp_raster <- terra::classify(id_raster, cbind(s$id, match(s$group, grp_levels)),
                              others = NA)
change <- sf::st_as_sf(terra::as.polygons(grp_raster, dissolve = TRUE))
names(change)[1] <- "code"
change$group <- factor(grp_levels[change$code], levels = grp_levels)

aoi <- sf::st_transform(aoi, sf::st_crs(change))

reg <- gq::gq_reg_custom(system.file("cartography", "drift_readme.csv", package = "drift"))
cls <- gq::gq_tmap_classes(reg$layers$readme_change)
stopifnot(identical(names(cls$values), grp_levels))
# one fill opacity for every class, so the imagery shows through the change
fill_opacity <- unique(vapply(reg$layers$readme_change$classification$classes,
                              function(k) k$opacity, numeric(1)))
stopifnot(length(fill_opacity) == 1)
edge <- reg$layers$readme_floodplain$stroke

# Canvas 7 x 6 in; frame the floodplain to the canvas aspect so there are no bands
fig_w <- 7
fig_h <- 6
frame <- gq::gq_bbox_aspect(aoi, asp = fig_w / fig_h, margin = 0.04)
imagery <- gq::gq_basemap_tiles(frame, provider = "Esri.WorldImagery", zoom = 16,
                                crs = sf::st_crs(change))

# Legend in the empty ground at bottom right, scale bar bottom left; the image
# credits go in the README caption rather than on the map
legend_pos <- tm_pos_in("right", "bottom")
map <- tm_shape(imagery, bbox = frame) +
  tm_rgb(col_alpha = 0.75) +
  tm_shape(change) +
  tm_polygons(fill = "group",
              fill.scale = tm_scale_categorical(values = unname(cls$values),
                                                labels = cls$labels),
              fill.legend = tm_legend(title = "Land cover change, 2017 to 2023",
                                      position = legend_pos, group_id = "key"),
              fill_alpha = fill_opacity, col = NULL) +
  tm_shape(aoi) +
  tm_borders(col = edge$color, lwd = edge$width) +
  tm_add_legend(type = "lines", labels = "Floodplain", col = edge$color,
                lwd = edge$width, position = legend_pos, group_id = "key") +
  tm_components("key", bg.color = "grey15", bg.alpha = 0.8, frame = FALSE) +
  tm_scalebar(breaks = c(0, 250, 500), position = tm_pos_in("left", "bottom"),
              text.size = 0.9, text.color = "white") +
  tm_layout(frame = FALSE, inner.margins = c(0, 0, 0, 0), outer.margins = c(0, 0, 0, 0),
            legend.text.size = 0.9, legend.title.size = 1,
            legend.text.color = "white", legend.title.color = "white")

out <- file.path("man", "figures", "readme-change.png")
tmap_save(map, out, width = fig_w, height = fig_h, units = "in", dpi = 150)

# Package index

## Fetch land cover and imagery

- [`dft_stac_fetch()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_fetch.md)
  : Fetch STAC-hosted rasters via gdalcubes
- [`dft_stac_composite()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_composite.md)
  : Fetch dated, cloud-masked reflectance composites from a STAC catalog
- [`dft_wayback_releases()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_releases.md)
  : List the Esri World Imagery Wayback releases
- [`dft_wayback_captures()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_captures.md)
  : Find the Esri Wayback captures that image each feature
- [`dft_wayback_pick()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_pick.md)
  : Pick, per feature, the capture nearest a date
- [`dft_wayback_fetch()`](https://www.newgraphenvironment.com/drift/reference/dft_wayback_fetch.md)
  : Fetch an Esri Wayback release as a local raster around an AOI

## Classify and summarize

- [`dft_rast_classify()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_classify.md)
  : Classify a raster with factor levels and colors
- [`dft_rast_summarize()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_summarize.md)
  : Summarize area by class
- [`dft_rast_consensus()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_consensus.md)
  : Compute per-pixel mode across classified rasters

## Change between two dates

- [`dft_rast_transition()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_transition.md)
  : Detect land cover transitions between two time steps
- [`dft_transition_vectors()`](https://www.newgraphenvironment.com/drift/reference/dft_transition_vectors.md)
  : Vectorize transition raster into individual change patches
- [`dft_transition_artifact()`](https://www.newgraphenvironment.com/drift/reference/dft_transition_artifact.md)
  : Tag transition patches with geometric misregistration evidence
- [`dft_transition_attribute()`](https://www.newgraphenvironment.com/drift/reference/dft_transition_attribute.md)
  : Attribute transition patches from an overlay polygon layer

## Change across an annual series

- [`dft_rast_break_class()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_break_class.md)
  : Detect sustained class switches across an annual classified series
- [`dft_break_category()`](https://www.newgraphenvironment.com/drift/reference/dft_break_category.md)
  : Temporal category of every row of a break-class summary
- [`dft_rast_break_category()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_break_category.md)
  : Temporal category of every pixel in a break-class scan
- [`dft_break_strength()`](https://www.newgraphenvironment.com/drift/reference/dft_break_strength.md)
  : How many observations a dated class switch held, either side

## Spectral index trajectories

- [`dft_stac_cube()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_cube.md)
  : Fetch a masked spectral-index cube from a STAC catalog
- [`dft_index_expr()`](https://www.newgraphenvironment.com/drift/reference/dft_index_expr.md)
  : Apply a spectral index to a data cube
- [`dft_index_table()`](https://www.newgraphenvironment.com/drift/reference/dft_index_table.md)
  : Load the shipped spectral-index registry
- [`dft_rast_break()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_break.md)
  : Detect per-pixel index-trajectory breakpoints
- [`dft_rast_trend()`](https://www.newgraphenvironment.com/drift/reference/dft_rast_trend.md)
  : Per-pixel index trend over time

## Accuracy and area

- [`dft_accuracy_sample()`](https://www.newgraphenvironment.com/drift/reference/dft_accuracy_sample.md)
  : Draw a stratified random sample of points for accuracy assessment
- [`dft_accuracy_labels()`](https://www.newgraphenvironment.com/drift/reference/dft_accuracy_labels.md)
  : Check a reference-label table against the accuracy-assessment
  contract
- [`dft_accuracy_estimate()`](https://www.newgraphenvironment.com/drift/reference/dft_accuracy_estimate.md)
  : Accuracy and error-adjusted area from a stratified reference sample
- [`dft_accuracy_size()`](https://www.newgraphenvironment.com/drift/reference/dft_accuracy_size.md)
  : Size and allocate a stratified accuracy sample

## Maps

- [`dft_map_interactive()`](https://www.newgraphenvironment.com/drift/reference/dft_map_interactive.md)
  : Interactive leaflet map for classified rasters and transitions

## Sources, classes and cache

- [`dft_stac_config()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_config.md)
  : Get STAC configuration for a known source
- [`dft_stac_classes()`](https://www.newgraphenvironment.com/drift/reference/dft_stac_classes.md)
  : Extract class table from STAC item metadata
- [`dft_class_table()`](https://www.newgraphenvironment.com/drift/reference/dft_class_table.md)
  : Load shipped class lookup table
- [`dft_cache_path()`](https://www.newgraphenvironment.com/drift/reference/dft_cache_path.md)
  : Get drift cache directory path
- [`dft_cache_info()`](https://www.newgraphenvironment.com/drift/reference/dft_cache_info.md)
  : Show drift cache info
- [`dft_cache_clear()`](https://www.newgraphenvironment.com/drift/reference/dft_cache_clear.md)
  : Clear the drift tile cache

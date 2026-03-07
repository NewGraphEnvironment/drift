#' Interactive leaflet map for classified rasters and transitions
#'
#' Build a toggleable leaflet map from classified `SpatRaster`s or remote COG
#' URLs served via titiler. Optionally overlay land cover transitions from
#' [dft_rast_transition()]. Includes layer control, legend, and fullscreen.
#'
#' When only `x` is supplied, classified layers appear as radio-toggle overlays
#' (one visible at a time). When `transition` is also supplied, each transition
#' type (e.g. Trees -> Rangeland) is added as a checkbox overlay that can be
#' shown simultaneously on top of any classified layer.
#'
#' @param x A named list of classified [terra::SpatRaster]s (e.g. from
#'   [dft_rast_classify()]) **or** a named character vector of COG URLs.
#'   A single `SpatRaster` or URL string is auto-wrapped into a length-1
#'   list/vector. Names become the layer toggle labels (years, seasons, etc.).
#' @param aoi An `sf` polygon for the area of interest outline. `NULL` (default)
#'   omits the AOI layer.
#' @param transition Output of [dft_rast_transition()] — a list with elements
#'   `raster` (factor `SpatRaster`) and `summary` (tibble). Each transition
#'   type becomes a toggleable overlay. Stable transitions (same from/to class)
#'   are excluded by default. `NULL` (default) omits transition overlays.
#' @param class_table A tibble with columns `code`, `class_name`, `color`
#'   (hex). When `NULL`, loaded via [dft_class_table()] using `source`.
#' @param source Character. Used to load a shipped class table when
#'   `class_table` is `NULL`. One of `"io-lulc"` or `"esa-worldcover"`.
#' @param titiler_url Base URL of a titiler instance (e.g.
#'   `"https://titiler.example.com"`). Only used when `x` contains COG URLs.
#'   Defaults to `getOption("drift.titiler_url")`. If `NULL` in COG mode, an
#'   error is raised prompting the user to set the option.
#' @param basemaps Named character vector of provider tile IDs or tile URL
#'   templates (starting with `http`). The first element is the default
#'   basemap. Names become radio button labels.
#' @param legend_position Legend placement passed to [leaflet::addLegend()].
#'   Set to `NULL` to suppress the legend.
#' @param zoom Initial zoom level.
#'
#' @return A [leaflet::leaflet] htmlwidget. The first layer in `x` is visible
#'   by default; other layers are hidden but toggleable. Transition overlays
#'   are visible by default when supplied.
#' @export
#' @examples
#' # Single classified raster — returns a leaflet widget
#' r <- terra::rast(system.file("extdata", "example_2020.tif", package = "drift"))
#' classified <- dft_rast_classify(r, source = "io-lulc")
#' map <- dft_map_interactive(classified)
#' class(map)
#'
#' # Multiple years with AOI — toggle between time periods
#' aoi <- sf::st_read(
#'   system.file("extdata", "example_aoi.gpkg", package = "drift"),
#'   quiet = TRUE
#' )
#' files <- c("2017" = "example_2017.tif", "2020" = "example_2020.tif",
#'            "2023" = "example_2023.tif")
#' rasters <- lapply(files, function(f) {
#'   terra::rast(system.file("extdata", f, package = "drift"))
#' })
#' classified <- dft_rast_classify(rasters, source = "io-lulc")
#' map <- dft_map_interactive(classified, aoi = aoi)
#' if (interactive()) map
#'
#' # Combined: classified layers + transition overlays
#' trans <- dft_rast_transition(classified, from = "2017", to = "2023",
#'                              from_class = "Trees")
#' map <- dft_map_interactive(classified, aoi = aoi, transition = trans)
#' if (interactive()) map
#'
#' \dontrun{
#' # Remote COGs via titiler (requires options(drift.titiler_url = "..."))
#' cogs <- c("2017" = "https://bucket.s3.amazonaws.com/lulc_2017.tif",
#'           "2023" = "https://bucket.s3.amazonaws.com/lulc_2023.tif")
#' dft_map_interactive(cogs, source = "io-lulc")
#' }
dft_map_interactive <- function(x,
                                aoi = NULL,
                                transition = NULL,
                                class_table = NULL,
                                source = "io-lulc",
                                titiler_url = getOption("drift.titiler_url"),
                                basemaps = c("Light" = "CartoDB.Positron",
                                             "Esri Satellite" = "Esri.WorldImagery",
                                             "Google Satellite" = "https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}"),
                                legend_position = "bottomright",
                                zoom = 14) {
  rlang::check_installed(c("leaflet", "leaflet.extras"))

  if (is.null(class_table)) {
    class_table <- dft_class_table(source)
  }

  # Validate transition input
  if (!is.null(transition)) {
    if (!is.list(transition) || !all(c("raster", "summary") %in% names(transition))) {
      stop("`transition` must be output of dft_rast_transition() ",
           "(a list with $raster and $summary).")
    }
  }

  # Detect mode and normalize input
  cog_mode <- is.character(x)

  if (cog_mode) {
    if (is.null(names(x)) && length(x) == 1L) {
      x <- stats::setNames(x, "Layer")
    }
    if (is.null(titiler_url)) {
      rlang::abort(paste0(
        "COG mode requires a titiler URL. Set:\n",
        "  options(drift.titiler_url = \"https://your-titiler.example.com\")"
      ))
    }
  } else {
    # SpatRaster input
    if (inherits(x, "SpatRaster")) {
      x <- list("Layer" = x)
    }
  }

  # Compute map center
  if (!is.null(aoi)) {
    bbox <- sf::st_bbox(sf::st_transform(aoi, 4326))
  } else if (!cog_mode) {
    ext <- terra::ext(terra::project(x[[1]], "EPSG:4326"))
    bbox <- c(xmin = ext[1], ymin = ext[3], xmax = ext[2], ymax = ext[4])
  } else {
    bbox <- NULL
  }

  map <- leaflet::leaflet()

  if (!is.null(bbox)) {
    map <- leaflet::setView(
      map,
      lng = mean(bbox[c("xmin", "xmax")]),
      lat = mean(bbox[c("ymin", "ymax")]),
      zoom = zoom
    )
  }

  # Add basemaps — first is default
  for (i in seq_along(basemaps)) {
    bm <- basemaps[[i]]
    nm <- names(basemaps)[[i]]
    if (grepl("^https?://", bm)) {
      map <- leaflet::addTiles(map, urlTemplate = bm, group = nm)
    } else {
      map <- leaflet::addProviderTiles(map, bm, group = nm)
    }
  }

  # Add classified layers
  if (cog_mode) {
    for (nm in names(x)) {
      tile_url <- build_titiler_url(titiler_url, x[[nm]], class_table)
      map <- leaflet::addTiles(map, urlTemplate = tile_url, group = nm)
    }
  } else {
    for (nm in names(x)) {
      map <- leaflet::addRasterImage(
        map,
        terra::project(x[[nm]], "EPSG:4326"),
        group = nm,
        project = FALSE
      )
    }
  }

  # Track overlay groups (classified layers are radio-toggled via hideGroup)
  overlay_groups <- names(x)

  # Add transition overlays
  trans_groups <- character(0)
  if (!is.null(transition)) {
    trans_result <- add_transition_layers(map, transition, class_table)
    map <- trans_result$map
    trans_groups <- trans_result$groups
    overlay_groups <- c(overlay_groups, trans_groups)
  }

  # AOI outline
  if (!is.null(aoi)) {
    map <- leaflet::addPolygons(
      map,
      data = sf::st_transform(aoi, 4326),
      fill = FALSE, color = "red", weight = 2,
      group = "AOI"
    )
    overlay_groups <- c(overlay_groups, "AOI")
  }

  # Legend — land cover classes
  if (!is.null(legend_position)) {
    if (cog_mode) {
      ct_legend <- class_table[class_table$class_name != "No Data", ]
    } else {
      present <- unique(unlist(lapply(x, function(r) {
        terra::levels(r)[[1]]$class_name
      })))
      ct_legend <- class_table[class_table$class_name %in% present, ]
    }

    map <- leaflet::addLegend(
      map,
      position = legend_position,
      colors = ct_legend$color,
      labels = ct_legend$class_name,
      title = "Land Cover",
      opacity = 1
    )

    # Legend — transitions
    if (length(trans_groups) > 0) {
      trans_colors <- attr(trans_result, "colors")
      map <- leaflet::addLegend(
        map,
        position = legend_position,
        colors = trans_colors,
        labels = trans_groups,
        title = "Transitions",
        opacity = 1
      )
    }
  }

  # Layer control + fullscreen
  map <- leaflet::addLayersControl(
    map,
    baseGroups = names(basemaps),
    overlayGroups = overlay_groups,
    options = leaflet::layersControlOptions(collapsed = FALSE)
  )
  # Hide all classified layers except the first (radio-style toggle)
  map <- leaflet::hideGroup(map, setdiff(names(x), names(x)[1]))
  map <- leaflet.extras::addFullscreenControl(map)

  map
}


#' Add transition overlay layers to a leaflet map
#'
#' @param map A leaflet map object.
#' @param transition Output of [dft_rast_transition()].
#' @param class_table Class table for color lookup.
#' @return A list with `map` (updated leaflet), `groups` (overlay group names).
#'   Has attribute `"colors"` with the hex colors used.
#' @noRd
add_transition_layers <- function(map, transition, class_table) {
  s <- transition$summary
  r <- transition$raster

  # Exclude stable transitions (from == to)
  s <- s[s$from_class != s$to_class, , drop = FALSE]

  if (nrow(s) == 0) {
    result <- list(map = map, groups = character(0))
    attr(result, "colors") <- character(0)
    return(result)
  }

  # Build color lookup from class_table: to_class gets its class color
  color_lookup <- stats::setNames(class_table$color, class_table$class_name)

  # Get factor levels table
  lvls <- terra::cats(r)[[1]]

  groups <- character(0)
  colors <- character(0)

  for (i in seq_len(nrow(s))) {
    label <- paste0(s$from_class[i], " -> ", s$to_class[i])

    # Find this transition in factor levels
    lvl_row <- lvls[lvls$transition == label, , drop = FALSE]
    if (nrow(lvl_row) == 0) next

    # Create binary mask: 1 where this transition, NA elsewhere
    r_mask <- terra::rast(r)
    raw_vals <- terra::values(r)
    terra::values(r_mask) <- ifelse(raw_vals == lvl_row$id[1], 1L, NA_integer_)

    # Color from to_class
    col <- if (s$to_class[i] %in% names(color_lookup)) {
      color_lookup[[s$to_class[i]]]
    } else {
      "#999999"
    }

    r_proj <- terra::project(r_mask, "EPSG:4326", method = "near")
    map <- leaflet::addRasterImage(
      map, r_proj, group = label,
      colors = col, project = FALSE
    )

    groups <- c(groups, label)
    colors <- c(colors, col)
  }

  result <- list(map = map, groups = groups)
  attr(result, "colors") <- colors
  result
}


#' Build a titiler tile URL template for a COG
#'
#' Constructs a tile URL with a discrete colormap derived from the class table.
#'
#' @param titiler_url Base titiler URL.
#' @param cog_url URL of the COG on S3 or other HTTP host.
#' @param class_table Tibble with `code` and `color` columns.
#' @return A character string suitable for [leaflet::addTiles()] `urlTemplate`.
#' @noRd
build_titiler_url <- function(titiler_url, cog_url, class_table) {
  # Build discrete colormap JSON: {"1": [65, 155, 223, 255], ...}
  # titiler expects RGBA arrays, not hex strings
  rgb_list <- lapply(class_table$color, function(hex) {
    r <- strtoi(substr(hex, 2, 3), 16L)
    g <- strtoi(substr(hex, 4, 5), 16L)
    b <- strtoi(substr(hex, 6, 7), 16L)
    c(r, g, b, 255L)
  })
  names(rgb_list) <- as.character(class_table$code)
  colormap_json <- paste0(
    "{",
    paste(
      vapply(names(rgb_list), function(k) {
        paste0("\"", k, "\":[", paste(rgb_list[[k]], collapse = ","), "]")
      }, character(1)),
      collapse = ","
    ),
    "}"
  )

  paste0(
    titiler_url, "/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png",
    "?url=", utils::URLencode(cog_url, reserved = TRUE),
    "&bidx=1",
    "&colormap=", utils::URLencode(colormap_json, reserved = TRUE)
  )
}

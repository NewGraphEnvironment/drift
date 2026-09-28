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
#' When `rgb` is supplied, each composite (e.g. from [dft_stac_composite()]) is
#' added as a switchable overlay beneath the classified and transition layers,
#' so dated imagery can be toggled under a land-cover label to check it. Every
#' composite gets **the same stretch**: each band's display range is set once,
#' from all the composites pooled, so a brightness or colour difference between
#' two years is in the data and not an artefact of stretching each image to its
#' own histogram.
#'
#' @param x A named list of classified [terra::SpatRaster]s (e.g. from
#'   [dft_rast_classify()]) **or** a named character vector of COG URLs.
#'   A single `SpatRaster` or URL string is auto-wrapped into a length-1
#'   list/vector. Names become the layer toggle labels (years, seasons, etc.).
#'   May be `NULL` when `rgb` is supplied, for an imagery-only map.
#' @param aoi An `sf` polygon for the area of interest outline. `NULL` (default)
#'   omits the AOI layer.
#' @param transition Output of [dft_rast_transition()] — a list with elements
#'   `raster` (factor `SpatRaster`) and `summary` (tibble). Each transition
#'   type becomes a toggleable overlay. Stable transitions (same from/to class)
#'   are excluded by default. `NULL` (default) omits transition overlays.
#' @param rgb Dated reference imagery: a named list of three-band
#'   [terra::SpatRaster]s in red, green, blue order (the output of
#'   [dft_stac_composite()] with its default `bands`), **or** a named character
#'   vector of three-band COG URLs served through `titiler_url`. Names become
#'   the layer labels, e.g. `"2017 Jun–Jul"`. Local rasters are drawn with
#'   [leafem::addRasterRGB()], which reads every cell into memory; for a
#'   floodplain-sized composite, publish the cached COG and pass its URL
#'   instead. `NULL` (default) adds no imagery.
#' @param rgb_rescale Numeric length-2 reflectance range stretched to the full
#'   display range, the same for every band of every `rgb` layer. When `NULL`,
#'   local rasters stretch each band from its 2nd to 98th percentile across all
#'   composites pooled, and COG URLs use `c(0, 0.3)`, a range that suits
#'   vegetated land in surface reflectance.
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
#'   are visible by default when supplied. `rgb` layers are hidden when `x` is
#'   supplied (toggle them on beneath it); without `x` the first is shown.
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
#'
#' # Dated true-colour composites beneath the land cover (network + gdalcubes)
#' tc <- dft_stac_composite(aoi, years = c(2017, 2023), months = 6:7)
#' dft_map_interactive(classified, aoi = aoi, rgb = tc)
#' }
dft_map_interactive <- function(x = NULL,
                                aoi = NULL,
                                transition = NULL,
                                rgb = NULL,
                                rgb_rescale = NULL,
                                class_table = NULL,
                                source = "io-lulc",
                                titiler_url = getOption("drift.titiler_url"),
                                basemaps = c("Light" = "CartoDB.Positron",
                                             "Esri Satellite" = "Esri.WorldImagery",
                                             "Google Satellite" = "https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}",
                                             "OpenTopoMap" = "OpenTopoMap"),
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

  if (is.null(x) && is.null(rgb)) {
    cli::cli_abort("Supply {.arg x} (classified layers), {.arg rgb} (imagery), or both.")
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

  rgb <- rgb_layers_check(rgb, titiler_url)
  rgb_cog <- is.character(rgb)
  clash <- intersect(names(rgb), names(x))
  if (length(clash)) {
    cli::cli_abort(c(
      "{.arg rgb} and {.arg x} share layer name{?s} {.val {clash}}.",
      "i" = "Names become layer groups, so a shared name merges two layers."
    ))
  }

  # Compute map center
  if (!is.null(aoi)) {
    bbox <- sf::st_bbox(sf::st_transform(aoi, 4326))
  } else if (!is.null(x) && !cog_mode) {
    bbox <- raster_bbox_4326(x[[1]])
  } else if (!is.null(rgb) && !rgb_cog) {
    bbox <- raster_bbox_4326(rgb[[1]])
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

  # Dated imagery first, so it draws beneath the classified and transition
  # layers: leaflet stacks overlays in the order they are added.
  if (!is.null(rgb)) {
    map <- add_rgb_layers(map, rgb, rgb_rescale, titiler_url)
  }

  # Add classified layers
  if (is.null(x)) {
    # imagery-only map
  } else if (cog_mode) {
    for (nm in names(x)) {
      tile_url <- build_titiler_url(titiler_url, x[[nm]], class_table)
      map <- leaflet::addTiles(map, urlTemplate = tile_url, group = nm)
    }
  } else {
    for (nm in names(x)) {
      # EPSG:3857, not 4326: with project = FALSE leaflet places the pixels
      # linearly between Web Mercator bounds, so a 4326 grid is misregistered
      # in latitude, which shows once RGB imagery (drawn in 3857) sits beneath.
      map <- leaflet::addRasterImage(
        map,
        terra::project(x[[nm]], "EPSG:3857", method = "near"),
        group = nm,
        project = FALSE
      )
    }
  }

  # Track overlay groups (classified layers are radio-toggled via hideGroup)
  overlay_groups <- c(names(rgb), names(x))

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

  # Legend — land cover classes (none for an imagery-only map)
  if (!is.null(legend_position) && !is.null(x)) {
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
  # Hide all classified layers except the first (radio-style toggle). Imagery
  # sits beneath the classified layers, so it starts hidden when they are
  # present; on an imagery-only map the first composite is shown.
  hidden <- setdiff(names(x), names(x)[1])
  hidden <- c(hidden, if (is.null(x)) setdiff(names(rgb), names(rgb)[1]) else names(rgb))
  if (length(hidden)) map <- leaflet::hideGroup(map, hidden)
  map <- leaflet.extras::addFullscreenControl(map)

  map
}


#' Validate and normalize the `rgb` argument of dft_map_interactive()
#'
#' Returns `NULL`, a named list of three-band SpatRasters, or a named character
#' vector of COG URLs. A single raster or unnamed URL is wrapped as `"RGB"`.
#' @noRd
rgb_layers_check <- function(rgb, titiler_url) {
  if (is.null(rgb)) return(NULL)
  if (inherits(rgb, "SpatRaster")) rgb <- list(RGB = rgb)
  if (is.character(rgb)) {
    if (is.null(names(rgb)) && length(rgb) == 1L) rgb <- stats::setNames(rgb, "RGB")
    if (is.null(titiler_url)) {
      cli::cli_abort(c(
        "COG URLs in {.arg rgb} need a titiler URL.",
        "i" = "Set {.code options(drift.titiler_url = \"https://...\")}."
      ))
    }
  } else if (!is.list(rgb) ||
               !all(vapply(rgb, inherits, logical(1), what = "SpatRaster"))) {
    cli::cli_abort(
      "{.arg rgb} must be a named list of SpatRasters or a named character vector of COG URLs."
    )
  }
  nm <- names(rgb)
  if (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) {
    cli::cli_abort("{.arg rgb} must be named, with distinct names (they become layer labels).")
  }
  if (is.list(rgb)) {
    n <- vapply(rgb, terra::nlyr, numeric(1))
    bad <- nm[n != 3]
    if (length(bad)) {
      cli::cli_abort(c(
        "Every {.arg rgb} layer must have three bands (red, green, blue).",
        "x" = "Not three: {.val {bad}}."
      ))
    }
  }
  rgb
}


#' The shared stretch for local RGB layers: per band, pooled across composites
#'
#' Returns a 2 x 3 matrix of (low, high) per band: each band's 2nd and 98th
#' percentile over every composite pooled, from a regular sample so a large
#' raster is not read whole to find six numbers. Per band keeps a false-colour
#' NIR channel from saturating; pooled keeps two years on one scale.
#' @noRd
rgb_domain <- function(rgb, probs = c(0.02, 0.98), size = 1e5) {
  smp <- do.call(rbind, lapply(rgb, function(r) {
    v <- terra::spatSample(r, size = size, method = "regular", as.df = TRUE)
    names(v) <- paste0("b", 1:3)
    v
  }))
  dom <- vapply(smp, function(z) {
    z <- z[is.finite(z)]
    if (!length(z)) return(c(NA_real_, NA_real_))
    unname(stats::quantile(z, probs))
  }, numeric(2))
  if (anyNA(dom)) cli::cli_abort("The {.arg rgb} layers have no data to stretch.")
  flat <- dom[2, ] <= dom[1, ]
  dom[2, flat] <- dom[1, flat] + 1e-6
  dom
}


#' Stretch a three-band raster to 0-1 with a fixed per-band range, clamped
#' @noRd
rgb_stretch <- function(r, dom) {
  out <- (r - dom[1, ]) / (dom[2, ] - dom[1, ])
  terra::clamp(out, lower = 0, upper = 1, values = TRUE)
}


#' Add dated RGB layers to a leaflet map, with one shared stretch
#'
#' Local rasters are stretched here, in terra, and handed to leafem already on
#' 0-1 with `quantiles = NULL, domain = c(0, 1)`: leafem otherwise stretches
#' each layer to its own histogram (its `quantiles` default wins over `domain`),
#' which is exactly the per-image stretch this avoids. Bands are 1, 2, 3 =
#' red, green, blue; leafem's own default is 3, 2, 1.
#' @noRd
add_rgb_layers <- function(map, rgb, rgb_rescale, titiler_url) {
  if (!is.null(rgb_rescale) &&
        (!is.numeric(rgb_rescale) || length(rgb_rescale) != 2L ||
           anyNA(rgb_rescale) || rgb_rescale[2] <= rgb_rescale[1])) {
    cli::cli_abort("{.arg rgb_rescale} must be two increasing numbers, e.g. {.code c(0, 0.3)}.")
  }
  if (is.character(rgb)) {
    rescale <- rgb_rescale %||% c(0, 0.3)
    for (nm in names(rgb)) {
      map <- leaflet::addTiles(
        map, urlTemplate = build_titiler_rgb_url(titiler_url, rgb[[nm]], rescale),
        group = nm
      )
    }
    return(map)
  }
  rlang::check_installed("leafem", reason = "to draw RGB layers")
  dom <- if (is.null(rgb_rescale)) rgb_domain(rgb) else matrix(rgb_rescale, 2, 3)
  for (nm in names(rgb)) {
    map <- leafem::addRasterRGB(
      map, rgb_stretch(rgb[[nm]], dom), r = 1, g = 2, b = 3,
      quantiles = NULL, domain = c(0, 1),
      na.color = "#00000000", group = nm
    )
  }
  map
}


#' Build a titiler tile URL template for a three-band COG with a fixed stretch
#'
#' The rescale is repeated once per band so every band gets the same range
#' whatever titiler does with a single value.
#' @noRd
build_titiler_rgb_url <- function(titiler_url, cog_url, rescale) {
  # per element: format() on a vector pads to a common width ("0.0,0.3")
  rs <- paste(vapply(rescale, format, character(1), scientific = FALSE,
                     trim = TRUE), collapse = ",")
  titiler_tile_url(
    titiler_url, cog_url,
    paste0("&bidx=1&bidx=2&bidx=3",
           strrep(paste0("&rescale=", utils::URLencode(rs, reserved = TRUE)), 3L))
  )
}


#' The titiler tile URL template both COG layer kinds share
#'
#' `query` is appended as given, so it must already be percent-encoded.
#' @noRd
titiler_tile_url <- function(titiler_url, cog_url, query) {
  paste0(
    titiler_url, "/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png",
    "?url=", utils::URLencode(cog_url, reserved = TRUE),
    query
  )
}


#' A raster's extent in EPSG:4326 as a named bbox vector
#' @noRd
raster_bbox_4326 <- function(r) {
  # terra::rast(r) is deliberately the EMPTY template: only the extent is
  # wanted, so projecting geometry alone avoids resampling every cell.
  ext <- terra::ext(terra::project(terra::rast(r), "EPSG:4326"))
  c(xmin = ext[1], ymin = ext[3], xmax = ext[2], ymax = ext[4])
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

    r_proj <- terra::project(r_mask, "EPSG:3857", method = "near")
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

  titiler_tile_url(
    titiler_url, cog_url,
    paste0("&bidx=1",
           "&colormap=", utils::URLencode(colormap_json, reserved = TRUE))
  )
}

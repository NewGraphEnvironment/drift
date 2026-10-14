#' Fetch an Esri Wayback release as a local raster around an AOI
#'
#' Reads one Wayback release's tiles at one zoom over `aoi` and returns a
#' three-band (red, green, blue) 8-bit raster, cached as a COG. Take the
#' `release_id` and `zoom` from [dft_wayback_pick()], so the raster shows the
#' capture you chose.
#'
#' GDAL reads the tiles. It follows the redirect a release answers with for a
#' tile it shares with an older release, which QGIS does not
#' (qgis/QGIS#54161), so a cached local raster is also the way to draw a
#' Wayback capture in QGIS. Tiles are always read at `zoom` itself, never
#' from a shallower level GDAL would otherwise substitute for a coarse `res`,
#' since a shallower level can show another capture.
#'
#' The finished raster is cached; the tiles are not. GDAL's own tile cache
#' turns every missing (404) tile into a pair of read errors (measured on GDAL
#' 3.13.0), and a fetch that treats GDAL errors as failures cannot tell those
#' from a real one. A cache hit downloads nothing; a new grid re-downloads.
#'
#' **Empty tiles.** A tile the release does not have (HTTP 404) reads as zeros.
#' A pixel that is zero in all three bands is treated as empty and becomes
#' nodata, and the call aborts (class `drift_wayback_empty`) when more than
#' `empty_max` of the AOI is empty: the release has no imagery at that zoom
#' there. A FLAT area is not empty: open water is flat. Elsewhere a band value of
#' 0 is raised to 1, because 0 is the nodata value.
#'
#' **Per point, one call each.** For chips around sample points, buffer each
#' point and call once per buffered point, as for [dft_stac_composite()]; each
#' chip is cached separately. Points themselves are refused. With
#' `clip = TRUE` a cell belongs to the AOI when its centre does, so AOIs that
#' tile the ground without overlap, such as Voronoi cells around the points,
#' produce chips that share no cell. A VRT over such chips then shows each
#' point's own capture at the point: it composites over nodata, which is why
#' these are nodata-masked and not alpha-masked.
#'
#' **Mosaics need one grid.** The default `crs` is the UTM zone of the AOI and
#' the default `res` follows its latitude, so chips spread over a large area
#' can differ in both. Pass the same `crs` and `res` to every call whose
#' outputs will be mosaicked.
#'
#' A polygon's fetch shows whatever the release draws there, which can be
#' several captures (see `cover` in [dft_wayback_captures()]).
#'
#' @param aoi An `sf`, `sfc` or `terra::SpatVector` of polygons. Several
#'   features are fetched as their union.
#' @param release A Wayback `release_id` (from [dft_wayback_releases()] or
#'   [dft_wayback_pick()]).
#' @param zoom One tile zoom level in 10 to 22, normally the `zoom` that
#'   [dft_wayback_pick()] returns with the release.
#' @param crs Output CRS (e.g. `"EPSG:3005"`). When `NULL`, the UTM zone of the
#'   AOI centroid.
#' @param res Output cell size in CRS units. When `NULL`, the tiles' own ground
#'   resolution at the AOI's latitude (Web Mercator pixels shrink by the cosine
#'   of the latitude), rounded to 0.05 m: zoom 17 is 0.70 m at 54 degrees
#'   north. Required for a geographic `crs`.
#' @param clip Logical. Set cells whose centre is outside `aoi` to nodata
#'   (default `TRUE`). `FALSE` keeps the whole bounding box.
#' @param empty_max Numeric in 0 to 1. The largest share of the AOI's cells that
#'   may come back empty before the call aborts (default 0.05).
#' @param cache_dir Character. Cache directory. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-build the raster even if cached (default `FALSE`).
#'
#' @return A [terra::SpatRaster] with layers `red`, `green`, `blue` (INT1U,
#'   nodata 0), backed by the cached COG.
#'
#' @seealso [dft_wayback_captures()], [dft_wayback_pick()],
#'   [dft_map_interactive()] (`rgb =`) to display it.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
#' pts <- sf::st_as_sf(sf::st_sample(aoi, 5, type = "regular"))
#' cap <- dft_wayback_captures(pts)
#' pick <- dft_wayback_pick(cap, as.Date("2017-07-01"))
#'
#' # One chip per point, +/-150 m, on one grid so they can be mosaicked
#' buf <- sf::st_buffer(pts, 150, endCapStyle = "SQUARE")
#' chips <- lapply(seq_len(nrow(pick)), function(i) {
#'   dft_wayback_fetch(buf[pick$feature[i], ], pick$release_id[i], pick$zoom[i],
#'                     crs = "EPSG:3005", res = 0.7)
#' })
#' terra::plotRGB(chips[[1]])
#' }
#'
#' @export
dft_wayback_fetch <- function(aoi,
                              release,
                              zoom,
                              crs = NULL,
                              res = NULL,
                              clip = TRUE,
                              empty_max = 0.05,
                              cache_dir = NULL,
                              force = FALSE) {
  aoi <- wayback_aoi_check(aoi)
  if (any(as.character(sf::st_geometry_type(aoi)) == "POINT")) {
    cli::cli_abort(c(
      "{.arg aoi} must be polygons for a fetch.",
      "i" = "Buffer a point first, e.g. {.code sf::st_buffer(pt, 150, endCapStyle = \"SQUARE\")}."
    ))
  }
  release <- as.character(release)
  if (length(release) != 1L || is.na(release) || !grepl("^[0-9]+$", release)) {
    cli::cli_abort("{.arg release} must be one Wayback release id (digits).")
  }
  zoom <- wayback_zoom_check(zoom, scalar = TRUE)
  clip <- isTRUE(as.logical(clip))
  force <- isTRUE(as.logical(force))
  if (!is.numeric(empty_max) || length(empty_max) != 1L || is.na(empty_max) ||
        empty_max < 0 || empty_max > 1) {
    cli::cli_abort("{.arg empty_max} must be one number in 0 to 1.")
  }

  crs <- if (is.null(crs)) auto_utm_epsg(aoi) else wayback_crs_check(crs)
  target <- sf::st_union(sf::st_geometry(sf::st_transform(aoi, sf::st_crs(crs))))
  if (is.null(res)) {
    if (isTRUE(sf::st_is_longlat(target))) {
      cli::cli_abort("{.arg res} is required for a geographic {.arg crs}.")
    }
    res <- wayback_ground_res(zoom, aoi)
  }
  if (!is.numeric(res) || length(res) != 1L || is.na(res) || res <= 0) {
    cli::cli_abort("{.arg res} must be one positive number.")
  }

  dir_wb <- cache_scheme_dir(cache_dir, "esri-wayback")
  dir.create(dir_wb, recursive = TRUE, showWarnings = FALSE)
  key <- cache_key_hash(list(
    sf::st_as_binary(target, endian = "little"), release, as.integer(zoom),
    crs, as.numeric(res), clip, as.numeric(empty_max),
    # The fixed choices: change any of them, change this.
    paste("wayback-fetch-v1 bilinear tap ovr=NONE zero=204,404 nodata=0",
          .wayback_tile_url)
  ))
  cache_file <- file.path(dir_wb, paste0("chip_", key, ".tif"))
  label <- sprintf("Wayback release %s, zoom %d", release, zoom)
  if (!force && file.exists(cache_file) && cache_hit_ok(cache_file, label)) {
    return(wayback_finish(terra::rast(cache_file)))
  }

  src <- wayback_source(release, zoom)
  cache_write_atomic(cache_file, function(path) {
    x <- wayback_warp(src, target, crs, res)
    x <- wayback_nodata(x, target, clip, empty_max, label)
    terra::writeRaster(
      x, path, filetype = "COG", datatype = "INT1U", NAflag = 0,
      overwrite = TRUE,
      gdal = c("COMPRESS=DEFLATE", "PREDICTOR=YES", "BLOCKSIZE=512",
               "OVERVIEW_RESAMPLING=AVERAGE")
    )
  })
  wayback_finish(terra::rast(cache_file))
}


#' A GDAL dataset for one release at one zoom: a TMS description in a tempfile
#'
#' GDAL follows the relative 301 a deduplicated tile answers with and reads a
#' 404 or 204 tile as zeros rather than aborting. No `<Cache>`: with one, each
#' 404 tile also raises "No such file" and "Unable to open downloaded block"
#' (GDAL 3.13.0), though the values are the same zeros. The test seam: mock
#' this to return a local raster.
#' @noRd
wayback_source <- function(release, zoom) {
  f <- tempfile(sprintf("wayback_%s_z%d_", release, zoom), fileext = ".xml")
  writeLines(wayback_wms_xml(release, zoom), f)
  f
}


#' @noRd
wayback_wms_xml <- function(release, zoom) {
  sprintf(paste0(
    "<GDAL_WMS>\n",
    "  <Service name=\"TMS\"><ServerUrl>%s/%s/${z}/${y}/${x}</ServerUrl></Service>\n",
    "  <DataWindow><UpperLeftX>-20037508.34</UpperLeftX><UpperLeftY>20037508.34</UpperLeftY>",
    "<LowerRightX>20037508.34</LowerRightX><LowerRightY>-20037508.34</LowerRightY>",
    "<TileLevel>%d</TileLevel><TileCountX>1</TileCountX><TileCountY>1</TileCountY>",
    "<YOrigin>top</YOrigin></DataWindow>\n",
    "  <Projection>EPSG:3857</Projection><BlockSizeX>256</BlockSizeX>",
    "<BlockSizeY>256</BlockSizeY><BandsCount>3</BandsCount>\n",
    "  <ZeroBlockHttpCodes>204,404</ZeroBlockHttpCodes>\n",
    "</GDAL_WMS>\n"
  ), .wayback_tile_url, release, as.integer(zoom))
}


#' Warp the source onto a grid aligned to `res` over the target's bbox
#'
#' Every GDAL warning is a failure: a tile that errored part way leaves a
#' raster that looks complete. The abort prints them.
#' @noRd
wayback_warp <- function(src, target, crs, res) {
  out <- tempfile(fileext = ".tif")
  on.exit(unlink(out), add = TRUE)
  b <- as.numeric(sf::st_bbox(target))
  warns <- character(0)
  # sf raises a bare "an error occured" when GDAL fails outright; the GDAL
  # message arrives first as a warning, so both are recorded and one classed
  # abort is raised after the call.
  ok <- tryCatch(
    withCallingHandlers(
      sf::gdal_utils(
        "warp", source = src, destination = out,
        # -ovr NONE: at a res coarser than the zoom's, gdalwarp would read a
        # shallower zoom from the service's overviews, which can be another
        # capture
        options = c("-t_srs", crs, "-te", b, "-tr", res, res, "-tap",
                    "-r", "bilinear", "-ovr", "NONE", "-overwrite"),
        config_options = c(GDAL_PAM_ENABLED = "NO")
      ),
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      warns <<- c(warns, conditionMessage(e))
      FALSE
    }
  )
  if (length(warns) || !isTRUE(ok) || !file.exists(out)) {
    cli::cli_abort(
      c("GDAL could not read the Wayback tiles cleanly.",
        if (length(warns)) c("x" = "{utils::head(warns, 3)}")),
      class = "drift_wayback_http"
    )
  }
  x <- terra::rast(out)
  if (terra::nlyr(x) < 3L) {
    cli::cli_abort("The Wayback source has {terra::nlyr(x)} band{?s}, not 3.")
  }
  # into memory before the tempfile goes: a chip is small
  x <- x[[1:3]] * 1
  x
}


#' Empty pixels (zero in all three bands) and cells outside the AOI to NA,
#' a lone zero band to 1; abort when too much of the AOI is empty
#' @noRd
wayback_nodata <- function(x, target, clip, empty_max, label) {
  v <- terra::values(x, mat = TRUE)
  empty <- rowSums(v != 0, na.rm = TRUE) == 0
  inside <- if (clip) {
    !is.na(terra::values(terra::rasterize(terra::vect(target), x[[1]],
                                          touches = FALSE))[, 1])
  } else {
    rep(TRUE, nrow(v))
  }
  if (!any(inside)) {
    cli::cli_abort(
      "{.arg aoi} covers no cell centre at this {.arg res}.",
      class = "drift_wayback_empty"
    )
  }
  share <- mean(empty[inside])
  if (share > empty_max) {
    cli::cli_abort(
      c("{round(100 * share)}% of the AOI came back empty from {label}.",
        "i" = "The release has no imagery at this zoom there (missing tiles \\
               read as zeros). Try a shallower zoom or another release."),
      class = "drift_wayback_empty"
    )
  }
  v[v == 0] <- 1
  v[empty | !inside, ] <- NA
  terra::values(x) <- v
  x
}


#' @noRd
wayback_finish <- function(r) {
  names(r) <- c("red", "green", "blue")
  terra::RGB(r) <- 1:3
  r
}


#' The tiles' ground resolution at the AOI's latitude, to 0.05 m
#' @noRd
wayback_ground_res <- function(zoom, aoi) {
  lat <- sf::st_coordinates(suppressWarnings(
    sf::st_centroid(sf::st_union(sf::st_transform(aoi, 4326)))
  ))[1, "Y"]
  max(0.05, round(156543.03392 / 2^zoom * cos(lat * pi / 180) / 0.05) * 0.05)
}


#' @noRd
wayback_crs_check <- function(crs) {
  if (is.numeric(crs) && length(crs) == 1L) crs <- paste0("EPSG:", crs)
  if (!is.character(crs) || length(crs) != 1L || is.na(sf::st_crs(crs))) {
    cli::cli_abort("{.arg crs} must be one CRS, such as {.val EPSG:3005}.")
  }
  crs
}

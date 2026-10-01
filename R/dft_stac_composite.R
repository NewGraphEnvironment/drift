#' Fetch dated, cloud-masked reflectance composites from a STAC catalog
#'
#' Reference imagery for windows you choose. For each year, streams every scene
#' in the chosen calendar months, masks clouds per pixel, and reduces them to
#' one median composite of the requested bands. A true-colour composite of the
#' same season in different years, or of early against late season within one
#' year, says **when** a place changed. The Esri and Google basemaps in
#' [dft_map_interactive()] carry no capture date, so they cannot.
#'
#' This is the multi-band sibling of [dft_stac_cube()] and shares its read path:
#' the same STAC query (paginated, `intersects` the AOI, scene-level
#' `eo:cloud_cover` pre-filter), the same per-pixel mask, the same Sentinel-2
#' offset correction at the 2022-01-25 processing-baseline boundary, the same
#' tiling and the same AOI clip. Where the cube returns one index per month, this
#' returns the bands themselves, one time step per window.
#'
#' Values are **surface reflectance** (the source's `scale` and `offset`
#' applied), stored as floating point rather than display bytes. That keeps a
#' composite usable as data, for an index or as classifier input, and leaves
#' contrast stretching to display time. [dft_map_interactive()] applies one
#' shared stretch to every composite it is given, so a brightness difference
#' between years is a real one.
#'
#' @section Counting clear observations:
#' `aggregation = "count"` returns, instead of reflectance, the number of
#' **distinct clear days** per pixel in each window. That is the number a caller
#' needs to choose composite windows. It is read one day per time step, so
#' where adjacent MGRS tiles overlap, their two items of one acquisition count
#' once, and a masked tile does not hide a clear one from the same day. "Clear"
#' means not in `mask_values` (by default cloud, cloud shadow, cirrus **and
#' snow**, so a spring or autumn count excludes snow cover as well as cloud), and
#' only scenes passing `cloud_cover_max` are counted. The counts are whole
#' numbers with no scale or offset applied, stored as integers, one layer per
#' band. The mask is shared, so bands count alike and `bands = "red"` is enough.
#' A pixel with no clear day is `NA`, never 0, because gdalcubes cannot tell a
#' chunk it failed to read from one that was all cloud. For the same reason a
#' day whose read failed for part of a chunk goes uncounted there, so where
#' reads fail a count is a lower bound; gdalcubes reports such failures only on
#' the console, as a composite's are. A count is not refused
#' across the Sentinel-2 2022-01-25 offset change, which does not affect it.
#'
#' @section Caching:
#' Each year's composite is written once under [dft_cache_path()] as
#' `<source>/composite_<key>.tif`, a Cloud Optimized GeoTIFF; a count is written
#' as `<source>/count_<key>.tif` and keyed apart from every composite. The key hashes the
#' AOI geometry and every parameter that changes the pixels: bands (in order),
#' months, the year's window, resolution, CRS, aggregation, resampling, cloud
#' cover, mask values, reflectance scale and offset, `clip` and `tile_size`.
#' Because the file is a COG, it can be copied to object storage and served
#' through titiler unchanged, which is how a floodplain-wide composite reaches
#' [dft_map_interactive()]: `rgb` accepts COG URLs as well as rasters.
#'
#' @section Floodplain scale and per-point chips:
#' A composite over a whole floodplain streams the floodplain's bounding box
#' and produces a raster the size of it. When the purpose is reviewing sample
#' points, call this **once per buffered point** instead (see the examples).
#' Each chip is small, streams only the COG blocks under it, and is cached on
#' its own, so adding a point to the sample fetches one chip rather than
#' invalidating the rest. Passing all the points as one multi-feature `aoi`
#' does not do this: the output spans the points' combined bounding box, and
#' one cache entry covers every point.
#'
#' @section Windows and the Sentinel-2 offset boundary:
#' A window is one calendar year's run of `months`, so a winter window that
#' crosses the new year (December to February) cannot be expressed; `c(12, 1,
#' 2)` composites January, February and December of the **same** year, and the
#' label says so. Sentinel-2 changed its reflectance offset on 2022-01-25. A
#' window with scenes on both sides of that date cannot be reduced to one true
#' median, because gdalcubes aggregates before the per-side offset is applied,
#' so such a window is refused rather than returned as something that is not a
#' median. Only a January 2022 window can straddle it.
#'
#' @param aoi An `sf` polygon defining the area of interest. A multi-feature
#'   `aoi` is read as its union; for sample points, see the chips section.
#' @param years Integer vector of years. One composite is returned per year.
#' @param months Integer vector of calendar months (1-12) to composite (default
#'   `6:7`, June and July). Each year's window runs from the first day of the
#'   earliest month to the last day of the latest; scenes from months not listed
#'   are dropped, so `c(6, 8)` composites June and August and skips July.
#' @param bands Character vector of band **roles** from [dft_stac_config()]
#'   (default `c("red", "green", "blue")`, true colour). Any roles and any
#'   number of them; `c("nir", "red", "green")` is the standard vegetation false
#'   colour. Layers are named by role, in the order given.
#' @param source Character. A cube source name for [dft_stac_config()] (default
#'   `"sentinel-2-l2a"`).
#' @param res Numeric. Output pixel size in CRS units (default 10).
#' @param crs Character. Target CRS as an EPSG string. When `NULL`,
#'   auto-detected from the AOI centroid's UTM zone.
#' @param aggregation Character. How scenes within a window are reduced
#'   (default `"median"`): one of `"median"`, `"mean"`, `"min"`, `"max"`,
#'   `"first"` or `"last"`, or `"count"` for the number of clear days per pixel
#'   instead of reflectance (see the section on counting). Anything else is
#'   refused. gdalcubes reads a value it does not know as no aggregation at all
#'   and returns reflectance with no error, which is how `"count"` behaved in
#'   drift 0.18.0 to 0.19.2, so drift passes it only values measured to work.
#' @param resampling Character. Spatial resampling (default `"bilinear"`):
#'   one of `"near"`, `"bilinear"`, `"cubic"`, `"cubicspline"`,
#'   `"lanczos"`, `"average"`, `"mode"`, `"max"`, `"min"`, `"med"`, `"q1"` or
#'   `"q3"`. Anything else is refused: gdalcubes reads a value it does not know as
#'   `"near"`, with no error, so drift passes it only values measured to work.
#'   `"mean"` and `"median"` are refused too; use `"average"` and `"med"`.
#' @param clip Logical. Clip the output to the AOI polygon (default `FALSE`).
#'   Reference imagery is read around a place, not only inside it, so the
#'   default keeps the whole AOI bounding box. `TRUE` uses the same rule as
#'   [dft_stac_cube()]: every cell the polygon touches is kept.
#' @param cloud_cover_max Numeric. Scene-level `eo:cloud_cover` maximum percent
#'   (default 20, stricter than the cube's 60 because a composite of few clear
#'   scenes looks better than one of many cloudy ones).
#' @param mask_values Integer vector of mask-band classes to exclude. When
#'   `NULL`, taken from [dft_stac_config()]; for Sentinel-2 that is the SCL
#'   cloud, cloud-shadow, cirrus and **snow** classes, so snow cover is masked
#'   as well as cloud.
#' @param tile_size Numeric or `NULL` (default). Read-tiling edge length in CRS
#'   units; only tiles intersecting the AOI are streamed. A memory knob, not a
#'   speed one; see [dft_stac_cube()].
#' @param parallel Integer or `NULL`. gdalcubes worker processes; see
#'   [dft_stac_cube()].
#' @param cache_dir Character. Cache directory. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-fetch even if cached (default `FALSE`). The
#'   replacement is atomic.
#' @param sign_fn A signing function for STAC assets. Default is
#'   [rstac::sign_planetary_computer()].
#'
#' @return A named list of [terra::SpatRaster]s, one per year, each with one
#'   layer per band. Names label the window, e.g. `"2017 Jun–Jul"`, and
#'   become layer labels in [dft_map_interactive()]. Each raster's
#'   [terra::time()] is the window start. With `aggregation = "count"` each layer
#'   holds integer clear-day counts rather than reflectance. A year with no
#'   usable scenes (or, for a count, no clear day anywhere) is dropped with a
#'   warning; if every year is empty, the call aborts.
#'
#' @seealso [dft_map_interactive()] (`rgb =`) to display them,
#'   [dft_stac_cube()] for index time series.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
#'
#' # True colour, same season in two years
#' tc <- dft_stac_composite(aoi, years = c(2017, 2023), months = 6:7)
#' names(tc)
#' terra::plotRGB(tc[[1]], stretch = "lin")
#'
#' # Vegetation false colour, late season
#' fc <- dft_stac_composite(aoi, years = 2023, months = 8:9,
#'                          bands = c("nir", "red", "green"))
#'
#' # Chips around sample points: one small, separately cached composite each
#' pts <- sf::st_as_sf(sf::st_sample(aoi, 20))
#' buf <- sf::st_buffer(pts, 300)
#' chips <- lapply(seq_len(nrow(buf)), function(i) {
#'   dft_stac_composite(buf[i, ], years = c(2017, 2023))
#' })
#'
#' dft_map_interactive(rgb = c(tc, fc[1]), aoi = aoi)
#'
#' # How many clear days each July had, to choose a composite window
#' n <- dft_stac_composite(aoi, years = 2017:2023, months = 7, bands = "red",
#'                         aggregation = "count")
#' sapply(n, function(r) terra::global(r, "max", na.rm = TRUE)[[1]])
#' }
#'
#' @export
dft_stac_composite <- function(aoi,
                               years,
                               months = 6:7,
                               bands = c("red", "green", "blue"),
                               source = "sentinel-2-l2a",
                               res = 10,
                               crs = NULL,
                               aggregation = "median",
                               resampling = "bilinear",
                               clip = FALSE,
                               cloud_cover_max = 20,
                               mask_values = NULL,
                               tile_size = NULL,
                               parallel = NULL,
                               cache_dir = NULL,
                               force = FALSE,
                               sign_fn = rstac::sign_planetary_computer()) {
  check_gdalcubes("to fetch STAC composites")

  cfg <- dft_stac_config(source)
  if (!isTRUE(cfg$cube)) {
    cli::cli_abort(c(
      "Source {.val {source}} is not a cube source.",
      "i" = "Use {.fn dft_stac_fetch} for categorical rasters."
    ))
  }
  aggregation <- aggregation_check(aggregation,
                                   c(.cube_view_aggregations, "count"))
  resampling <- resampling_check(resampling)
  # matched without case, like every aggregation; the count family is new, so
  # normalising it moves no existing key
  is_count <- identical(tolower(aggregation), "count")
  if (is_count) aggregation <- "count"
  family <- if (is_count) "count" else "composite"
  years <- composite_years_check(years)
  months <- composite_months_check(months)
  band_assets <- composite_band_assets(bands, cfg$roles)

  mask_values <- mask_values %||% cfg$mask_values
  scale <- cfg$scale %||% 1
  offset <- cfg$offset %||% 0
  offset_before <- cfg$offset_before %||% 0
  clip <- isTRUE(as.logical(clip))
  if (!is.null(tile_size)) tile_size <- tile_size_check(tile_size, res)

  if (inherits(aoi, "SpatVector")) aoi <- sf::st_as_sf(aoi)
  stopifnot(inherits(aoi, c("sf", "sfc")))
  target_crs <- if (is.null(crs)) auto_utm_epsg(aoi) else crs
  aoi_wgs84 <- sf::st_transform(aoi, 4326)
  aoi_target <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))

  restore_session <- stac_cube_session(parallel)
  on.exit(restore_session(), add = TRUE)

  cache_source_dir <- cache_scheme_dir(cache_dir, source)
  dir.create(cache_source_dir, recursive = TRUE, showWarnings = FALSE)

  # Every band scaled to reflectance with the offset for the side of the
  # 2022-01-25 boundary the window's scenes fall on (a window straddling it is
  # refused by composite_offset_check()). A count applies neither: it counts
  # clear days, and the offset only moves values, not whether they are masked.
  pixel_fn <- if (is_count) {
    function(cube, offset_use) composite_count_cube(cube, band_assets, bands)
  } else {
    function(cube, offset_use) {
      exprs <- vapply(band_assets, scale_token, character(1),
                      scale = scale, offset = offset_use, USE.NAMES = FALSE)
      gdalcubes::apply_pixel(cube, exprs, names = bands)
    }
  }

  out <- lapply(years, function(year) {
    w <- composite_window(year, months)
    label <- composite_label(year, months)
    # A count is read one day per time step (see composite_count_cube()), so
    # that is the step it reads with and the step it keys on.
    dt_read <- if (is_count) "P1D" else w$dt
    cache_key <- stac_composite_cache_key(
      aoi_target, res, target_crs, w$datetime, dt_read, aggregation, resampling,
      cfg$stac_url, cfg$collection, band_assets, bands, cloud_cover_max,
      mask_values, scale, offset, offset_before, months, clip, tile_size,
      family = family
    )
    cache_file <- file.path(cache_source_dir,
                            paste0(family, "_", cache_key, ".tif"))

    if (!force && file.exists(cache_file) &&
          cache_hit_ok(cache_file, family)) {
      r <- stac_cube_cache_read(cache_file, cfg$collection, w$datetime,
                                label = family)
      if (!is.null(r)) {
        message("  ", family, " ", label, ": cached")
        return(composite_finish(r, bands, w$t0))
      }
    }

    build <- function() {
      fetched <- stac_cube_items(cfg, aoi_wgs84, w$query, cloud_cover_max,
                                 months, sign_fn)
      if (is_count) {
        # No offset split. stac_cube_assemble() coalesces the two sides with
        # terra::cover(pre, post), which keeps the pre-side count wherever it is
        # not NA and so would drop every post-side day. The offset does not
        # change which pixels are masked, so one pass counts the window whole.
        fetched$is_pre[] <- FALSE
      } else {
        composite_offset_check(fetched$is_pre, label, cfg$offset_boundary)
      }
      stk <- stac_cube_assemble(
        fetched, cfg, aoi_target, target_crs, t0 = w$t0, t1 = w$t1, res = res,
        dt = dt_read,
        # "count" is not a cube_view aggregation: gdalcubes would read it as
        # "none" and return reflectance (#92). Within a day, "first" skips
        # masked (NaN) items, so a clear tile is not blanked by a cloudy one.
        aggregation = if (is_count) "first" else aggregation,
        resampling = resampling,
        band_assets = band_assets, mask_values = mask_values,
        offset = offset, offset_before = offset_before, pixel_fn = pixel_fn,
        tile_size = tile_size
      )
      stk <- composite_layers_order(stk, bands, label, w)
      if (is_count) stk <- count_zero_na(stk)
      if (isTRUE(clip)) stk <- stac_cube_clip(stk, aoi_target)
      cube_check_nonempty(stk, cfg$collection, w$datetime, cached = FALSE)
      # Names, and NO time, before the write. The stack arrives carrying a time
      # read from the gdalcubes NetCDF, and a raster with a time makes terra's
      # COG writer emit a `.aux.json` sidecar: an extra file beside a COG that is
      # meant to be publishable on its own. The time is stamped on the re-read
      # below, as it is on a cache hit.
      names(stk) <- bands
      terra::time(stk) <- NULL
      # A count is a whole number of days, stored as one; its overviews take
      # the nearest cell rather than an average, which would not be a count.
      cache_write_atomic(cache_file, function(path) {
        terra::writeRaster(
          stk, path, filetype = "COG",
          datatype = if (is_count) "INT2U" else "FLT4S", overwrite = TRUE,
          gdal = c("COMPRESS=DEFLATE", "PREDICTOR=YES", "BLOCKSIZE=512",
                   paste0("OVERVIEW_RESAMPLING=",
                          if (is_count) "NEAREST" else "AVERAGE"))
        )
      })
      # Return what was cached, not the in-memory double stack: the file is
      # Float32, so returning `stk` would make the first call differ from every
      # later cache hit in the eighth significant figure.
      composite_finish(terra::rast(cache_file), bands, w$t0)
    }
    # An empty or fully clouded year is a result, not a failure: warn and drop
    # it, keeping the years already built (and cached) before it.
    tryCatch(
      build(),
      drift_no_items = function(e) composite_skip(label, "no scenes"),
      drift_empty_cube = function(e) composite_skip(label, "no clear pixels")
    )
  })
  names(out) <- vapply(years, composite_label, character(1), months = months)
  out <- out[!vapply(out, is.null, logical(1))]
  if (!length(out)) {
    cli::cli_abort(c(
      "No year produced a composite.",
      "i" = "Every window had no scenes or no clear pixels; try more \\
             {.arg months} or a higher {.arg cloud_cover_max}."
    ))
  }
  out
}


#' Count the clear days per pixel in a daily masked cube, one layer per band
#'
#' `cube` is the masked `raster_cube()` over a window at `dt = "P1D"`, so each
#' time step is one day and same-day items (overlapping MGRS tiles) have already
#' been reduced to one value. `count()` counts the non-NaN, i.e. unmasked, days.
#' The built-in string reducer runs in C++, so the reduce_time() closure trap in
#' inst/notes/gdalcubes-pc-gotchas.md does not apply. `names = bands` gives the
#' layers their role names, which composite_layers_order() requires. The window
#' always spans more than one day, which matters: reduce_time() passes a
#' single-step cube through unchanged.
#' @noRd
composite_count_cube <- function(cube, band_assets, bands) {
  gdalcubes::reduce_time(cube, paste0("count(", band_assets, ")"),
                         names = bands)
}


#' A pixel with no clear day is NA, never 0
#'
#' gdalcubes returns such a pixel as 0 when its chunk holds a clear pixel
#' somewhere and as NaN when the whole chunk is empty, and the chunk size follows
#' `parallel`. Measured on a 128 x 128 fixture: 12,544 zeros at 256 px chunks,
#' 4,352 zeros and 8,192 NaN at 64 px. Mapping 0 to NA makes the output the same
#' at every chunking, so `parallel` stays a cost-only setting. It is NA rather
#' than 0 because a chunk that failed to read is NaN as well, and a failed read
#' must not be published as a count of zero clear days.
#' @noRd
count_zero_na <- function(stk) {
  terra::classify(stk, cbind(0, NA))
}


#' Warn that a year was dropped, and return NULL for it
#' @noRd
composite_skip <- function(label, why) {
  cli::cli_warn("Skipping the {label} composite: {why}.")
  NULL
}


#' Refuse a window whose scenes straddle the reflectance-offset boundary
#'
#' gdalcubes reduces scenes to the median BEFORE the pixel function applies the
#' offset, so the two sides cannot be pooled into one median. The cube handles
#' this with terra::cover(pre, post), which for a composite window would return
#' the pre-boundary median wherever it has data, not a median of the window.
#' Refusing is honest; only a January 2022 window can reach it.
#' @noRd
composite_offset_check <- function(is_pre, label, boundary) {
  if (any(is_pre) && !all(is_pre)) {
    cli::cli_abort(c(
      "The {label} window has scenes on both sides of the {boundary} \\
       reflectance-offset change, so it has no single median.",
      "i" = "Choose months that do not include January of that year."
    ), class = "drift_composite_offset_split")
  }
  invisible(TRUE)
}


#' Put a composite's layers in band order, by name, checking there is one per band
#'
#' terra reads a multi-variable gdalcubes NetCDF with its variables in
#' ALPHABETICAL order (measured: `blue`, `green`, `red` for a true-colour
#' request), so renaming the layers by position would silently swap red and
#' blue. Layers are therefore selected by name. A window and `dt` that disagree
#' would give more than one time step, which is refused too.
#' @noRd
composite_layers_order <- function(stk, bands, label, w) {
  if (terra::nlyr(stk) != length(bands)) {
    cli::cli_abort(c(
      "The {label} composite has {terra::nlyr(stk)} layer{?s}; expected \\
       {length(bands)} (one per band).",
      "i" = "Window {.val {w$datetime}} with {.code dt = {w$dt}} should be \\
             a single time step."
    ))
  }
  idx <- match(bands, names(stk))
  if (anyNA(idx)) {
    cli::cli_abort(c(
      "The {label} composite's layers do not match its bands.",
      "x" = "Layers: {.val {names(stk)}}; bands: {.val {bands}}."
    ))
  }
  stk[[idx]]
}

#' Name a composite's layers by band role and stamp the window start
#' @noRd
composite_finish <- function(r, bands, t0) {
  names(r) <- bands
  terra::time(r) <- rep(as.Date(t0), terra::nlyr(r))
  r
}


#' Validate `years`: non-empty whole numbers, no NA
#' @noRd
composite_years_check <- function(years) {
  if (!is.numeric(years) || length(years) == 0L || anyNA(years) ||
        any(years != trunc(years))) {
    cli::cli_abort(c(
      "{.arg years} must be one or more whole-number years.",
      "x" = "Got {.obj_type_friendly {years}}."
    ))
  }
  as.integer(years)
}


#' Validate `months`: non-empty whole numbers in 1-12; returned sorted, unique
#' @noRd
composite_months_check <- function(months) {
  if (!is.numeric(months) || length(months) == 0L || anyNA(months) ||
        any(months != trunc(months)) || any(months < 1 | months > 12)) {
    cli::cli_abort(c(
      "{.arg months} must be one or more calendar months, whole numbers 1-12.",
      "x" = "Got {.obj_type_friendly {months}}."
    ))
  }
  sort(unique(as.integer(months)))
}


#' Resolve band roles to asset names, erroring on a role the source lacks
#'
#' The mask role is not a band and is refused, as is a repeated role (two layers
#' with one name).
#' @noRd
composite_band_assets <- function(bands, roles) {
  available <- setdiff(names(roles), "mask")
  if (!is.character(bands) || length(bands) == 0L || anyNA(bands) ||
        anyDuplicated(bands)) {
    cli::cli_abort(c(
      "{.arg bands} must be one or more distinct band roles.",
      "i" = "Available roles: {.val {available}}."
    ))
  }
  unknown <- setdiff(bands, available)
  if (length(unknown)) {
    cli::cli_abort(c(
      "Unknown band role{?s} {.val {unknown}}.",
      "i" = "Available roles: {.val {available}}."
    ))
  }
  unlist(roles[bands], use.names = FALSE)
}


#' One year's composite window: first day of the first month to the last day of
#' the last, as one `dt` step
#' @noRd
composite_window <- function(year, months) {
  first <- min(months)
  last <- max(months)
  t0 <- as.Date(sprintf("%04d-%02d-01", year, first))
  # last day of the last month: the day before the 1st of the month after it
  t1 <- seq(as.Date(sprintf("%04d-%02d-01", year, last)),
            by = "month", length.out = 2L)[2L] - 1L
  list(
    t0 = format(t0), t1 = format(t1),
    datetime = paste0(format(t0), "/", format(t1)),
    # The STAC query needs explicit times: a date-only end bound is read as
    # 00:00Z and drops the last day's scenes (measured: a window ending on a
    # scene day returned 22 of 23 items), which in BC are acquired ~19:00Z.
    query = paste0(format(t0), "T00:00:00Z/", format(t1), "T23:59:59Z"),
    dt = sprintf("P%dM", last - first + 1L)
  )
}


#' Label a composite window, e.g. "2017 Jun-Jul" with an en dash
#'
#' A contiguous run of months is a range, a single month is itself, and a gap
#' lists the months, so the label never claims a month that was not composited.
#' @noRd
composite_label <- function(year, months) {
  months <- sort(unique(months))
  abb <- month.abb[months]
  span <- if (length(months) == 1L) {
    abb
  } else if (all(diff(months) == 1L)) {
    paste0(abb[1L], "\u2013", abb[length(abb)])
  } else {
    paste(abb, collapse = ", ")
  }
  paste(year, span)
}


#' Cache key for one composite
#'
#' Its own function rather than a reuse of stac_cube_cache_key(), whose legacy
#' shape is frozen. The leading tag keeps the families apart even if their
#' parameter lists ever coincide; the filename prefix already does, and this
#' makes it true of the hash as well. Bands and their assets are
#' order-sensitive (they are the layer order); months and mask values are not.
#'
#' `family = "count"` is the clear-observation count (#92). It keys apart from
#' every composite, and in particular from the 0.18.0-0.19.2 `composite_<key>.tif`
#' files written under `aggregation = "count"`, which hold reflectance: the
#' tag, and the `P1D` read step the caller passes, both change the hash. The
#' default keeps every existing composite key unchanged.
#' @noRd
stac_composite_cache_key <- function(aoi_target, res, target_crs, datetime, dt,
                                     aggregation, resampling, stac_url,
                                     collection, band_assets, bands,
                                     cloud_cover_max, mask_values, scale,
                                     offset, offset_before, months, clip,
                                     tile_size = NULL, family = "composite") {
  geom_wkb <- sf::st_as_binary(sf::st_geometry(aoi_target), endian = "little")
  parts <- list(
    family, geom_wkb, as.numeric(res), target_crs, datetime, dt,
    aggregation, resampling, stac_url, collection, band_assets, bands,
    as.numeric(cloud_cover_max), sort(as.numeric(mask_values)),
    as.numeric(scale), as.numeric(offset), as.numeric(offset_before),
    sort(as.numeric(months)), as.logical(clip),
    if (is.null(tile_size)) NA_real_ else as.numeric(tile_size)
  )
  cache_key_hash(parts)
}

#' Fetch STAC-hosted rasters via gdalcubes
#'
#' Query a STAC catalog, build a gdalcubes image collection, and extract
#' per-year rasters cropped and masked to the AOI. Works with any STAC
#' collection hosting single-band classified rasters (IO LULC, ESA WorldCover,
#' custom COGs).
#'
#' Fetched rasters are cached under [dft_cache_path()] as
#' `v2/<source>/<year>_<key>.nc` (or `.tif` when `tile_size` is set — see below),
#' where `key` is a hash of the AOI geometry and every fetch parameter that
#' affects the output (`res`, `crs`, `dt`, `aggregation`, `resampling`,
#' `stac_url`, `collection`, `asset`, and `tile_size`). Repeat calls with the
#' same AOI and parameters reuse the cache; changing any of them re-fetches.
#'
#' Entries are **published atomically** — written to a temp file in the same
#' directory and renamed into place only after a complete, validated write — so
#' an interrupted fetch cannot leave a partial file under the canonical name for
#' a later run to trust. A cached entry is also **validated before it is
#' served**: it must open as a raster, be sanely georeferenced, and return its
#' pixels without a read error. An entry that fails is re-fetched with a warning
#' rather than served or left for the user to delete by hand.
#'
#' The read check samples rather than proves — it reads one row, so interior
#' damage that leaves the file structurally walkable can pass it. The guarantee
#' against partial entries is the atomic write, not the check.
#'
#' The key is a function of **content alone** (#48), so the same AOI and
#' parameters produce the same filename on any machine, R version, rlang version
#' and architecture — a cache can be copied between machines and stay valid. The
#' leading `v2` is the cache-scheme generation: a deliberate key change moves it,
#' leaving older entries findable rather than silently orphaned. See
#' [dft_cache_info()] and [dft_cache_clear()] for reporting and reclaiming them.
#'
#' Note `sf::st_as_binary()` honours `sf::st_precision()`, so setting a precision
#' on the AOI changes its WKB and therefore the key. That has always been true.
#'
#' @param aoi An `sf` polygon defining the area of interest.
#' @param source Character. A known source name passed to [dft_stac_config()].
#'   Ignored when `stac_url`, `collection`, and `asset` are all provided.
#' @param years Integer vector of years to fetch. When `NULL`, uses
#'   `available_years` from [dft_stac_config()].
#' @param stac_url Character. STAC API endpoint URL. Overrides `source`.
#' @param collection Character. STAC collection ID. Overrides `source`.
#' @param asset Character. Asset name within each STAC item. Overrides `source`.
#' @param res Numeric. Output pixel size in CRS units (default 10).
#' @param crs Character. Target CRS as an EPSG string (e.g. `"EPSG:32609"`).
#'   When `NULL`, auto-detected from the AOI centroid's UTM zone.
#' @param dt Character. ISO 8601 duration for the temporal aggregation window
#'   (default `"P1Y"`).
#' @param aggregation Character. Temporal aggregation method (default
#'   `"first"`). Use `"median"` for multi-scene composites.
#' @param resampling Character. Spatial resampling method (default `"near"`
#'   for categorical data).
#' @param tile_size Numeric or `NULL` (default). Edge length, in CRS units
#'   (metres for the default UTM CRS), of the download-tiling grid. When `NULL`,
#'   one cube is streamed over the whole AOI bounding box (the download scales
#'   with the bbox, not the AOI). When set, the bbox is split into a grid of
#'   `tile_size`-square tiles and only tiles that intersect the AOI polygon are
#'   streamed, then mosaicked — so a thin, diagonal AOI (e.g. a floodplain
#'   corridor) fetches close to its footprint instead of its full bounding box.
#'   Snapped to a multiple of `res`. Smaller tiles waste less bbox but cost more
#'   per-tile round trips; there is no auto-tuning. Tiled fetches cache a terra
#'   GeoTIFF (`.tif`) rather than a gdalcubes NetCDF (`.nc`).
#' @param cache_dir Character. Cache directory path. When `NULL`, uses
#'   [dft_cache_path()].
#' @param force Logical. Re-fetch even if cached, replacing the cached file
#'   (default `FALSE`). The replacement is atomic, so a raster returned by an
#'   earlier call keeps reading the entry it was opened against rather than
#'   picking up half-rewritten contents, and an interrupted forced re-fetch
#'   leaves the previous entry intact.
#' @param sign_fn A signing function for STAC assets. Default is
#'   [rstac::sign_planetary_computer()].
#'
#' @return A named list of [terra::SpatRaster] objects, one per year. The STAC
#'   items are attached as `attr(, "stac_items")` for use with
#'   [dft_stac_classes()] — paged to exhaustion, with the (stale) `next` link
#'   stripped so a caller re-running [rstac::items_fetch()] on them cannot
#'   silently duplicate features. The cache key is attached as
#'   `attr(, "cache_key")` so a caller can record which cache entry served the
#'   fetch; it is **per call, not per year** — cached files are named
#'   `<year>_<cache_key>`, so one key covers every year the call returned. Its
#'   format changed in 0.12.0 (#48): 16 lowercase hex characters, from
#'   `digest::digest(algo = "xxhash64")` over a canonical string, where it was
#'   previously 12 from `rlang::hash()`.
#' @export
dft_stac_fetch <- function(aoi,
                           source = "io-lulc",
                           years = NULL,
                           stac_url = NULL,
                           collection = NULL,
                           asset = NULL,
                           res = 10,
                           crs = NULL,
                           dt = "P1Y",
                           aggregation = "first",
                           resampling = "near",
                           tile_size = NULL,
                           cache_dir = NULL,
                           force = FALSE,
                           sign_fn = rstac::sign_planetary_computer()) {
  rlang::check_installed("gdalcubes", reason = "to fetch STAC rasters")

  # Normalize tile_size ONCE so the path gate (is.null) and the cache key derive
  # from the same snapped scalar. When tiling, tune GDAL for the many extra
  # per-item COG opens (restored on exit so the caller's session is untouched).
  if (!is.null(tile_size)) {
    tile_size <- tile_size_check(tile_size, res)
    gdal_cfg <- c(
      GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR",
      GDAL_HTTP_MULTIPLEX = "YES",
      GDAL_HTTP_VERSION = "2",
      VSI_CACHE = "TRUE",
      CPL_VSIL_CURL_ALLOWED_EXTENSIONS = ".tif"
    )
    old_cfg <- Sys.getenv(names(gdal_cfg), unset = NA)
    do.call(Sys.setenv, as.list(gdal_cfg))
    on.exit({
      set_again <- old_cfg[!is.na(old_cfg)]
      if (length(set_again)) do.call(Sys.setenv, as.list(set_again))
      unset <- names(old_cfg)[is.na(old_cfg)]
      if (length(unset)) Sys.unsetenv(unset)
    }, add = TRUE)
  }

  # Resolve config
  if (is.null(stac_url) || is.null(collection) || is.null(asset)) {
    cfg <- dft_stac_config(source)
    if (isTRUE(cfg$cube)) {
      cli::cli_abort(c(
        "Source {.val {source}} is a cube source, not a categorical raster.",
        "i" = "Use {.fn dft_stac_cube} for continuous index-trajectory sources."
      ))
    }
    stac_url <- stac_url %||% cfg$stac_url
    collection <- collection %||% cfg$collection
    asset <- asset %||% cfg$asset
    if (is.null(years)) years <- cfg$available_years
  }
  stopifnot(!is.null(years), length(years) > 0)

  # Ensure aoi is sf

  if (inherits(aoi, "SpatVector")) aoi <- sf::st_as_sf(aoi)
  stopifnot(inherits(aoi, c("sf", "sfc")))

  # Resolve CRS
  target_crs <- if (is.null(crs)) auto_utm_epsg(aoi) else crs

  # AOI in WGS84 for STAC query
  aoi_wgs84 <- sf::st_transform(aoi, 4326)
  bbox_query <- as.numeric(sf::st_bbox(aoi_wgs84))

  # AOI in target CRS for cube extent and masking
  aoi_target <- sf::st_transform(aoi, as.integer(gsub("EPSG:", "", target_crs)))
  bbox_target <- sf::st_bbox(aoi_target)

  # STAC query, paged to exhaustion (#51)
  message("Querying STAC: ", collection, " (", min(years), "-", max(years), ")...")
  items <- stac_items_paged(
    stac_url = stac_url,
    collection = collection,
    bbox = bbox_query,
    datetime = paste0(min(years), "-01-01/", max(years), "-12-31"),
    sign_fn = sign_fn
  )

  n_items <- length(items$features)
  message("  ", n_items, " items returned")
  if (n_items == 0) stop("No STAC items found for ", collection)

  # Build gdalcubes image collection
  col <- gdalcubes::stac_image_collection(items$features, asset_names = asset)

  # Cache setup
  source_label <- if (!is.null(source)) source else "custom"
  # <base>/<scheme>/<source> (#48). recursive = TRUE is required, not tidiness:
  # the scheme segment adds a level, and cache_write_atomic() renames its temp
  # (and any GDAL sidecar) within this directory, so a missing parent aborts the
  # very first fetch.
  cache_source_dir <- cache_scheme_dir(cache_dir, source_label)
  dir.create(cache_source_dir, recursive = TRUE, showWarnings = FALSE)
  cache_key <- stac_cache_key(
    aoi_target, res, target_crs, dt, aggregation, resampling,
    stac_url, collection, asset, tile_size = tile_size
  )

  # A tiled fetch mosaics per-tile cubes with terra and caches a GeoTIFF; an
  # untiled fetch writes a single gdalcubes NetCDF. The grid and full-bbox extent
  # are constant across years, so build them once.
  ext_out <- if (is.null(tile_size)) "nc" else "tif"
  bbox_ext <- list(
    left = bbox_target[["xmin"]], right = bbox_target[["xmax"]],
    bottom = bbox_target[["ymin"]], top = bbox_target[["ymax"]]
  )
  tiles <- if (is.null(tile_size)) NULL else tile_grid(aoi_target, tile_size, res)

  # Fetch per year
  result <- lapply(years, function(yr) {
    cache_file <- file.path(cache_source_dir,
                            paste0(yr, "_", cache_key, ".", ext_out))
    t0 <- paste0(yr, "-01-01")
    t1 <- paste0(yr, "-12-31")

    # Presence is no longer trust (#41): a cached file must also be readable,
    # sanely georeferenced, and able to return its pixels. `force` short-circuits
    # first — the file is about to be replaced, so validating it is pure cost,
    # and a validation abort would break `force = TRUE` exactly when the cache is
    # broken, which is the documented recovery lever.
    if (!force && file.exists(cache_file) && cache_hit_ok(cache_file, yr)) {
      message("  ", yr, ": cached")
    } else if (is.null(tile_size)) {
      message("  ", yr, ": fetching...")
      cache_write_atomic(cache_file, function(out) {
        fetch_extent_to(col, bbox_ext, t0, t1, target_crs, res, dt,
                        aggregation, resampling, out)
      })
    } else {
      message("  ", yr, ": fetching ", length(tiles), " tile(s)...")
      tile_files <- vapply(seq_along(tiles), function(i) {
        fetch_extent_to(col, tiles[[i]], t0, t1, target_crs, res, dt,
                        aggregation, resampling,
                        tempfile(sprintf("drift_tile%d_", i), fileext = ".nc"))
      }, character(1))
      # on.exit, not a trailing unlink(): a mosaic_tiles() error would otherwise
      # strand every tile file for the life of the session.
      on.exit(unlink(tile_files), add = TRUE)
      cache_write_atomic(cache_file, function(out) mosaic_tiles(tile_files, out))
    }

    terra::mask(terra::rast(cache_file), terra::vect(aoi_target))
  })

  names(result) <- as.character(years)
  attr(result, "stac_items") <- items
  attr(result, "cache_key") <- cache_key
  result
}


#' Query STAC and page to exhaustion, then sign
#'
#' `rstac::get_request()` returns ONE page. Handing that to
#' [gdalcubes::stac_image_collection()] builds the cube from a partial item set,
#' so a wide AOI silently yields a raster with missing tiles (#51). This pages
#' with [rstac::items_fetch()] before signing.
#'
#' **Order matters.** Signing must come after paging: [rstac::items_sign()]
#' rewrites asset hrefs, so signing first leaves every item from page 2 onward
#' unsigned.
#'
#' **GET, not POST.** [dft_stac_cube()] posts because `ext_filter()` (CQL2)
#' requires it and because its `intersects` carries a whole polygon; neither
#' applies here, where the query is a bbox with no filter. Revisit if this
#' function ever gains `intersects` or a property filter.
#'
#' **No guard on a surviving `next` link**, which is what the obvious
#' implementation would do. `rstac:::items_fetch.doc_items` mutates only
#' `items$features` and never `items$links`, so a fully-paged collection still
#' carries page 1's `next`. Erroring on it would abort every correctly-paged
#' fetch. The link is stale rather than meaningful, so it is stripped before
#' returning — otherwise a caller who runs `items_fetch()` on
#' `attr(, "stac_items")` re-fetches pages 2..N into an already-complete feature
#' list and silently duplicates them.
#'
#' Two completeness checks, deliberately of different reach:
#' * `items_matched()` vs the item count — fires only where the API reports a
#'   total. Planetary Computer reports none, so **this never executes against
#'   PC**; it is fixtured in the tests rather than left as dead code.
#' * duplicate item ids — never skipped, and the only completeness signal
#'   available on PC. [gdalcubes::stac_image_collection()] drops duplicates
#'   behind a debug-only message, so nothing downstream would ever report them.
#'
#' `limit` is a round-trip reducer, not the fix: it sets the page size, and PC
#' clamps it to its own cap regardless. `items_fetch()` is what makes the result
#' complete.
#' @noRd
stac_items_paged <- function(stac_url, collection, bbox, datetime, sign_fn,
                             limit = 500) {
  items <- rstac::stac(stac_url) |>
    rstac::stac_search(
      collections = collection,
      bbox = bbox,
      datetime = datetime,
      limit = limit
    ) |>
    rstac::get_request() |>
    rstac::items_fetch()

  n_items <- length(items$features)

  matched <- rstac::items_matched(items)
  # length(), not is.null(). NULL is the reachable case here (PC sends no
  # numberMatched); the length() form additionally covers a zero-length or
  # multi-element value, because `&&` on a non-scalar is an ERROR in R >= 4.2 —
  # the guard would abort the fetch it exists to protect. Being precise about
  # reach: this call site passes no `matched_field`, so items_matched() only
  # ever reads `search:metadata$matched`, `context$matched` or `numberMatched`
  # off the document, and a server is free to put anything in those.
  #
  # ASYMMETRIC on purpose. Fewer items than reported is the truncation #51 is
  # about, so it aborts. MORE is not: this function is documented as generic
  # ("any STAC collection hosting single-band classified rasters"), and a
  # pgstac/stac-fastapi catalogue can return an ESTIMATED `numberMatched` above
  # a row threshold rather than an exact count — against which a complete fetch
  # would abort. Warning there keeps a real signal without failing toward abort
  # on a healthy result. (Not verified against a live pgstac instance; the
  # asymmetry is chosen so it does not matter which way that lands.)
  if (length(matched) == 1L && !is.na(matched) && n_items != matched) {
    if (n_items < matched) {
      cli::cli_abort(c(
        "STAC paging returned {n_items} item{?s} but the API reports {matched}.",
        "i" = "The item set is incomplete; the raster would be missing tiles."
      ))
    }
    cli::cli_warn(c(
      "STAC paging returned {n_items} item{?s}, more than the {matched} the \\
       API reports.",
      "i" = "Treated as an estimated count, not truncation — the item set is \\
             complete. Proceeding."
    ))
  }

  ids <- vapply(
    items$features,
    function(f) if (length(f$id) == 1L) as.character(f$id) else NA_character_,
    character(1)
  )
  # Missing ids are their own diagnosis, checked FIRST. Folding them into the
  # duplicate check reports two id-less items as "duplicate id: NA / pages
  # overlapped", which names the wrong cause: the items are malformed and the
  # pages did not overlap. STAC requires `id`, so this is a bad response.
  if (anyNA(ids)) {
    cli::cli_abort(c(
      "STAC returned {sum(is.na(ids))} item{?s} with no usable {.field id}.",
      "i" = "Every STAC item must carry a scalar {.field id}; this response \\
             is malformed, and duplicate detection cannot run without one."
    ))
  }
  if (anyDuplicated(ids) > 0L) {
    dup <- unique(ids[duplicated(ids)])
    cli::cli_abort(c(
      "STAC paging returned duplicate item id{?s}: {.val {dup}}.",
      "i" = "Pages overlapped — the item set cannot be trusted."
    ))
  }

  # A case-VARIANT `next` is a different problem and must not be stripped.
  # `rstac:::items_next.doc_items` selects with `links(items, rel == "next")`,
  # which is case-sensitive (measured: next -> 1, NEXT -> 0, Next -> 0). So a
  # `NEXT` link is inert to items_fetch() — it cannot cause the re-paging
  # duplicate this strip exists to prevent. What it means instead is that rstac
  # could not follow it and STOPPED AFTER PAGE ONE, i.e. exactly the #51
  # truncation, with `items_matched()` NULL on PC and duplicate-ids unable to
  # see it. That surviving link is then the last local trace, so deleting it
  # would destroy the only evidence. Warn and keep.
  is_odd_next <- function(l) {
    is.character(l$rel) && length(l$rel) == 1L &&
      tolower(l$rel) == "next" && !identical(l$rel, "next")
  }
  odd <- Filter(is_odd_next, items$links)
  if (length(odd)) {
    cli::cli_warn(c(
      "STAC returned a {.val {odd[[1]]$rel}} link, which {.pkg rstac} matches \\
       case-sensitively and therefore did not follow.",
      "!" = "The item set may be truncated. The link is left attached to \\
             {.code attr(, \"stac_items\")} as evidence."
    ))
  }

  # Drop the stale `next` (see above) before it reaches callers via
  # `attr(result, "stac_items")`. Matched EXACTLY as rstac matches it, so this
  # removes precisely the links that were followed and nothing else. A link
  # with no `rel` is kept — only `next` is being removed.
  items$links <- Filter(function(l) !identical(l$rel, "next"), items$links)

  rstac::items_sign(items, sign_fn = sign_fn)
}


#' Cache key for one STAC fetch parameter set
#'
#' Hashes everything that changes the written raster except year, which stays
#' as the readable filename prefix (all years of one call share a key). The
#' geometry is hashed as WKB so sf attribute columns and PROJ-version CRS
#' representation differences can't change the key; the CRS enters separately
#' as `target_crs`. `res` is coerced to double so `10L` and `10` key alike.
#' Callers must pass post-resolution `stac_url`/`collection`/`asset`, never
#' the raw possibly-NULL arguments. `tile_size` (the download-tiling grid, #36)
#' is appended to the hash ONLY when non-NULL, so a tiled fetch keys distinctly
#' from an untiled one. It must arrive already snapped by the caller.
#'
#' The parts list also carries a constant salt (#51) — see the comment in the
#' body. **Untiled keys moved once, deliberately, at v0.10.0**, so the earlier
#' claim that an untiled fetch keeps its legacy hash and that existing caches
#' stay valid no longer holds: they rebuild once, on purpose, because the key
#' is what stops a raster built from a truncated item set being served forever.
#'
#' `limit` (the STAC page size, `stac_items_paged()`) is deliberately NOT
#' hashed. It changes only where page boundaries fall, not the item set: the
#' network test asserts the *identical ordered* item ids at `limit = 1` and
#' `limit = 500`, so on Planetary Computer the ordering is limit-independent
#' and `limit` is not output-affecting. If `limit` is ever exposed as a
#' user-facing argument, re-derive that before trusting it — two calls
#' differing only in `limit` would otherwise key identically.
#' @noRd
stac_cache_key <- function(aoi_target, res, target_crs, dt, aggregation,
                           resampling, stac_url, collection, asset,
                           tile_size = NULL) {
  geom_wkb <- sf::st_as_binary(sf::st_geometry(aoi_target), endian = "little")
  parts <- list(
    geom_wkb, as.numeric(res), target_crs, dt, aggregation,
    resampling, stac_url, collection, asset,
    # Deliberate cache-format break (#51). Every key parameter above is
    # unchanged by the paging fix, so without this salt a raster written from a
    # TRUNCATED item set keeps being served by the file.exists() short-circuit —
    # and the users the bug hit hardest (wide AOIs) get no fix at all on
    # upgrade, silently and permanently under `force = FALSE`. Bumping the salt
    # costs a one-time re-fetch of small annual rasters. Do not remove it; to
    # invalidate again, change the string rather than adding another element.
    "items-paged-v2"
  )
  # A tiled fetch caches a terra .tif mosaic; an untiled fetch caches a
  # gdalcubes .nc. Keying them apart stops one being served as the other.
  if (!is.null(tile_size)) parts <- c(parts, list(as.numeric(tile_size)))
  cache_key_hash(parts)
}


#' Hash a key parts list to a stable cache key
#'
#' The one place a cache key is produced. Canonicalizes to a single string, then
#' hashes **that string's bytes** — so the key is a function of content alone,
#' not of any library's traversal of an R object.
#'
#' **This replaced `rlang::hash()` for a measured reason (#48).** rlang 1.3.0
#' rewrote `hash()` and says so in its own NEWS: *"with this version all hash
#' values will now be different… you should assume it's always possible for a
#' new version to invalidate existing hashes."* Because the key **is** the cache
#' filename, that made every rlang upgrade a silent, cache-wide re-download with
#' no error and no log line. `digest` is a categorically different bet: it
#' implements **published** algorithms and pins this exact call shape to the
#' upstream XXH64 reference vector in its own test suite
#' (`digest("abc", algo = "xxhash64", serialize = FALSE)` is `44bc2cf5ad770999`,
#' asserted in `inst/tinytest/test_digest.R`), so a change in its output would be
#' a bug rather than a design decision. drift pins that same vector as a control.
#'
#' `serialize = FALSE` is load-bearing: it hashes the string directly, keeping
#' R's serializer out of the path entirely. Never set it to `TRUE`.
#'
#' The full 16 characters are kept rather than the legacy 12 (#48). A key
#' collision does not crash — it silently serves the **wrong raster**, and
#' nothing downstream can detect that. 12 hex chars is 48 bits; keeping all 64
#' costs four characters of filename and buys a 65,536x margin.
#' @noRd
cache_key_hash <- function(parts) {
  s <- cache_key_string(parts)
  # digest(serialize = FALSE) takes only the FIRST element of a character
  # vector, silently and with no warning: digest(c("a","b")) == digest("a").
  # A length > 1 here would collapse every key to the hash of its first member —
  # a total collision, not a probabilistic one. Cheapest possible guard.
  stopifnot(is.character(s), length(s) == 1L, !is.na(s))
  digest::digest(s, algo = "xxhash64", serialize = FALSE)
}


#' Render a key parts list to one canonical string
#'
#' Every member becomes `<type-tag>:<value>`, members joined on `\x1f` and vector
#' elements on `\x1e`. Control characters cannot occur in the real values (hex,
#' numbers, URLs, enum strings), which is what keeps the separators unambiguous.
#'
#' **Type tags are not decoration.** Without them a plain string scheme collides
#' `NULL` with the literal `"<none>"`, `NA` with `"<NA>"`, numeric `10` with
#' character `"10"`, and `TRUE` with `"TRUE"`. None of those bite today, because
#' every member position happens to be type-fixed by coercion at the call sites —
#' but that is an invariant held by convention, written down nowhere, and the
#' cube key does not coerce most of its character members. One byte per member
#' removes the whole class by construction.
#'
#' Branch order matters in two places, both measured:
#' * **`is.list()` first.** `sf::st_as_binary()` returns a **list** of raw
#'   vectors classed `"WKB"` — `is.raw()` on it is `FALSE`. A raw-only branch
#'   would never match it.
#' * **`is.logical()` before `is.numeric()`**, or `TRUE` renders as `1` and
#'   collides with the number.
#'
#' Numerics are hashed as their **IEEE-754 bytes**, not via `sprintf("%.17g")`.
#' `%.17g` is injective and would work, but it routes through libc — so its
#' exponent formatting is a platform variable, and drift has no cross-platform
#' CI to catch that. It also collapses `NaN` into `NA_real_` under any `is.na()`
#' sentinel (`is.na(NaN)` is `TRUE`), a distinction the old key made. The byte
#' form has neither problem and reuses the hex path the WKB member already needs.
#'
#' Character members go through `enc2utf8()`: the same text in UTF-8 and latin1
#' hashes differently otherwise, which is a spurious distinction rather than a
#' real one.
#' @noRd
cache_key_string <- function(parts) {
  paste(vapply(parts, cache_key_member, character(1)), collapse = "\x1f")
}

#' @noRd
cache_key_member <- function(x) {
  # zero-length and NULL are one case, tagged so they cannot collide with any
  # literal a caller might pass
  if (is.null(x) || length(x) == 0L) return("0:")
  # BEFORE the vector branches: a WKB is a list, and is.raw() is FALSE on it
  if (is.list(x)) {
    return(paste0("l:", paste(vapply(x, cache_key_member, character(1)),
                              collapse = "\x1e")))
  }
  if (is.raw(x)) return(paste0("x:", paste(as.character(x), collapse = "")))
  # before is.numeric(): sprintf/as.double would render TRUE as 1
  if (is.logical(x)) {
    return(paste0("b:", paste(ifelse(is.na(x), "NA", ifelse(x, "T", "F")),
                              collapse = "\x1e")))
  }
  if (is.numeric(x)) {
    return(paste0("n:", paste(vapply(x, function(v) {
      paste(as.character(writeBin(as.double(v), raw(), endian = "little")),
            collapse = "")
    }, character(1)), collapse = "\x1e")))
  }
  paste0("s:", paste(ifelse(is.na(x), "\x01NA", enc2utf8(as.character(x))),
                     collapse = "\x1e"))
}


#' Validate and snap a download `tile_size` to the pixel grid
#'
#' `tile_size` (CRS units) controls the download-tiling grid (#36). It is
#' snapped to a multiple of `res` so every tile's pixel grid aligns to the same
#' `res`-lattice — a prerequisite for a seam-free `terra::merge()` of the tiles.
#' Caller only invokes this for a non-NULL `tile_size`; `NULL` gates the whole
#' tiled path upstream. Returns the snapped size (a single positive numeric).
#' @noRd
tile_size_check <- function(tile_size, res) {
  if (!is.numeric(tile_size) || length(tile_size) != 1L ||
        !is.finite(tile_size) || tile_size <= 0) {
    cli::cli_abort(c(
      "{.arg tile_size} must be a single positive finite number (CRS units) \\
       or {.code NULL}.",
      "x" = "Got {.obj_type_friendly {tile_size}}."
    ))
  }
  snapped <- round(tile_size / res) * res
  if (snapped < res) {
    cli::cli_abort(c(
      "{.arg tile_size} ({tile_size}) snaps to {snapped}, smaller than \\
       {.arg res} ({res}).",
      "i" = "Choose a {.arg tile_size} at least as large as {.arg res}."
    ))
  }
  if (!isTRUE(all.equal(snapped, tile_size))) {
    cli::cli_inform(
      "{.arg tile_size} snapped from {tile_size} to {snapped} \\
       (a multiple of {.arg res} = {res})."
    )
  }
  snapped
}


#' Build the res-aligned download tiles that intersect the AOI
#'
#' Splits the AOI bounding box into a grid of `tile_size`-square cells anchored
#' at the bbox lower-left (the same origin as the single-cube extent), and keeps
#' only cells that intersect the AOI polygon — so a thin corridor fetches near
#' its footprint, not its full bbox (#36). Boundary cells are left un-trimmed
#' past the bbox: trimming the max edge would break `res`-alignment, and the
#' `< tile_size` overhang is dropped by the final `terra::mask()` anyway.
#' `tile_size` must already be snapped (see `tile_size_check()`).
#' @return A list of `list(left, right, bottom, top)` extents for [gdalcubes::cube_view()].
#' @noRd
tile_grid <- function(aoi_target, tile_size, res) {
  bbox <- sf::st_bbox(aoi_target)
  grid <- sf::st_make_grid(
    sf::st_as_sfc(bbox),
    cellsize = tile_size,
    offset = c(bbox[["xmin"]], bbox[["ymin"]])
  )
  aoi_union <- sf::st_union(sf::st_geometry(aoi_target))
  grid <- grid[lengths(sf::st_intersects(grid, aoi_union)) > 0]
  if (length(grid) == 0) {
    cli::cli_abort("No download tiles intersect the AOI \\
                    (is the AOI geometry valid and non-empty?).")
  }
  lapply(grid, function(cell) {
    b <- sf::st_bbox(cell)
    list(left = b[["xmin"]], right = b[["xmax"]],
         bottom = b[["ymin"]], top = b[["ymax"]])
  })
}


#' Fetch one gdalcubes cube over a single space+time extent to a NetCDF file
#'
#' The `cube_view` + `raster_cube` + `write_ncdf` block shared by the untiled
#' fetch (one call over the AOI bbox) and the tiled fetch (one call per tile,
#' #36). Sharing this primitive is what guarantees a tile fetches identically to
#' the corresponding slice of the untiled cube. `ext` is a list with
#' `left`/`right`/`bottom`/`top`; `t0`/`t1` bound the year. Writes to `out_nc`
#' and returns it (the caller reads it back with [terra::rast()]).
#' @noRd
fetch_extent_to <- function(col, ext, t0, t1, target_crs, res, dt,
                            aggregation, resampling, out_nc) {
  v <- gdalcubes::cube_view(
    srs = target_crs,
    extent = list(
      left = ext$left, right = ext$right,
      bottom = ext$bottom, top = ext$top,
      t0 = t0, t1 = t1
    ),
    dx = res, dy = res, dt = dt,
    aggregation = aggregation, resampling = resampling
  )
  cube <- gdalcubes::raster_cube(col, v)
  gdalcubes::write_ncdf(cube, out_nc, overwrite = TRUE)
  out_nc
}


#' Mosaic per-tile fetch outputs into one cache raster
#'
#' Reads each per-tile NetCDF, merges them (tiles are res-aligned and
#' non-overlapping, so `terra::merge()` reassembles without resampling), and
#' writes the mosaic to `out_file`. Written with `terra::writeRaster()` to a
#' GeoTIFF — not `gdalcubes::write_ncdf()` — because terra's own NetCDF *write*
#' is fragile on the pinned stack (see inst/notes/gdalcubes-pc-gotchas.md); this
#' mirrors the `dft_stac_cube()` cache. Returns `out_file`.
#' @noRd
mosaic_tiles <- function(tile_files, out_file) {
  rasters <- lapply(tile_files, terra::rast)
  merged <- terra::merge(terra::sprc(rasters))
  terra::writeRaster(merged, out_file, overwrite = TRUE)
  out_file
}


#' Publish a cache entry atomically
#'
#' Writes via a unique temp file **in the same directory** and moves it onto the
#' canonical name only after `write_fn` has returned and the result has been
#' validated. Same directory means same filesystem, so the move is a POSIX
#' `rename(2)` — atomic, and it replaces the destination in one step.
#'
#' This is what #41 was missing. Writing straight to `<year>_<key>.nc` meant a
#' process killed mid-write left a partial file at the *canonical* name, which
#' the presence-only cache gate then reported as `cached` forever.
#'
#' Three details that are easy to get wrong:
#' * **The temp keeps the real extension.** [terra::writeRaster()] picks its
#'   driver from the extension, so a `.tmp` suffix would select the wrong driver
#'   or fail outright.
#' * **[file.rename()] signals failure by returning `FALSE`**, not by erroring.
#'   An unchecked move is how a missing cache reaches a consumer silently.
#' * **The temp is not hidden.** `dft_cache_info()` and `dft_cache_clear()` call
#'   [list.files()] with the default `all.files = FALSE`, so a dot-prefixed temp
#'   would be invisible to the size report and would under-report the count
#'   removed.
#'
#' The temp name carries the PID and a per-call token, so two sessions fetching
#' the same key no longer interleave writes onto one path — that becomes clean
#' last-writer-wins.
#'
#' `on.exit()` removes the temp on error and on R-level interrupt. It does not
#' run on `SIGKILL`, OOM-kill or power loss, so a hard kill can still strand a
#' `*.tmp*` file. That is disk garbage and never a correctness problem: the read
#' gate matches only the canonical name, so a temp can never be served — which
#' is precisely the property #41 lacked. `dft_cache_clear()` removes them.
#' @noRd
cache_write_atomic <- function(path, write_fn) {
  tmp <- file.path(
    dirname(path),
    sprintf("%s.tmp%d-%s.%s",
            tools::file_path_sans_ext(basename(path)),
            Sys.getpid(),
            basename(tempfile("")),
            tools::file_ext(path))
  )
  # GDAL's PAM sidecar rides along with whatever the writer produced. Measured:
  # terra::writeRaster() to `.nc` emits one, to `.tif` does not. Renaming only
  # the raster would strand it under the dead temp name, leaving cache litter
  # that dft_cache_info() then counts.
  tmp_pam <- paste0(tmp, ".aux.xml")
  on.exit(unlink(c(tmp, tmp_pam)), add = TRUE)

  write_fn(tmp)

  if (!file.exists(tmp)) {
    cli::cli_abort(c(
      "Writing the cache entry for {.file {basename(path)}} produced no file.",
      "i" = "Nothing was written to {.file {tmp}}."
    ))
  }
  # Validate BEFORE publishing, not only at the read gate. This is what covers
  # the miss branch — a freshly written file otherwise flows straight into
  # terra::mask(terra::rast(cache_file)), which is exactly where the #41
  # traceback dies — and it is the only validation `force = TRUE` ever reaches.
  why <- cache_invalid_reason(tmp)
  if (!is.na(why)) {
    cli::cli_abort(c(
      "The cache entry just written for {.file {basename(path)}} {why}.",
      "i" = "It was discarded rather than published; the previous entry, if \\
             any, is untouched."
    ))
  }

  # Sidecar first, raster second, so the canonical name never exists without it.
  if (file.exists(tmp_pam) &&
        !isTRUE(file.rename(tmp_pam, paste0(path, ".aux.xml")))) {
    cli::cli_abort(
      "The sidecar for {.file {basename(path)}} could not be moved into place."
    )
  }
  if (!isTRUE(file.rename(tmp, path))) {
    cli::cli_abort(c(
      "The cache entry for {.file {basename(path)}} could not be moved into \\
       place.",
      "i" = "Failed to rename {.file {tmp}} onto {.file {path}}.",
      "i" = "Check permissions on the cache directory and that it is not \\
             read-only."
    ))
  }
  path
}


#' Why a cache file cannot be trusted, or `NA` if it can
#'
#' Three arms, each covering a damage shape the others structurally cannot see.
#' Measured 2026-09-02 (terra 1.9.34, GDAL 3.8.5, gdalcubes 0.7.4):
#'
#' | shape | `terra::rast()` | geometry | pixel read |
#' | --- | --- | --- | --- |
#' | tail-truncated (and zero-byte) | errors | -- | -- |
#' | broken geotransform | succeeds + warns | degenerate | `mask()` fails |
#' | content-damaged, size preserved | succeeds silently | valid | warns |
#'
#' So none of the cheaper single checks is sufficient: `tryCatch(rast())` alone
#' passes the second and third shapes, and a geometry check alone passes the
#' third — that file opens clean, has correct dim/res/CRS, and even masks fine.
#' Content damage is detectable *only* via the warning raised during the read;
#' the values come back looking plausible (`nNA = 0`), so nothing is inferable
#' by inspecting them.
#'
#' **Arm (a) catches errors only, never a warning on open.** The multidim-API
#' warning is a capability message rather than a damage signal — drift's own
#' tests must `suppressWarnings()` around writing a `.nc` through terra — so
#' failing on it would refuse healthy `.nc` entries across the whole cache.
#'
#' `probe` is injectable so the warning-handling branch is testable without
#' depending on a damage fixture whose reachability is format-dependent.
#' @noRd
cache_invalid_reason <- function(path, probe = cache_probe_last_row) {
  # suppressWarnings on the OPEN only. Warnings here are capability messages,
  # not damage signals (see above), and this function is routinely pointed at a
  # file that may be broken — letting GDAL's "not recognized as a supported file
  # format" escape would make every successful detection also spray a second,
  # lower-level warning at the user. The READ warnings below are deliberately
  # NOT suppressed: there, the condition is the entire signal.
  r <- suppressWarnings(tryCatch(terra::rast(path), error = function(e) NULL))
  if (is.null(r)) return("could not be opened as a raster")

  why <- cache_geom_ok(dim(r), terra::res(r), as.vector(terra::ext(r)),
                       terra::crs(r))
  if (!is.na(why)) return(why)

  # The caller judges, the probe just reads. A GDAL read failure surfaces as a
  # WARNING with the values still returned (measured: `netcdf error #-101`), so
  # the warning is the only signal — and catching it here rather than inside the
  # probe means an injected probe cannot accidentally swallow its own evidence.
  ok <- TRUE
  withCallingHandlers(
    tryCatch(probe(r), error = function(e) {
      ok <<- FALSE
      NULL
    }),
    warning = function(w) {
      ok <<- FALSE
      invokeRestart("muffleWarning")
    }
  )
  if (!ok) return("its pixel data could not be read cleanly")
  NA_character_
}


#' Is a raster's georeferencing self-consistent?
#'
#' Kept separate from the [terra::SpatRaster] it describes, over plain numerics,
#' because terra refuses to *construct* a zero-dimension, non-finite-resolution
#' or collapsed-extent raster — so driving these checks through a file would
#' leave three of the four shipping with no test able to reach them.
#'
#' The empty-CRS check is a **conjunction** with the identity geotransform
#' (`res == 1`, extent `0..ncol` by `0..nrow`) rather than a test on the CRS
#' alone. An absent CRS is not by itself proof of damage, and refusing on it
#' alone risks discarding healthy entries — the cost of a false refusal here is
#' a silent, permanent re-download. Together the two are the shape the #41
#' report describes, where GDAL fell back to an identity geotransform and terra
#' reported `Cannot invert geotransform`.
#'
#' @return `NA_character_` when the geometry is sound, otherwise a reason.
#' @noRd
cache_geom_ok <- function(dims, res, ext, crs) {
  if (any(dims[1:2] <= 0)) return("has zero rows or columns")
  if (any(!is.finite(res)) || any(res <= 0)) {
    return("has a non-finite or non-positive resolution")
  }
  if (any(!is.finite(ext))) return("has a non-finite extent")
  if (ext[1] >= ext[2] || ext[3] >= ext[4]) return("has a collapsed extent")
  if (!nzchar(crs) &&
        isTRUE(all.equal(as.numeric(res), c(1, 1))) &&
        isTRUE(all.equal(as.numeric(ext),
                         c(0, dims[2], 0, dims[1]), check.names = FALSE))) {
    return("has no CRS and an identity geotransform, the fallback GDAL uses \\
            when it cannot read the georeferencing")
  }
  NA_character_
}


#' Read the last row of a raster, reporting whether it came back clean
#'
#' The **last** row rather than the first: an interrupted write truncates at the
#' end, so the tail is the part least likely to be complete. Cost is the same
#' either way — one block-row across every layer, 0.08 s on a 13 MB cache entry
#' against 2.4 s for a `minmax(compute = TRUE)` scan.
#'
#' This **samples, it does not prove**. It is a smoke test for truncation and
#' structural damage; interior content damage that leaves the container walkable
#' can pass it. The guarantee against partial cache entries is the atomic write
#' in `cache_write_atomic()`, not this probe.
#'
#' It only reads. Whether the read counts as clean is decided by
#' `cache_invalid_reason()`, which watches for a warning or error around this
#' call — a GDAL read failure surfaces as a *warning* with the values still
#' returned, so the returned data cannot be distinguished from healthy data by
#' inspection and the condition is the whole signal.
#' @noRd
cache_probe_last_row <- function(r) {
  terra::values(r, row = terra::nrow(r), nrows = 1)
}


#' Decide whether a cached file may be served, warning if it may not
#'
#' Shared by [dft_stac_fetch()] and [dft_stac_cube()]. A rejected entry is
#' treated as a **miss and re-fetched** — never an abort telling the user to
#' delete a file by hand, since manual deletion is the recovery #41 exists to
#' remove. The warning names the failing arm so a false refusal is reportable
#' rather than showing up as "drift mysteriously got slow".
#' @noRd
cache_hit_ok <- function(cache_file, label) {
  why <- cache_invalid_reason(cache_file)
  if (is.na(why)) return(TRUE)
  cli::cli_warn(c(
    "The cached file for {label} {why}; re-fetching.",
    "i" = "{.file {cache_file}}"
  ))
  FALSE
}


#' Auto-detect UTM EPSG code from sf geometry
#' @noRd
auto_utm_epsg <- function(x) {
  centroid <- sf::st_coordinates(
    sf::st_centroid(sf::st_union(sf::st_transform(x, 4326)))
  )
  zone <- floor((centroid[1, "X"] + 180) / 6) + 1
  hemisphere <- if (centroid[1, "Y"] >= 0) 32600L else 32700L
  paste0("EPSG:", hemisphere + zone)
}

#' Apply a spectral index to a data cube
#'
#' Resolve a named spectral index (e.g. `"kndvi"`) into a per-pixel arithmetic
#' expression over a source's band roles and apply it to a `gdalcubes` data
#' cube, returning a single-band cube named after the index.
#'
#' Index formulas are stored in a shipped registry ([dft_index_table()]) written
#' over band **roles** (`red`, `nir`, `swir16`), not literal asset names. The
#' roles are resolved to per-source asset names via [dft_stac_config()], so the
#' same `"kndvi"` works against Sentinel-2 (`B04`/`B08`) or any future
#' reflectance source without changing the formula.
#'
#' Reflectance `scale`/`offset` are folded **into** the expression as a per-band
#' affine transform `(asset * scale + offset)`. This matters for ratio indices:
#' a non-zero offset does not cancel in `(nir - red)/(nir + red)`, so computing
#' NDVI on raw digital numbers is wrong for sources with an offset (Landsat C2
#' L2, or Sentinel-2 processing baseline 04.00).
#'
#' @param cube A `gdalcubes` data cube (e.g. the lazy cube built inside
#'   [dft_stac_cube()]) whose bands are the source's assets.
#' @param index Character. An index name present in [dft_index_table()]
#'   (default `"kndvi"`).
#' @param source Character. Source name passed to [dft_stac_config()] to resolve
#'   the role→asset map and reflectance scale/offset (default
#'   `"sentinel-2-l2a"`).
#' @param roles Named list mapping roles to asset names. When `NULL`, taken from
#'   `dft_stac_config(source)$roles`.
#' @param scale,offset Numeric reflectance affine transform. When `NULL`, taken
#'   from the source config (falling back to `1` / `0`).
#'
#' @return A single-band `gdalcubes` cube with the band named `index`.
#'
#' @seealso [dft_index_table()] for the registry, [dft_stac_cube()] for the
#'   caller that builds the input cube.
#'
#' @examples
#' # The registry the resolver reads:
#' dft_index_table()
#'
#' \dontrun{
#' # Applied to a lazy Sentinel-2 cube (requires network + gdalcubes):
#' aoi <- sf::st_read(system.file("extdata", "example_aoi.gpkg", package = "drift"))
#' cube <- dft_stac_cube(aoi, index = "kndvi")  # dft_stac_cube calls this internally
#' }
#'
#' @export
dft_index_expr <- function(cube,
                           index = "kndvi",
                           source = "sentinel-2-l2a",
                           roles = NULL,
                           scale = NULL,
                           offset = NULL) {
  rlang::check_installed("gdalcubes", reason = "to apply an index to a cube")
  cfg <- dft_stac_config(source)
  roles <- roles %||% cfg$roles
  scale <- scale %||% cfg$scale %||% 1
  offset <- offset %||% cfg$offset %||% 0
  expr <- index_resolve_expr(index, roles, scale, offset)
  gdalcubes::apply_pixel(cube, expr, names = index)
}

#' Load the shipped spectral-index registry
#'
#' Reads the CSV index registry bundled with the package. Each row defines one
#' index as a `gdalcubes`/tinyexpr formula written over band roles.
#'
#' @return A tibble with columns `index`, `formula`, `roles` (comma-separated
#'   role names), and `description`.
#'
#' @examples
#' dft_index_table()
#'
#' @export
dft_index_table <- function() {
  path <- system.file("indices", "indices.csv", package = "drift", mustWork = TRUE)
  tibble::as_tibble(utils::read.csv(path, stringsAsFactors = FALSE))
}

#' Look up one index registry row, erroring on unknown index
#' @noRd
index_row <- function(index) {
  tbl <- dft_index_table()
  row <- tbl[tbl$index == index, ]
  if (nrow(row) == 0) {
    cli::cli_abort(c(
      "Unknown index {.val {index}}.",
      "i" = "Available indices: {.val {tbl$index}}."
    ))
  }
  row
}

#' Band roles required by an index (internal)
#'
#' Used by [dft_stac_cube()] to decide which assets to pull.
#' @noRd
index_roles <- function(index) {
  trimws(strsplit(index_row(index)$roles[[1]], ",")[[1]])
}

#' Build a per-band affine reflectance token for an expression (internal)
#'
#' Returns the bare asset name when the transform is identity (`scale == 1`,
#' `offset == 0`); otherwise `(asset * scale +/- |offset|)`. Numbers are
#' formatted without scientific notation so the tinyexpr C parser accepts them.
#' @noRd
scale_token <- function(asset, scale, offset) {
  if (scale == 1 && offset == 0) return(asset)
  core <- if (scale == 1) {
    asset
  } else {
    sprintf("%s * %s", asset, format(scale, scientific = FALSE, trim = TRUE))
  }
  if (offset == 0) return(sprintf("(%s)", core))
  sign <- if (offset < 0) "-" else "+"
  sprintf("(%s %s %s)", core, sign,
          format(abs(offset), scientific = FALSE, trim = TRUE))
}

#' Resolve an index name to a per-pixel expression string (internal)
#'
#' Substitutes each role token in the registry formula with its scaled asset
#' token. Roles are substituted longest-name-first with word boundaries so a
#' shorter role name cannot clobber part of a longer one.
#' @noRd
index_resolve_expr <- function(index, roles, scale = 1, offset = 0) {
  row <- index_row(index)
  formula <- row$formula[[1]]
  needed <- trimws(strsplit(row$roles[[1]], ",")[[1]])
  needed <- needed[order(nchar(needed), decreasing = TRUE)]
  for (role in needed) {
    asset <- roles[[role]]
    if (is.null(asset)) {
      cli::cli_abort(c(
        "Index {.val {index}} needs role {.val {role}}, absent from the role map.",
        "i" = "Available roles: {.val {names(roles)}}."
      ))
    }
    formula <- gsub(paste0("\\b", role, "\\b"),
                    scale_token(asset, scale, offset), formula)
  }
  formula
}

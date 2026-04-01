#' Check that a raster has a projected CRS
#'
#' Internal helper that errors when a raster uses a geographic (degree-based)
#' CRS. Area calculations via `prod(terra::res(r))` assume metre units and
#' produce silently wrong results for geographic CRS.
#'
#' @param r A [terra::SpatRaster].
#' @param fn Character. Name of the calling function, used in the error message.
#'
#' @return Invisible `TRUE` if the CRS is projected. Throws an error otherwise.
#'
#' @details
#' `dft_stac_fetch()` auto-projects to UTM, so rasters from the standard
#' pipeline always pass. This guard catches user-supplied rasters in
#' EPSG:4326 or other geographic CRS.
#'
#' See [drift#16](https://github.com/NewGraphEnvironment/drift/issues/16) for
#' planned `terra::cellSize()` support for geographic CRS.
#'
#' @noRd
dft_check_crs <- function(r, fn = "this function") {
  if (terra::is.lonlat(r, perhaps = TRUE, warn = FALSE)) {
    stop(
      fn, "() requires a projected CRS (metre-based resolution). ",
      "The input raster appears to use a geographic CRS (degrees). ",
      "Reproject first, e.g.: terra::project(r, \"EPSG:32609\")",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

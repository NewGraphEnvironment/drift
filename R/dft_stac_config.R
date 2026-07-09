#' Get STAC configuration for a known source
#'
#' Returns connection details for pre-configured STAC collections.
#' Used as a convenience wrapper around [dft_stac_fetch()] (categorical
#' sources) and [dft_stac_cube()] (continuous index-trajectory sources) so
#' users don't need to remember STAC URLs, collection IDs, and band names.
#'
#' Sources are of two kinds. **Categorical** sources (`"io-lulc"`,
#' `"esa-worldcover"`) host single-band classified rasters and carry a flat
#' `asset` name for [dft_stac_fetch()]. **Cube** sources (`"sentinel-2-l2a"`)
#' host multi-band reflectance imagery and instead carry a role-based band map
#' (`red`/`nir`/`swir16`/`mask`), mask values, and reflectance scale/offset for
#' [dft_stac_cube()]; they are marked with `cube = TRUE`. The role-based schema
#' means a new reflectance source (e.g. Landsat C2 L2) drops in with no API
#' change — only the role→asset map and scale/offset differ.
#'
#' @param source Character. One of `"io-lulc"` (Esri IO LULC annual v02),
#'   `"esa-worldcover"` (ESA WorldCover), or `"sentinel-2-l2a"` (Sentinel-2
#'   L2A surface reflectance, a cube source).
#'
#' @return A list. Categorical sources have elements `stac_url`, `collection`,
#'   `asset`, `available_years`. Cube sources have `stac_url`, `collection`,
#'   `cube = TRUE`, `roles` (a named list mapping `red`/`nir`/`swir16`/`mask`
#'   to asset names), `mask_values` (integer mask classes to exclude),
#'   `scale`/`offset` (DN → reflectance affine transform), and
#'   `available_datetime` (an ISO 8601 interval string). The `cube` field is
#'   absent (not `FALSE`) for categorical sources; test with `isTRUE(cfg$cube)`.
#'
#' @examples
#' dft_stac_config("io-lulc")
#' dft_stac_config("esa-worldcover")
#' dft_stac_config("sentinel-2-l2a")
#'
#' @export
dft_stac_config <- function(source = c("io-lulc", "esa-worldcover",
                                       "sentinel-2-l2a")) {
  source <- match.arg(source)
  switch(source,
    "io-lulc" = list(
      stac_url = "https://planetarycomputer.microsoft.com/api/stac/v1",
      collection = "io-lulc-annual-v02",
      asset = "data",
      available_years = 2017L:2023L
    ),
    "esa-worldcover" = list(
      stac_url = "https://planetarycomputer.microsoft.com/api/stac/v1",
      collection = "esa-worldcover",
      asset = "map",
      available_years = c(2020L, 2021L)
    ),
    "sentinel-2-l2a" = list(
      stac_url = "https://planetarycomputer.microsoft.com/api/stac/v1",
      collection = "sentinel-2-l2a",
      cube = TRUE,
      # Planetary Computer asset names (NOT the Element84/AWS red/nir/scl names)
      roles = list(
        red    = "B04",
        nir    = "B08",
        swir16 = "B11",
        mask   = "SCL"
      ),
      # Scene Classification Layer classes to mask out:
      # 3 cloud shadow, 8 cloud medium, 9 cloud high, 10 thin cirrus, 11 snow/ice
      # (snow is masked by default: it is never a vegetation signal and otherwise
      # dominates the winter trajectory at high latitudes)
      mask_values = c(3L, 8L, 9L, 10L, 11L),
      # DN -> reflectance: baseline 04.00 (+1000 DN) => DN * 1e-4 - 0.1
      scale = 1e-4,
      offset = -0.1,
      available_datetime = "2017-01-01/2024-12-31"
    )
    # "landsat-c2-l2" drops in with the same cube shape, no API change:
    #   list(
    #     stac_url = "https://planetarycomputer.microsoft.com/api/stac/v1",
    #     collection = "landsat-c2-l2",
    #     cube = TRUE,
    #     roles = list(red = "red", nir = "nir08",
    #                  swir16 = "swir16", mask = "qa_pixel"),
    #     mask_values = <qa_pixel cloud/shadow bit classes>,
    #     scale = 0.0000275, offset = -0.2,   # non-zero offset breaks ratio
    #     available_datetime = "1984-01-01/2024-12-31"  #   indices on raw DNs
    #   )
  )
}

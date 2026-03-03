#' Get STAC configuration for a known land cover source
#'
#' Returns connection details for pre-configured STAC collections.
#' Used as a convenience wrapper around [dft_stac_fetch()] so users
#' don't need to remember STAC URLs and collection IDs.
#'
#' @param source Character. One of `"io-lulc"` (Esri IO LULC annual v02)
#'   or `"esa-worldcover"` (ESA WorldCover).
#'
#' @return A list with elements:
#'   \describe{
#'     \item{stac_url}{STAC API endpoint}
#'     \item{collection}{Collection ID}
#'     \item{asset}{Asset name to download}
#'     \item{available_years}{Integer vector of available years}
#'   }
#'
#' @examples
#' dft_stac_config("io-lulc")
#' dft_stac_config("esa-worldcover")
#'
#' @export
dft_stac_config <- function(source = c("io-lulc", "esa-worldcover")) {
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
    )
  )
}

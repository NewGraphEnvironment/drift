#' List the Esri World Imagery Wayback releases
#'
#' Reads Esri's Wayback configuration, which lists every archived release of the
#' World Imagery basemap, and returns one row per release, sorted by date.
#'
#' **A release date is not a capture date.** A release is the World Imagery
#' mosaic as published on that date, and it mosaics captures of many years:
#' over the Neexdzii Kwa floodplain the 2017-11-16 release serves WorldView-2
#' captures from 2013 and 2016. The release date bounds the capture from above
#' and says nothing more. To find the capture a feature was actually imaged at,
#' use [dft_wayback_captures()], which reads each release's capture metadata.
#'
#' Release ids are not ordered by date, so sort or filter on `release_date`,
#' never on `release_id`.
#'
#' @return A tibble with one row per release: `release_id` (character, the
#'   tile service's release number), `release_date` (Date) and `meta_url` (the
#'   release's capture-metadata MapServer). Sorted by `release_date`.
#'
#' @seealso [dft_wayback_captures()], [dft_wayback_pick()],
#'   [dft_wayback_fetch()].
#'
#' @examples
#' \dontrun{
#' rel <- dft_wayback_releases()
#' nrow(rel)
#' range(rel$release_date)
#'
#' # Only the releases from 2020 on, to query fewer of them
#' rel_recent <- rel[rel$release_date >= as.Date("2020-01-01"), ]
#' }
#'
#' @export
dft_wayback_releases <- function() {
  cfg <- jsonlite::fromJSON(wayback_get(.wayback_config_url),
                            simplifyVector = FALSE)
  wayback_releases_parse(cfg)
}


#' Parse Esri's waybackconfig.json into the release table
#'
#' Every release must carry a dated title and a metadata URL. One that does not
#' is an abort, not a dropped row: a release missing from the table silently
#' narrows every capture search built on it.
#' @noRd
wayback_releases_parse <- function(cfg) {
  if (!is.list(cfg) || !length(cfg) || is.null(names(cfg))) {
    cli::cli_abort("The Wayback configuration lists no releases.")
  }
  title <- vapply(cfg, function(r) as.character(r$itemTitle %||% NA)[1], "")
  meta <- vapply(cfg, function(r) as.character(r$metadataLayerUrl %||% NA)[1],
                 "")
  m <- regmatches(title, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", title))
  date_chr <- rep(NA_character_, length(title))
  date_chr[!is.na(title) & grepl("[0-9]{4}-[0-9]{2}-[0-9]{2}", title)] <- m
  release_date <- as.Date(date_chr, format = "%Y-%m-%d")
  bad <- is.na(release_date) | is.na(meta) | !nzchar(meta)
  if (any(bad)) {
    ids <- utils::head(names(cfg)[bad], 3)
    cli::cli_abort(c(
      "{sum(bad)} Wayback release{?s} lack a parseable date or a metadata URL.",
      "i" = "First: {.val {ids}}."
    ))
  }
  out <- tibble::tibble(
    release_id = names(cfg),
    release_date = release_date,
    meta_url = sub("/+$", "", meta)
  )
  # Ties on date are broken by id so the order is total and reproducible.
  out[order(out$release_date, suppressWarnings(as.numeric(out$release_id)),
            out$release_id, method = "radix"), ]
}


#' GET a Wayback URL, reading the status from curl
#'
#' Three tries: a metadata service that answers 5xx once is common, and a
#' release that fails silently would narrow the candidate set. The status comes
#' from `curl_fetch_memory()`'s `status_code`, never from a reader's message.
#' @noRd
wayback_get <- function(url, tries = 3L) {
  why <- NULL
  for (i in seq_len(tries)) {
    r <- tryCatch(
      curl::curl_fetch_memory(url, handle = curl::new_handle(timeout = 120)),
      error = identity
    )
    if (!inherits(r, "error") && r$status_code == 200L) {
      return(rawToChar(r$content))
    }
    why <- if (inherits(r, "error")) conditionMessage(r) else
      paste("HTTP", r$status_code)
    if (i < tries) Sys.sleep(2 * i)
  }
  cli::cli_abort(
    c("A Wayback request failed after {tries} tr{?y/ies}: {why}.",
      "i" = "{.url {url}}"),
    class = "drift_wayback_http"
  )
}

.wayback_config_url <-
  "https://s3-us-west-2.amazonaws.com/config.maptiles.arcgis.com/waybackconfig.json"

.wayback_tile_url <- paste0(
  "https://wayback.maptiles.arcgis.com/arcgis/rest/services/World_Imagery/",
  "WMTS/1.0.0/default028mm/MapServer/tile"
)

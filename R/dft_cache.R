#' Get drift cache directory path
#'
#' Returns the path to the drift tile cache directory. Creates it if
#' it doesn't exist.
#'
#' @param cache_dir Character. Override the default cache location.
#'   If NULL, uses `rappdirs::user_cache_dir("drift")`.
#'
#' @return Character path to the cache directory.
#'
#' @examples
#' dft_cache_path()
#'
#' @export
dft_cache_path <- function(cache_dir = NULL) {
  path <- cache_dir %||% rappdirs::user_cache_dir("drift")
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  path
}

#' Clear the drift tile cache
#'
#' Removes all cached files from the drift cache directory.
#'
#' @param cache_dir Character. Override the default cache location.
#' @param source Character. If provided, only clear files for this source.
#'   Otherwise clears everything.
#'
#' @return Invisibly returns the number of files removed.
#'
#' @examples
#' \dontrun{
#' dft_cache_clear()
#' }
#'
#' @export
dft_cache_clear <- function(cache_dir = NULL, source = NULL) {
  path <- dft_cache_path(cache_dir)
  if (!is.null(source)) {
    path <- file.path(path, source)
  }
  if (!dir.exists(path)) return(invisible(0L))
  files <- list.files(path, recursive = TRUE, full.names = TRUE)
  n <- length(files)
  if (n > 0) unlink(path, recursive = TRUE)
  invisible(n)
}

#' Show drift cache info
#'
#' Reports the cache location and size.
#'
#' @param cache_dir Character. Override the default cache location.
#'
#' @return A list with `path`, `n_files`, and `size_mb`.
#'
#' @examples
#' dft_cache_info()
#'
#' @export
dft_cache_info <- function(cache_dir = NULL) {
  path <- dft_cache_path(cache_dir)
  files <- list.files(path, recursive = TRUE, full.names = TRUE)
  size <- if (length(files) > 0) sum(file.size(files), na.rm = TRUE) else 0
  list(
    path = path,
    n_files = length(files),
    size_mb = round(size / 1024^2, 2)
  )
}

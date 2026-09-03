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
#' This includes any `*.tmp*` orphans. Cache entries are published atomically —
#' written to a temp file beside the target and renamed into place only on a
#' complete, validated write — so a process killed by `SIGKILL`, an OOM-kill or
#' power loss can strand a temp file that R's own cleanup never ran for. Such a
#' file is disk garbage but never a correctness problem: the cache gate matches
#' only the canonical name, so an orphan can never be served as a hit.
#'
#' Nothing sweeps them automatically during a fetch, deliberately: a multi-hour
#' cube write is precisely the in-flight temp such a sweep would delete.
#'
#' @param cache_dir Character. Override the default cache location.
#' @param source Character. If provided, only clear files for this source.
#'   Otherwise clears everything.
#' @param scheme Character. Which cache-scheme generations to clear (#48).
#'   `"all"` (default) clears everything, matching the behaviour before schemes
#'   existed. `"current"` clears only entries the running version can actually
#'   use. `"superseded"` clears only entries left behind by an older scheme —
#'   the reclaim path for caches orphaned by a key change.
#'
#' @return Invisibly returns the number of files removed.
#'
#' @examples
#' \dontrun{
#' dft_cache_clear()
#' dft_cache_clear(scheme = "superseded") # reclaim orphaned generations only
#' }
#'
#' @export
dft_cache_clear <- function(cache_dir = NULL, source = NULL,
                            scheme = c("all", "current", "superseded")) {
  scheme <- match.arg(scheme)
  base <- dft_cache_path(cache_dir)
  current <- cache_scheme_dir(cache_dir)
  targets <- switch(
    scheme,
    all = base,
    current = current,
    # Anything directly under the base that is not the current scheme dir. A
    # pre-scheme layout put <base>/<source>/ there, so those are exactly the
    # generations a key change orphaned.
    superseded = setdiff(list.dirs(base, recursive = FALSE), current)
  )
  if (!is.null(source)) targets <- file.path(targets, source)
  targets <- targets[dir.exists(targets)]
  if (!length(targets)) return(invisible(0L))
  files <- unlist(lapply(targets, list.files, recursive = TRUE,
                         full.names = TRUE))
  n <- length(files)
  if (n > 0) unlink(targets, recursive = TRUE)
  invisible(n)
}


#' Directory for the current cache scheme
#'
#' Cache entries live under `<base>/<scheme>/<source>/`. The scheme segment
#' exists so that a deliberate key change is a **migration** rather than a silent
#' orphaning (#48): old entries keep their own directory, stay findable, and can
#' be reclaimed with `dft_cache_clear(scheme = "superseded")` instead of becoming
#' invisible litter nobody can attribute.
#'
#' [dft_cache_path()] deliberately keeps returning the **base** and its existing
#' contract — it is exported, documented, and referenced downstream, so the
#' scheme segment is added here rather than there.
#'
#' Every site that builds a cache path must route through this, including
#' [dft_cache_clear()]. Adding the segment only in the fetch and cube paths would
#' leave `dft_cache_clear(source = )` pointed at the *superseded* generation,
#' where it would report success having deleted nothing current — and it is the
#' documented recovery lever.
#' @noRd
cache_scheme_dir <- function(cache_dir = NULL, source = NULL) {
  path <- file.path(dft_cache_path(cache_dir), .dft_cache_scheme)
  if (!is.null(source)) path <- file.path(path, source)
  path
}

# Bumped only when a key change is deliberate. See cache_key_hash() for why the
# key moved at v2 and why it should not move again on a dependency upgrade.
.dft_cache_scheme <- "v2"

#' Show drift cache info
#'
#' Reports the cache location and size.
#'
#' Entries left behind by an older cache scheme are reported separately (#48).
#' A key change orphans them — they can never be served again — but nothing
#' deletes them automatically, so without a count they are simply invisible disk
#' use that no one can attribute. Reclaim with
#' `dft_cache_clear(scheme = "superseded")`.
#'
#' @param cache_dir Character. Override the default cache location.
#'
#' @return A list with `path` (the base), `n_files` and `size_mb` (everything
#'   under it), and `n_files_superseded` / `size_mb_superseded` (the subset
#'   belonging to superseded schemes, which can never be served).
#'
#' @examples
#' dft_cache_info()
#'
#' @export
dft_cache_info <- function(cache_dir = NULL) {
  path <- dft_cache_path(cache_dir)
  files <- list.files(path, recursive = TRUE, full.names = TRUE)
  size <- if (length(files) > 0) sum(file.size(files), na.rm = TRUE) else 0

  old_dirs <- setdiff(list.dirs(path, recursive = FALSE),
                      cache_scheme_dir(cache_dir))
  old <- unlist(lapply(old_dirs, list.files, recursive = TRUE,
                       full.names = TRUE))
  old_size <- if (length(old) > 0) sum(file.size(old), na.rm = TRUE) else 0

  list(
    path = path,
    n_files = length(files),
    size_mb = round(size / 1024^2, 2),
    n_files_superseded = length(old),
    size_mb_superseded = round(old_size / 1024^2, 2)
  )
}

#!/usr/bin/env Rscript
# Scale test for dft_rast_break_category() on the BULK floodplain (drift#72).
#
# CLAUDE.md requires any new or changed raster-pipeline function to run on a real
# floodplain-scale pair before the PR: the bundled Neexdzii Kwa tile is 600 x 600
# and cannot reach a memory or runtime failure mode. The first
# dft_transition_artifact() held one in-memory 169M-cell raster per class per
# intermediate and was killed here at eight classes with 125 unit assertions
# green (#44).
#
# It is also the only place the pixel-grain export can be checked against
# committed evidence at scale: data-raw/logs/break_class_groups/bulk/summary_change.csv
# records what the four-level cat_fun() measured on this exact item, so a
# crosstab of the new category against `changed` must reproduce it row for row
# once the four-level labels are mapped to five.
#
# Writes:
#   data-raw/logs/benchmark_break_category/rss.txt        - sampler trace (committed)
#   data-raw/logs/benchmark_break_category/timings.csv    - stage wall-clock (committed)
#   data-raw/logs/benchmark_break_category/summary_category.csv
#                                                          - the reconciliation (committed)
#   data-raw/logs/benchmark_break_category/classified_*.tif, item.json, *.gpkg
#                                                          - fetched, gitignored
#
# Usage: Rscript data-raw/benchmark_break_category_bulk.R
# The RSS sampler is started by this script against its OWN pid, so the wrapper
# trap in code-check-shell.md ("`&` binds to the whole `&&` list") does not apply
# -- there is no backgrounded list whose $! could be a subshell.

suppressMessages({
  library(terra)
  pkgload::load_all(".", quiet = TRUE)
})

item <- "bulk_co_ff04"
years <- 2017:2023
api_url <- "https://images.a11s.one/collections/stac-floodplains-bc/items"
out_dir <- file.path("data-raw", "logs", "benchmark_break_category")
ref_change <- file.path("data-raw", "logs", "break_class_groups", "bulk", "summary_change.csv")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

t0 <- Sys.time()
timings <- list()
tick <- function(label, start) {
  el <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  message(sprintf("[%7.1fs] %s: %.1f s",
                  as.numeric(difftime(Sys.time(), t0, units = "secs")), label, el))
  timings[[label]] <<- el
  invisible(el)
}

# --- RSS sampler, against this process ------------------------------------
# ps -o rss= is KiB. Sampling our own pid removes the whole class of wrong-PID
# traces: a `mkdir && ... &` list makes $! the subshell, and the resulting trace
# is well-formed, plausible and three orders of magnitude low (#62).
rss_file <- file.path(out_dir, "rss.txt")
unlink(rss_file)
pid <- Sys.getpid()
sampler <- processx::process$new(
  "bash", c("-c", sprintf("while kill -0 %d 2>/dev/null; do ps -o rss= -p %d; sleep 2; done",
                          pid, pid)),
  stdout = rss_file)
# withr::defer(), not on.exit(): at the TOP LEVEL of a script the frame is the
# global environment, which never exits, so an on.exit() handler is registered
# and simply never called -- silently, and here it would have swallowed the peak
# RSS the whole run exists to record.
withr::defer({
  if (sampler$is_alive()) sampler$kill()
  rss <- suppressWarnings(as.numeric(readLines(rss_file)))
  rss <- rss[is.finite(rss)]
  if (length(rss)) {
    message(sprintf("peak RSS %.2f GiB over %d samples (first %.2f GiB)",
                    max(rss) / 1024^2, length(rss), rss[1] / 1024^2))
    # a wrong-pid trace is off by three orders of magnitude and still looks
    # well-formed, so assert the magnitude rather than trusting the file
    if (max(rss) / 1024^2 < 0.5) {
      warning("peak RSS under 0.5 GiB on a 169M-cell grid -- the sampler is ",
              "watching the wrong process")
    }
    utils::write.csv(data.frame(samples = length(rss),
                                peak_gib = round(max(rss) / 1024^2, 2),
                                median_gib = round(stats::median(rss) / 1024^2, 2)),
                     file.path(out_dir, "rss_summary.csv"), row.names = FALSE)
  }
}, envir = globalenv())

# --- 1. Published assets ---------------------------------------------------
t1 <- Sys.time()
fetch_once <- function(url, dest) {
  if (file.exists(dest) && file.size(dest) > 0) return(invisible(dest))
  tmp <- tempfile(fileext = paste0(".", tools::file_ext(dest)))
  h <- curl::new_handle(followlocation = TRUE, timeout = 600)
  resp <- tryCatch(curl::curl_fetch_disk(url, tmp, handle = h),
                   error = function(e) { unlink(tmp); stop(url, ": ", conditionMessage(e)) })
  if (resp$status_code != 200L) { unlink(tmp); stop(url, " returned HTTP ", resp$status_code) }
  stopifnot(file.rename(tmp, dest))
  invisible(dest)
}
item_json <- fetch_once(paste0(api_url, "/", item), file.path(out_dir, "item.json"))
assets <- jsonlite::fromJSON(item_json, simplifyVector = FALSE)[["assets"]]
stopifnot(all(sprintf("classified_%d", years) %in% names(assets)))
tifs <- vapply(years, function(y) {
  key <- sprintf("classified_%d", y)
  p <- fetch_once(assets[[key]][["href"]], file.path(out_dir, paste0(key, ".tif")))
  mh <- assets[[key]][["file:checksum"]]
  stopifnot(is.character(mh), startsWith(mh, "1220"), nchar(mh) == 68)
  got <- digest::digest(p, algo = "sha256", file = TRUE)
  if (!identical(got, substr(mh, 5, 68))) {
    unlink(c(p, item_json))
    stop(basename(p), ": sha256 ", got, " != published — deleted it and item.json")
  }
  p
}, character(1))
tick("download", t1)

rasters <- lapply(tifs, terra::rast)
names(rasters) <- years
stopifnot(!any(vapply(rasters, terra::inMemory, logical(1))))
message(sprintf("grid: %d x %d = %s cells",
                terra::nrow(rasters[[1]]), terra::ncol(rasters[[1]]),
                format(terra::ncell(rasters[[1]]), big.mark = ",")))

# --- 2. The scan the category is composed from -----------------------------
t2 <- Sys.time()
res <- dft_rast_break_class(rasters, source = "io-lulc")
tick("break_class", t2)

# --- 3. The function under test --------------------------------------------
t3 <- Sys.time()
cat_r <- dft_rast_break_category(res, filename = file.path(out_dir, "category.tif"),
                                 overwrite = TRUE)
tick("break_category", t3)
stopifnot(identical(names(cat_r), c("category", "strength")))

# --- 4. Reconcile against the committed four-level run ---------------------
# `changed` is derived from the transition layer here rather than taken from the
# category, so the crosstab is not the category compared against itself.
t4 <- Sys.time()
codes <- terra::deepcopy(res$raster)
terra::set.cats(codes, layer = 1, value = NULL)
changed <- terra::app(codes, fun = function(v) {
  if (!is.matrix(v)) stop("matrix chunks only")
  as.integer((v[, 1] %/% 1000L) != (v[, 1] %% 1000L))
}, filename = tempfile(fileext = ".tif"), wopt = list(datatype = "INT1U"))
ct <- terra::crosstab(c(changed, cat_r[["category"]]), long = TRUE, useNA = TRUE)
names(ct) <- c("changed", "category_label", "n_cells")
ct <- ct[!is.na(ct$changed), ]
ct$changed <- as.integer(ct$changed)   # never via as.character(): see below
ct$category_label <- as.character(ct$category_label)
tick("crosstab", t4)

ref <- utils::read.csv(ref_change, stringsAsFactors = FALSE)
fl <- ref$category_label == "flicker"
ref$category_label[fl] <- ifelse(as.integer(ref$changed[fl]) == 1L,
                                 "unsettled", "stable_flicker")
k_now <- paste(ct$changed, ct$category_label)
k_ref <- paste(ref$changed, ref$category_label)
if (anyDuplicated(k_now) || anyDuplicated(k_ref)) stop("a (changed, category) key repeats")
if (!setequal(k_now, k_ref)) {
  stop("category sets differ; only in the committed run: (",
       paste(setdiff(k_ref, k_now), collapse = ", "), "), only in this run: (",
       paste(setdiff(k_now, k_ref), collapse = ", "), ")")
}
idx <- match(k_now, k_ref)
if (!identical(as.integer(ct$n_cells), as.integer(ref$n_cells[idx]))) {
  print(data.frame(key = k_now, now = ct$n_cells, ref = ref$n_cells[idx]))
  stop("dft_rast_break_category() does not reproduce ", ref_change, " cell for cell")
}
# positive control: the comparator must be able to return FALSE
bad <- ct; bad$n_cells[1] <- bad$n_cells[1] + 1L
if (identical(as.integer(bad$n_cells), as.integer(ref$n_cells[idx]))) {
  stop("the comparator cannot fail; it is not a check")
}
message("reproduces the committed four-level BULK run cell for cell, mapped to five levels")

# strength must be the number the label was thresholded from, at scale
st <- terra::crosstab(c(cat_r[["strength"]], cat_r[["category"]]), long = TRUE, useNA = TRUE)
names(st) <- c("strength", "category_label", "n_cells")
st$category_label <- as.character(st$category_label)
# `%in%`, not `==`: crosstab(useNA = TRUE) carries an NA category row, and
# `df[cond, ]` with an NA in cond returns an all-NA ROW rather than dropping it,
# so `==` silently drags one into every subset and all(c(2, 3, NA) >= 2) is NA.
# as.integer() DIRECTLY. crosstab() returns numeric columns with NaN for the
# useNA group, and as.integer("NaN") is 0 with NO warning where as.integer(NaN)
# is NA -- so routing through a string publishes a strength of 0 for every
# category that has none, which is a plausible number and a wrong one.
stopifnot(is.numeric(st$strength))
st$strength <- as.integer(st$strength)
sus <- st[st$category_label %in% "break_sustained", ]
end <- st[st$category_label %in% "break_endpoint", ]
stopifnot(nrow(sus) > 0L, nrow(end) > 0L,                 # premise: both present
          !anyNA(sus$strength), !anyNA(end$strength),     # a clean switch always has one
          all(sus$strength >= 2L), all(end$strength == 1L))
# and the labels are nothing but that threshold, so the counts must reconcile
ref_sus <- ref$n_cells[ref$category_label == "break_sustained"]
ref_end <- ref$n_cells[ref$category_label == "break_endpoint"]
stopifnot(identical(sum(as.integer(sus$n_cells)), as.integer(ref_sus)),
          identical(sum(as.integer(end$n_cells)), as.integer(ref_end)))
message(sprintf("strength reconciles: %s sustained cells at strength >= 2, %s endpoint at 1",
                format(sum(sus$n_cells), big.mark = ","),
                format(sum(end$n_cells), big.mark = ",")))
utils::write.csv(st, file.path(out_dir, "summary_strength.csv"), row.names = FALSE)

ct$area_ha <- ct$n_cells * prod(terra::res(res$raster)) / 1e4
utils::write.csv(ct, file.path(out_dir, "summary_category.csv"), row.names = FALSE)
utils::write.csv(data.frame(stage = names(timings), seconds = unlist(timings)),
                 file.path(out_dir, "timings.csv"), row.names = FALSE)
message("BENCHMARK DONE")

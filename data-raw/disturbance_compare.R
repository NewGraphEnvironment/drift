# Compare drift's temporal evidence against dated provincial disturbance (drift#67).
#
# #62 measured the temporal composition of published change on four watershed groups
# (inst/notes/temporal-qa-groups.md). Every leg of that is internal to the imagery: it says
# whether labels settled, never whether anything happened on the ground. `floodplains` tags
# each published change patch with dated fire and harvest from DataBC, a source with no
# relationship to the classifier -- so comparing those dates against drift's `break_year` is
# the first external check available on the method.
#
# NAMED `compare`, NOT `corroborate`: the latter presumes the conclusion, and the most likely
# honest outcome here is that the published tags CANNOT corroborate `break_year` under a
# seven-year series (see `discriminates()` below).
#
# Reads only published assets from stac-floodplains-bc -- the seven `classified_<year>` COGs
# and `transition_vector.gpkg` of each item -- plus ONE machine-local file that is not
# published (see `subbasins` below). No database, no fwapg connection.
#
# Usage (from the repo root; one group per process so an RSS trace is per group):
#   Rscript data-raw/disturbance_compare.R bulk        # or necr, lnth, kotl
#   Rscript data-raw/disturbance_compare.R summarize   # assemble summary_groups.*
#
# Prefer data-raw/disturbance_compare-run.sh, which samples RSS and gates on the in-band
# `ALL STAGES DONE` marker rather than on the exit status.
#
# Outputs, data-raw/logs/disturbance_compare/<group>/ (the .tif, .gpkg, .json and .log files
# are gitignored; the CSVs and rss.txt are the committed evidence record):
#   summary_events.csv        - Phase 0. Tagged patches/area by (source, year), each year
#                               classed full / partial / none for whether it can discriminate,
#                               with distinct fire_number where an id is published.
#                               WRITTEN FIRST, before any agreement number exists.
#   summary_reconcile.csv     - Phase 1. 21,701 patches / 4,625.0 ha -> 7,161 / 3,627.2 ha,
#                               one row per named mechanism, deltas summing exactly.
#   summary_class_compare.csv - Phase 1. Per-transition-class reproduction against published.
#   join_audit.csv            - Phase 2. Proof the patch_id join is lossless.
#   summary_break_offset.csv  - Phase 2. break_year - disturbance_year, full distribution.
#   summary_flicker_strata.csv- Phase 3. Flicker in harvest-touching vs untagged residual,
#                               stratified by the #44 geometric signature.
#   group_meta.csv, timings.csv
# and from the summarize stage, in data-raw/logs/disturbance_compare/:
#   summary_reconcile_groups.csv, summary_events_groups.csv, summary_events_disc_groups.csv,
#   summary_agreement_groups.csv, summary_flicker_groups.csv - the note's tables, one CSV each
#   summary_groups.md         - those tables rendered, included verbatim in the note
#   summary_groups.csv        - the reconciliation summary, and the stage's COMPLETION MARKER:
#                               written last, after the note check, so its presence means the
#                               whole stage ran. Same content as summary_reconcile_groups.csv.
#
# ---------------------------------------------------------------------------
# THREE FACTS THAT SHAPE THIS SCRIPT. Each was verified before it was relied on; the
# verification is in planning/archive/*-issue-67-*/findings.md.
#
# 1. `patch_id` IS drift's own global key. dft_transition_vectors() assigns
#    `seq_len(nrow(polys_sf))` BEFORE the zone intersection, so the published ids are
#    drift's, with the zone clip having removed some. Measured: no duplicates in any of
#    the four published layers, and max(patch_id) > n in all four. So the join is a COLUMN
#    join. Rasterizing the published polygons instead would drop sub-cell fragments -- a
#    perimeter-to-area loss concentrated in small slivers, which are the high-flicker
#    population, and would therefore MANUFACTURE Phase 3's hypothesis.
#
# 2. The sustained/endpoint split IS `break_year`, deterministically. break_class_scan sets
#    break_year = years[idx+1], n_before = idx, n_after = n - idx, so with seven years
#    `pmin(n_before, n_after) >= 2` is exactly `break_year %in% 2019:2022`. A disturbance
#    year therefore discriminates the disturbance hypothesis from endpoint noise only
#    insofar as the break years it can reach (Y and Y+1) are sustained ones -- see
#    `discriminates()` below, which derives full / partial / none from `years`. Fire is a
#    handful of events either way, so Phase 2 is a case series, not a test.
#
# 3. `in_fire` / `in_harvest` is st_intersects -- TOUCHING, not containment -- and no
#    overlap fraction is published. Change concentrates at cutblock edges, and #62 measured
#    slivers flickering more than wider patches, so Phase 3 must stratify on shape or its
#    result is confounded by construction. This script never says "inside".
#
# NON-GOAL, stated so it is not read in: this does not measure containment in a cutblock.
# That needs the cutblock polygons, i.e. the database, and is out of scope.
# ---------------------------------------------------------------------------

suppressMessages({
  library(sf)
  library(terra)
  pkgload::load_all(".", quiet = TRUE)
})

groups <- c(bulk = "bulk_co_ff04", necr = "necr_ch_ff04",
            lnth = "lnth_ch_ff04", kotl = "kotl_bt_ff04")
years <- 2017:2023
# The 1 ha sieve floodplains passes to dft_rast_transition(). NOT published in the item
# properties -- read from floodplains/scripts/floodplain_lcc/03_lulc_classify.R:65
# (`patch_min_m2 <- 10000`), which is why the reconciliation has to TEST it rather than
# assert it. If the reproduction fails, this constant is the first thing to re-read.
patch_min_m2 <- 10000
# Which disturbance years can tell the disturbance hypothesis apart from endpoint noise.
#
# A break at index idx has n_before = idx, n_after = n - idx and break_year = years[idx+1],
# so "sustained" (pmin >= 2) is exactly break_year in years[3:(n-1)] = 2019..2022. A
# disturbance in calendar year Y shows up in the composite for Y or Y+1 -- IO LULC is
# annual and harvest_start_year_calendar is a START -- so Y discriminates only insofar as
# its REACHABLE break years are sustained ones. That is a three-level answer, not a window:
#
#   Y = 2017  reachable {2018}        endpoint only          -> none
#   Y = 2018  reachable {2018, 2019}  one of two sustained    -> partial
#   Y = 2019..2021  reachable both sustained                  -> full
#   Y = 2022  reachable {2022, 2023}  one of two sustained    -> partial
#   Y = 2023  reachable {2023}        endpoint only           -> none
#
# A first pass here used a flat `2019:2022` window and called it "the discriminating
# window". That was wrong in BOTH directions -- it excluded 2018, which is partial and
# holds the largest fire signal in the dataset (necr's 2018 fire put 414.7 ha at
# break_year 2019, a sustained break), and it called 2022 full when it is partial. The
# error was caught by the data, not by review. Derived from `years` below, never typed.
break_years <- years[-1]
# drift::dft_break_strength() is pmin(n_before, n_after) recovered from the break
# year, and dft_break_category() thresholds it at 2 to call a switch sustained --
# so this is that one definition rather than a fourth copy of it (#72). Every
# caller below intersects with `break_years` first, so the export's refusal of a
# year outside years[-1] is unreachable here and is a guard, not a branch.
is_sustained <- function(by) dft_break_strength(by, years) >= 2L
discriminates <- function(Y) {
  Y <- as.integer(Y)
  if (is.na(Y)) return(NA_character_)
  reach <- intersect(c(Y, Y + 1L), break_years)
  if (!length(reach)) return("none")
  s <- is_sustained(reach)
  if (all(s)) "full" else if (any(s)) "partial" else "none"
}
discriminates_v <- function(Y) vapply(Y, discriminates, character(1))
api_url <- "https://images.a11s.one/collections/stac-floodplains-bc/items"
log_root <- file.path("data-raw", "logs", "disturbance_compare")
# Not published in the STAC item: a floodplains step-2 product, gitignored there. Named and
# checksummed in group_meta.csv so the result does not silently depend on a local file, and
# the published ff04 polygon is measured beside it as the fallback zone.
subbasin_root <- path.expand("~/Projects/repo/floodplains/data")

arg <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(arg) || !(arg %in% c(names(groups), "summarize"))) {
  stop("usage: Rscript data-raw/disturbance_compare.R <", paste(names(groups), collapse = "|"),
       "|summarize>", call. = FALSE)
}

# --- helpers ---------------------------------------------------------------

tf <- function() tempfile(fileext = ".tif")

# Written by terra beside any factor raster it writes; an unlink() of the .tif alone leaves
# it behind. Guarded on length: paste0(character(0), ".aux.xml") is ".aux.xml", which
# unlink() would resolve in the working directory.
unlink_tif <- function(paths) {
  paths <- paths[nzchar(paths) & !is.na(paths)]
  if (length(paths)) unlink(c(paths, paste0(paths, ".aux.xml")))
  invisible(NULL)
}

# fetch to a temp file and rename on 200 only: a transport error mid-body would otherwise
# leave a truncated file under the name the next run trusts
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

# the item's `file:checksum` is a sha256 multihash: 0x12 (sha2-256), 0x20 (32 bytes), then
# the digest. A 200 + rename says the transfer completed; this says the bytes are the ones
# the catalogue published.
verify_checksum <- function(path, asset, item_json) {
  mh <- asset[["file:checksum"]]
  stopifnot(is.character(mh), startsWith(mh, "1220"), nchar(mh) == 68)
  got <- digest::digest(path, algo = "sha256", file = TRUE)
  if (!identical(got, substr(mh, 5, 68))) {
    unlink(c(path, item_json))
    stop(basename(path), ": sha256 ", got, " != published ", substr(mh, 5, 68),
         " - deleted it and item.json; re-run to fetch both again")
  }
  invisible(TRUE)
}

# One tidy row per (source, year). `carry_year` is the published column holding the
# disturbance date for that source; both sources are handled by one function so the two
# cannot drift apart in how they are counted.
event_rows <- function(p, source, flag_col, year_col, id_col = NULL) {
  sel <- !is.na(p[[flag_col]]) & p[[flag_col]] == 1L
  if (!any(sel)) {
    return(data.frame(source = source, year = NA_integer_, n_patches = 0L, area_ha = 0,
                      n_events = NA_integer_, discriminating = NA_character_)[0, ])
  }
  q <- p[sel, , drop = FALSE]
  yr <- as.integer(q[[year_col]])
  split_by <- factor(yr, levels = sort(unique(yr[!is.na(yr)])))
  do.call(rbind, lapply(levels(split_by), function(y) {
    k <- !is.na(yr) & yr == as.integer(y)
    data.frame(
      source = source, year = as.integer(y), n_patches = sum(k),
      area_ha = round(sum(q$area_ha[k]), 1),
      # harvest publishes no opening id, so events are uncountable for it -- NA, never 0,
      # which would read as "no events"
      # na.omit first: length(unique(x)) counts NA as one distinct value, so a year whose
      # fire-tagged patches all lack a fire_number would report 1 event for zero identified
      # fires -- inverting the reason NA rather than 0 is used for harvest just below.
      n_events = if (is.null(id_col)) NA_integer_
                 else length(unique(stats::na.omit(q[[id_col]][k]))),
      discriminating = discriminates(y))
  }))
}

# --- summarize stage -------------------------------------------------------

if (arg == "summarize") {
  # group_meta.csv, not summary_reconcile.csv: the per-group stage writes meta LAST, so its
  # presence is the marker that the whole run completed. Gating on an early file would accept
  # a run that died in Phase 3.
  need <- "group_meta.csv"
  have <- names(groups)[file.exists(file.path(log_root, names(groups), need))]
  if (length(have) < length(groups)) {
    stop("missing ", need, " for: ", paste(setdiff(names(groups), have), collapse = ", "))
  }
  # `x$group <- g` ERRORS on a 0-row frame ("replacement has 1 row, data has 0"), and both
  # event_rows() and offset_rows() legitimately return 0 rows -- so the empty guard that
  # exists to keep a 12-minute run alive was exactly the branch that killed the assembly.
  # rep(g, nrow(x)) is 0-row-safe.
  # Every group must have been produced by the same script. The column-presence stopifnots
  # below catch a RENAME; only this catches a redefinition that keeps the name.
  # DELIBERATE SCOPE: the four stamps are compared to each other, not to the file this stage
  # is running from, so "run all four, edit, summarize" passes. Both stages live in one file,
  # so comparing against the running file would invalidate four valid per-group stamps on any
  # cosmetic edit to the summarize half and force ~25 min of re-runs. The cross-group mixing
  # this exists to catch is the one that silently changes a published number.
  rd0 <- function(g, f) utils::read.csv(file.path(log_root, g, f))
  shas <- vapply(have, function(g) {
    m <- rd0(g, "group_meta.csv")
    if (!"script_sha" %in% names(m)) NA_character_ else as.character(m[["script_sha"]][1])
  }, character(1))
  if (anyNA(shas) || length(unique(shas)) != 1L) {
    stop("groups were produced by different script versions (or a meta predating script_sha): ",
         paste(sprintf("%s=%s", have, shas), collapse = ", "),
         " -- re-run every group with the current script before summarizing")
  }
  rd <- function(g, f) {
    x <- utils::read.csv(file.path(log_root, g, f))
    x$group <- rep(g, nrow(x))
    x
  }

  # Q1: did the reconciliation close?
  recon <- do.call(rbind, lapply(have, function(g) {
    r <- rd(g, "summary_reconcile.csv")
    pick <- function(s, col) { v <- r[r$step == s, col]; if (length(v) == 1) v else NA_real_ }
    data.frame(group = g,
               drift_patches = pick("unsieved_vectorize", "n_patches"),
               drift_ha = pick("unsieved_vectorize", "area_ha"),
               pub_patches = pick("published", "n_patches"),
               pub_ha = pick("published", "area_ha"),
               repro_patches = pick("after_zone_clip", "n_patches"),
               repro_ha = pick("after_zone_clip", "area_ha"),
               sieve_ha = pick("unsieved_vectorize", "area_ha") -
                 pick("after_sieve_unclipped", "area_ha"),
               clip_ha = pick("after_sieve_unclipped", "area_ha") -
                 pick("after_zone_clip", "area_ha"))
  }))
  # `reproduced` is NOT re-derived here. The per-group stage computes it on RAW values; these
  # columns come from a CSV already rounded to 1 dp, so an independent `abs(d) < 0.1` test
  # here would sit on a floating-point boundary and could disagree with the authoritative one.
  # One fact, derived once, read back -- with the class counts carried so "0 of 53 classes
  # differ" is a generated cell rather than a hand-transcribed claim.
  cls <- do.call(rbind, lapply(have, function(g) {
    c2 <- rd(g, "summary_class_compare.csv")
    gm2 <- rd(g, "group_meta.csv")
    stopifnot("reconciled" %in% names(gm2))
    data.frame(group = g, n_classes = nrow(c2), n_classes_differ = sum(c2$d_n != 0),
               max_abs_d_ha = max(abs(c2$d_ha)), reproduced = gm2[["reconciled"]])
  }))
  recon <- merge(recon, cls, by = "group", sort = FALSE)

  # Q2: the discriminating sample, and the offsets in it
  events <- do.call(rbind, lapply(have, function(g) rd(g, "summary_events.csv")))
  ev <- do.call(rbind, lapply(have, function(g) {
    e <- events[events$group == g, ]
    d <- e[!is.na(e$discriminating) & e$discriminating %in% c("full", "partial"), ]
    gm <- rd(g, "group_meta.csv")
    # `$` on a data.frame returns NULL for a missing column and data.frame() silently DROPS a
    # NULL argument, so a meta predating this column would ship a table quietly missing it.
    stopifnot("n_fire_events_disc" %in% names(gm))
    # sum() is always length 1, so no emptiness guard is needed or possible here; an empty
    # selection already sums to 0.
    f <- function(src, col, lvl) {
      sum(d[d$source == src & d$discriminating %in% lvl, col], na.rm = TRUE)
    }
    data.frame(group = g,
               fire_patches_full = f("fire", "n_patches", "full"),
               fire_patches_partial = f("fire", "n_patches", "partial"),
               fire_ha_disc = f("fire", "area_ha", c("full", "partial")),
               # distinct fires, read from the per-group meta -- NOT summed across year rows.
               # `[[` and an explicit stopifnot: `$` on a data.frame returns NULL for a missing
               # column and data.frame() silently DROPS a NULL argument, so a stale meta would
               # ship a table quietly missing this column rather than failing.
               fire_events_disc = gm[["n_fire_events_disc"]],
               harv_patches_full = f("harvest", "n_patches", "full"),
               harv_patches_partial = f("harvest", "n_patches", "partial"),
               harv_ha_disc = f("harvest", "area_ha", c("full", "partial")))
  }))

  off <- do.call(rbind, lapply(have, function(g) rd(g, "summary_break_offset.csv")))
  # Agreement is lag 0 or +1: IO LULC is an annual composite and harvest_start_year is a
  # START, so a stand cut late in a year need not change class until the next composite.
  # Pre-registered here, not chosen after seeing the distribution.
  # THE DENOMINATOR IS CONDITIONED ON THE OUTCOME and both halves are published so it cannot
  # be read as an unconditional agreement rate. `offset_rows()` keeps only patches that have a
  # modal break year at all, so a tagged patch that never produced a clean break cell
  # contributes no row -- flicker is 40-49% of changed area (#62), so the excluded set is not
  # small. `n_tagged` is every tagged patch in a discriminating year; `n_with_break` is the
  # subset that reached the offset distribution; `pct_lag01` is over `n_with_break`.
  # Both denominators come from summary_break_offset.csv, so they are two subsets of one
  # population: `n_tagged` is every tagged patch in a discriminating year, `n_with_break` the
  # subset with a modal break year (offset non-NA). THE RATE IS CONDITIONED ON THE OUTCOME and
  # both denominators are published so it cannot be read as an unconditional agreement rate.
  agree <- do.call(rbind, lapply(have, function(g) {
    o <- off[off$group == g & off$discriminating %in% c("full", "partial"), ]
    f <- function(src) {
      q <- o[o$source == src, ]
      n_tag <- sum(q$n_patches)
      n_brk <- sum(q$n_patches[!is.na(q$offset)])
      k <- sum(q$n_patches[!is.na(q$offset) & q$offset %in% c(0L, 1L)])
      data.frame(source = src, n_tagged = n_tag, n_with_break = n_brk, n_lag01 = k,
                 pct_lag01_of_break = if (n_brk > 0) round(100 * k / n_brk, 1) else NA_real_,
                 pct_lag01_of_tagged = if (n_tag > 0) round(100 * k / n_tag, 1) else NA_real_)
    }
    cbind(group = g, rbind(f("fire"), f("harvest")))
  }))

  # Q3: flicker, harvest-touching against the untagged residual, stratified
  flick <- do.call(rbind, lapply(have, function(g) rd(g, "summary_flicker_strata.csv")))

  # The per-group stage clears its own CSVs and writes its marker last; this stage had the
  # defect that fix removed. An error during construction -- R3-1's 0-row crash fires before
  # any write -- would leave all six files from a PREVIOUS summarize sitting over freshly
  # regenerated per-group CSVs, with nothing able to tell. Clear first, and write
  # summary_groups.csv LAST so its presence is the marker.
  dir.create(log_root, recursive = TRUE, showWarnings = FALSE)
  stale <- file.path(log_root, c("summary_reconcile_groups.csv", "summary_events_groups.csv",
                                 "summary_events_disc_groups.csv",
                                 "summary_agreement_groups.csv", "summary_flicker_groups.csv",
                                 "summary_groups.md", "summary_groups.csv"))
  stale <- stale[file.exists(stale)]
  if (length(stale) && !all(file.remove(stale))) {
    stop("could not clear stale summarize outputs in ", log_root)
  }
  utils::write.csv(recon, file.path(log_root, "summary_reconcile_groups.csv"), row.names = FALSE)
  utils::write.csv(events, file.path(log_root, "summary_events_groups.csv"), row.names = FALSE)
  # the discriminating-sample table is where Phase 0's pre-registration lands, so it needs a
  # machine-readable artifact rather than existing only inside summary_groups.md
  utils::write.csv(ev, file.path(log_root, "summary_events_disc_groups.csv"), row.names = FALSE)
  utils::write.csv(agree, file.path(log_root, "summary_agreement_groups.csv"), row.names = FALSE)
  utils::write.csv(flick, file.path(log_root, "summary_flicker_groups.csv"), row.names = FALSE)

  md <- c(
    "## Reconciliation: drift's change patches against the published transition layer",
    "",
    knitr::kable(recon),
    "",
    "## Discriminating sample: disturbance years whose reachable break years are sustained",
    "",
    knitr::kable(ev),
    "",
    "## Agreement at lag 0 or +1, discriminating disturbance years only (full + partial)",
    "",
    knitr::kable(agree),
    "",
    "## Flicker: harvest-touching against the untagged residual, by geometric stratum",
    "",
    knitr::kable(flick))
  writeLines(md, file.path(log_root, "summary_groups.md"))

  # The note must contain the generated tables verbatim, or it is quoting numbers that no
  # longer exist. Same guard as break_class_groups.R.
  # The note is committed, so its absence is a failure, not a reason to skip the check --
  # `if (file.exists(note))` alone is a guard that fails toward pass.
  note <- file.path("inst", "notes", "temporal-qa-disturbance.md")
  if (!file.exists(note)) stop(note, " is missing; it is a committed artifact of this script")
  body <- paste(readLines(note), collapse = "\n")
  if (!grepl(paste(md, collapse = "\n"), body, fixed = TRUE)) {
    stop("inst/notes/temporal-qa-disturbance.md does not contain summary_groups.md verbatim; ",
         "rebuild the note from the generated tables. NOTE: summary_groups.csv was cleared at ",
         "the start of this stage and has NOT been rewritten -- re-run summarize once the note ",
         "is updated, or `git checkout` it.")
  }
  message("note tables match summary_groups.md")
  # written LAST, after the note check, so its presence means the whole stage completed
  utils::write.csv(recon, file.path(log_root, "summary_groups.csv"), row.names = FALSE)
  message("SUMMARIZE DONE")
  quit(save = "no", status = 0)
}

# --- per-group stage -------------------------------------------------------

g <- arg
item <- groups[[g]]
out_dir <- file.path(log_root, g)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
# Clear this group's outputs before writing any of them. Without this a run that dies partway
# refreshes the early CSVs and leaves the later ones from a previous run, and nothing
# downstream can tell the two apart -- the note would then be assembled from two runs and
# report success. group_meta.csv is written LAST and is what `summarize` gates on, so the
# invariant is: meta present => every CSV beside it came from the same run.
# file.remove() WARNS rather than errors on failure, and a warning is one line in a run.log
# the wrapper only greps for error|halted -- so an unchecked clear leaves the invariant
# ("meta present => every CSV beside it came from the same run") silently false.
stale_csv <- Sys.glob(file.path(out_dir, "*.csv"))
if (length(stale_csv) && !all(file.remove(stale_csv))) {
  stop("could not clear stale CSVs in ", out_dir)
}
tmp_tifs <- character(0)
# withr::defer(envir = globalenv()), NOT on.exit(): at a script's top level the current
# frame IS the global environment, which never exits, so an on.exit() handler here is
# registered and never called (code-check-r.md). It prints "Ran 1/1 deferred expressions",
# which is the confirmation it worked.
withr::defer(unlink_tif(tmp_tifs), envir = globalenv())

t0 <- Sys.time()
# Hashed HERE, not where meta is written. digest(file =) opens the path fresh, so computing it
# at the end of the run records the file's state when the run FINISHED -- and a file edited
# mid-run would then stamp the post-edit sha onto CSVs the pre-edit code produced, making the
# uniformity check in `summarize` accept two definitions. That is this guard failing toward
# pass, on the guard that exists to stop precisely that. digest() errors loudly on an
# unresolvable path, so a bad working directory is a stop rather than an NA.
script_sha <- substr(digest::digest(file = "data-raw/disturbance_compare.R",
                                    algo = "sha256"), 1, 12)
timings <- list()
tick <- function(label, start) {
  el <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  message(sprintf("[%7.1fs] %s: %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs")),
                  label, el))
  timings[[label]] <<- el
  invisible(el)
}

# --- 1. Published assets, verified against the item's checksums ----
t1 <- Sys.time()
item_json <- fetch_once(paste0(api_url, "/", item), file.path(out_dir, "item.json"))
meta_json <- jsonlite::fromJSON(item_json, simplifyVector = FALSE)
assets <- meta_json[["assets"]]
props <- meta_json[["properties"]]
stopifnot(all(sprintf("classified_%d", years) %in% names(assets)),
          "transition_vector" %in% names(assets))
tifs <- vapply(years, function(y) {
  key <- sprintf("classified_%d", y)
  p <- fetch_once(assets[[key]][["href"]], file.path(out_dir, paste0(key, ".tif")))
  verify_checksum(p, assets[[key]], item_json)
  p
}, character(1))
gpkg_tr <- fetch_once(assets[["transition_vector"]][["href"]],
                      file.path(out_dir, "transition_vector.gpkg"))
verify_checksum(gpkg_tr, assets[["transition_vector"]], item_json)
tick("download", t1)

# The published items were produced by drift 0.13.0 (nge:drift_version). The reconciliation
# below re-runs dft_rast_transition() and dft_transition_vectors() from the CURRENT tree and
# asserts it reproduces them, which is only a fair test if those two files have not moved.
# Verified at planning time: both are byte-identical to v0.13.0. Recorded, not asserted at
# runtime -- a future divergence should show up as a reconciliation failure with this line
# to read, rather than as a refusal that stops the run.
message(item, ": published by drift ", props[["nge:drift_version"]],
        ", running ", as.character(utils::packageVersion("drift")))

rasters <- lapply(tifs, terra::rast)
names(rasters) <- years
stopifnot(identical(as.integer(names(rasters)), years))
for (r in rasters[-1]) stopifnot(terra::compareGeom(rasters[[1]], r, stopOnError = FALSE))
stopifnot(!any(vapply(rasters, terra::inMemory, logical(1))))
ref <- rasters[[1]]
epsg <- terra::crs(ref, describe = TRUE)$code
cell_ha <- prod(terra::res(ref)) * 1e-4

published <- sf::st_read(gpkg_tr, layer = "transition", quiet = TRUE)
stopifnot(nrow(published) > 0)

# --- 2. Phase 0: the sample, pre-registered BEFORE any agreement number ----
# Written first and on its own, so a near-empty discriminating window is a RESULT rather
# than something discovered while writing up an agreement statistic.
t1 <- Sys.time()
ev <- rbind(
  event_rows(published, "fire", "in_fire", "fire_year", "fire_number"),
  event_rows(published, "harvest", "in_harvest", "harvest_start_year_calendar", NULL))
# n_events in summary_events.csv is per YEAR, so summing it across years would double-count a
# fire spanning two of them. The distinct count over the discriminating set is computed here,
# once, and carried in group_meta.csv.
disc_fire <- published[!is.na(published$in_fire) & published$in_fire == 1 &
                         discriminates_v(published$fire_year) %in% c("full", "partial"), ]
n_fire_events_disc <- length(unique(disc_fire$fire_number[!is.na(disc_fire$fire_number)]))
utils::write.csv(ev, file.path(out_dir, "summary_events.csv"), row.names = FALSE)
tick("events", t1)
print(ev)
message("  discriminating: full ", sum(ev$n_patches[ev$discriminating == "full"]),
        " / partial ", sum(ev$n_patches[ev$discriminating == "partial"]),
        " / none ", sum(ev$n_patches[ev$discriminating == "none"]), " patches tagged")

# --- 3. Phase 1: reconcile ----
# Two mechanisms in floodplains, and they move count and area in OPPOSITE directions:
#   (a) dft_rast_transition(patch_area_min = 10000) sieves 8-connected components of a
#       CLASS-AGNOSTIC changed mask, so a mixed blob >= 1 ha survives whole;
#   (b) dft_transition_vectors() then builds components of SAME-VALUED cells, so that blob
#       re-splits into many sub-1-ha polygons -- which is why 3,627.2 ha yields 7,161
#       features where a per-class 0.5 ha filter on drift's own output gives 1,471.
#   (c) the zone clip trims geometry, drops patches falling outside, and can split
#       straddling ones (asserted zero here: every group has one sub-basin).
t1 <- Sys.time()
classified <- dft_rast_classify(rasters, source = "io-lulc")
tick("classify", t1)

subbasin_file <- file.path(subbasin_root, g, "subbasins.gpkg")
if (!file.exists(subbasin_file)) {
  stop("subbasins.gpkg not found at ", subbasin_file, ". It is a floodplains step-2 product ",
       "and is NOT published in the STAC item, so the exact reconciliation cannot run ",
       "without it. Clone/refresh floodplains, or read the ff04 fallback numbers in ",
       "summary_reconcile.csv from a machine that has it.", call. = FALSE)
}
subbasins <- sf::st_read(subbasin_file, layer = "subbasins", quiet = TRUE)
subbasin_md5 <- unname(tools::md5sum(subbasin_file))
stopifnot(nrow(subbasins) >= 1)
if (!"name_basin" %in% names(subbasins)) stop("subbasins has no `name_basin` column")

t1 <- Sys.time()
trans <- dft_rast_transition(classified, from = as.character(years[1]),
                             to = as.character(years[length(years)]),
                             patch_area_min = patch_min_m2)
tick("transition_sieved", t1)

t1 <- Sys.time()
pat_sv <- dft_transition_vectors(trans$raster, changes_only = TRUE)
tick("vectors_sieved", t1)
message("  sieved, unclipped: ", nrow(pat_sv), " patches, ", round(sum(pat_sv$area_ha), 1), " ha")

t1 <- Sys.time()
pat_cl <- dft_transition_vectors(trans$raster, zones = subbasins, zone_col = "name_basin",
                                 changes_only = TRUE)
# floodplains recomputes area from geometry post-intersection (03_lulc_classify.R:213);
# drift's own column is pre-intersection, so summing it double-counts a straddling patch.
pat_cl$area_ha <- as.numeric(sf::st_area(pat_cl)) * 1e-4
tick("vectors_clipped", t1)

# The #44 geometric signature, needed by Phase 3's stratification. Tagged on the SIEVED,
# UNCLIPPED patches -- the population the join uses -- while trans$raster is still alive.
t1 <- Sys.time()
pat_sv <- dft_transition_artifact(pat_sv, trans$raster)
tick("artifact", t1)

# Free the sieved grid before break_class allocates its own. terra holds a result in memory
# whenever it fits, and these are 56M-204M cell grids.
trans_geom <- c(dim(trans$raster)[1:2], terra::res(trans$raster), as.vector(terra::ext(trans$raster)))
trans_cats <- terra::cats(trans$raster)[[1]]
rm(trans); invisible(gc(verbose = FALSE))

# --- 4. Phase 1 continued: the unsieved baseline, from break_class ----
# dft_rast_break_class()$raster is documented identical to
# dft_rast_transition(x, from = first, to = last)$raster, so this is the unsieved transition
# and costs no extra pass. That premise supplies the WHOLE `unsieved_vectorize` row of
# summary_reconcile.csv and hence `sieve_ha`, and the sieve delta is large either way -- so a
# divergence in geometry or class encoding between the two rasters would be absorbed silently
# and the "deltas sum exactly" property could not fail. Assert it rather than assert that it
# is asserted: the geometry and the category table are captured BEFORE `trans` is freed and
# compared after, so the check costs no second full-grid raster.
t1 <- Sys.time()
res <- dft_rast_break_class(classified)
tick("break_class", t1)
res_geom <- c(dim(res$raster)[1:2], terra::res(res$raster), as.vector(terra::ext(res$raster)))
stopifnot(identical(trans_geom, res_geom))
# The sieved raster's categories are a SUBSET of the unsieved one's -- the sieve can remove a
# transition class entirely -- so this is subset, not identity, and it is the direction that
# matters: a class present after sieving and absent before would mean the two rasters do not
# describe the same transition.
stopifnot(all(trans_cats[[2]] %in% terra::cats(res$raster)[[1]][[2]]))

t1 <- Sys.time()
pat_unsv <- dft_transition_vectors(res$raster, changes_only = TRUE)
tick("vectors_unsieved", t1)
message("  unsieved: ", nrow(pat_unsv), " patches, ", round(sum(pat_unsv$area_ha), 1), " ha")

dropped_ids <- setdiff(pat_sv$patch_id, pat_cl$patch_id)
split_rows <- nrow(pat_cl) - length(unique(pat_cl$patch_id))
# `max(published$patch_id) - nrow(published)` is a LOWER BOUND on patches the zone clip
# dropped, not an equality: ids dropped ABOVE the surviving maximum leave no trace in the
# published layer at all. Measured on lnth: 9 dropped, the published-only predictor says 8,
# because patch 2762 was itself dropped. Report both so the gap reads as arithmetic rather
# than as a reconciliation failure.
pub_pred_drop <- max(published$patch_id) - nrow(published)

recon <- data.frame(
  step = c("unsieved_vectorize", "after_sieve_unclipped", "after_zone_clip", "published"),
  mechanism = c("drift, changes_only, no filter",
                "class-agnostic 1 ha sieve in dft_rast_transition()",
                "st_intersection with subbasins; area recomputed from geometry",
                "stac-floodplains-bc transition_vector.gpkg"),
  n_patches = c(nrow(pat_unsv), nrow(pat_sv), nrow(pat_cl), nrow(published)),
  area_ha = round(c(sum(pat_unsv$area_ha), sum(pat_sv$area_ha), sum(pat_cl$area_ha),
                    sum(published$area_ha)), 1))
recon$d_n <- c(NA_integer_, diff(recon$n_patches))
recon$d_ha <- c(NA_real_, round(diff(recon$area_ha), 1))
utils::write.csv(recon, file.path(out_dir, "summary_reconcile.csv"), row.names = FALSE)
print(recon)
message("  patches dropped entirely by the clip: ", length(dropped_ids),
        " (published max(patch_id) - n is a lower bound at ", pub_pred_drop, ")")
message("  rows split across sub-basins: ", split_rows, " (expected 0, one sub-basin)")

# Per-transition-class reproduction. A matching TOTAL with mismatched classes is a
# different pipeline agreeing by luck, so this is the assertion that matters.
agg <- function(x, lbl) {
  a <- stats::aggregate(cbind(n = rep(1, nrow(x)), ha = x$area_ha),
                        by = list(transition = x$transition), FUN = sum)
  names(a) <- c("transition", paste0("n_", lbl), paste0("ha_", lbl))
  a
}
cmp <- merge(agg(sf::st_drop_geometry(pat_cl), "repro"),
             agg(sf::st_drop_geometry(published), "pub"),
             by = "transition", all = TRUE)
for (cc in names(cmp)[-1]) cmp[[cc]][is.na(cmp[[cc]])] <- 0
cmp$d_n <- cmp$n_repro - cmp$n_pub
cmp$d_ha <- round(cmp$ha_repro - cmp$ha_pub, 2)
cmp <- cmp[order(-cmp$ha_pub), ]
utils::write.csv(cmp, file.path(out_dir, "summary_class_compare.csv"), row.names = FALSE)
reproduced <- nrow(pat_cl) == nrow(published) &&
  abs(sum(pat_cl$area_ha) - sum(published$area_ha)) < 0.1 &&
  all(cmp$d_n == 0)
message("  per-class reproduction: ", sum(cmp$d_n != 0), " of ", nrow(cmp),
        " classes differ in count; max |d_ha| ", round(max(abs(cmp$d_ha)), 2))
message("  RECONCILED: ", reproduced)

# --- 5. Phase 2/3: join published disturbance tags onto drift's temporal evidence ----
# By patch_id, on the SIEVED UNCLIPPED patches: their boundaries lie on cell edges by
# construction (terra::as.polygons), so rasterizing them back is exact. The published
# polygons are post-intersection and sub-cell in places, and rasterize takes a cell on its
# CENTRE -- rasterizing those would drop fragments, a loss concentrated in slivers.
t1 <- Sys.time()
pid_r <- terra::rasterize(terra::vect(pat_sv), res$raster, field = "patch_id", filename = tf())
tmp_tifs <- c(tmp_tifs, terra::sources(pid_r))
names(pid_r) <- "patch_id"

# crosstab(), NOT zonal(). terra's zonal C++ fast path covers only
# {max,min,mean,sum,notNA,isNA}; anything else -- modal, a quantile, a closure -- falls back
# to as.data.frame() over the WHOLE grid, which is 169M-204M rows here. crosstab is streamed
# C++ and, with long = TRUE, returns only observed combinations. It also gives the exact NA
# count, which zonal(na.rm = TRUE) throws away.
ct_by <- terra::crosstab(c(pid_r, res$breaks[["break_year"]]), long = TRUE, useNA = TRUE)
names(ct_by) <- c("patch_id", "break_year", "n_cells")
ct_nf <- terra::crosstab(c(pid_r, res$breaks[["n_flips"]]), long = TRUE, useNA = TRUE)
names(ct_nf) <- c("patch_id", "n_flips", "n_cells")
ct_by <- ct_by[!is.na(ct_by$patch_id), ]
ct_nf <- ct_nf[!is.na(ct_nf$patch_id), ]
tick("crosstab", t1)

# Join audit: committed evidence that the join is lossless, not a check that passes quietly.
cells_by_patch <- stats::aggregate(n_cells ~ patch_id, ct_nf, sum)   # never empty: pat_sv is non-empty
zero_cell <- setdiff(pat_sv$patch_id, cells_by_patch$patch_id)
# The totals below are aggregate identities: a rasterize() that assigned a cell to the WRONG
# neighbouring patch conserves both of them and would read clean. The per-patch delta is what
# actually says the join is lossless, so it is a row here rather than an assumption.
mm <- merge(data.frame(patch_id = pat_sv$patch_id, ha = pat_sv$area_ha), cells_by_patch,
            by = "patch_id")
per_patch_delta <- if (nrow(mm)) max(abs(mm$ha - mm$n_cells * cell_ha)) else NA_real_
audit <- data.frame(
  metric = c("patches_in", "patches_with_cells", "patches_zero_cells",
             "cells_total", "area_from_cells_ha", "area_from_geometry_ha",
             "max_abs_patch_ha_delta",
             "published_patch_ids_matched", "published_patch_ids_unmatched",
             "patches_not_tag_evaluated"),
  value = c(nrow(pat_sv), nrow(cells_by_patch), length(zero_cell),
            sum(cells_by_patch$n_cells), round(sum(cells_by_patch$n_cells) * cell_ha, 2),
            round(sum(pat_sv$area_ha), 2),
            signif(per_patch_delta, 3),
            length(unique(published$patch_id[published$patch_id %in% pat_sv$patch_id])),
            length(unique(published$patch_id[!published$patch_id %in% pat_sv$patch_id])),
            sum(!pat_sv$patch_id %in% published$patch_id)))
# NOT written yet: three more rows depend on ev_patch, which is built below. Writing here
# and appending later would leave a join_audit.csv on disk that is missing rows whenever the
# run dies in between -- the partial-artifact problem this script now guards against.
print(audit)

# Per-patch temporal evidence, with denominators that are explicit rather than implied.
# flicker_frac is n(n_flips >= 2) / n(non-NA n_flips): n_flips is NA wherever any year is
# NA, and IO LULC carries Clouds and No Data as real classes, so the NA count is published
# beside it rather than silently forming a different denominator per patch.
# stats::aggregate() ERRORS with "no rows to aggregate" on an empty subset rather than
# returning a 0-row frame, and every one of these subsets is legitimately empty on some
# input: lnth has no NA n_flips cells at all. Guard once, here, so an empty stratum stays a
# zero rather than aborting a 12-minute run at its last step.
agg_cells <- function(sub, nm) {
  if (!nrow(sub)) {
    out <- data.frame(patch_id = numeric(0), x = numeric(0))
    names(out)[2] <- nm
    return(out)
  }
  out <- stats::aggregate(n_cells ~ patch_id, sub, sum)
  names(out)[2] <- nm
  out
}
tot <- agg_cells(ct_nf[!is.na(ct_nf$n_flips), ], "n_valid")
nas <- agg_cells(ct_nf[is.na(ct_nf$n_flips), ], "n_na")
fl <- agg_cells(ct_nf[!is.na(ct_nf$n_flips) & ct_nf$n_flips >= 2, ], "n_flicker")
br <- agg_cells(ct_nf[!is.na(ct_nf$n_flips) & ct_nf$n_flips == 1, ], "n_break")

# Modal break year per patch -- the statistic zonal() cannot compute at this scale.
# NOTE the definition, which is looser than "the patch broke cleanly in year Y": it is the
# modal break year among the patch's BREAK CELLS ONLY. A patch that is 90% flicker and 10%
# clean break still gets a break_year_modal, from that 10%. No minimum break fraction is
# imposed -- `break_frac` is carried alongside so a reader can impose one -- and the offset
# distribution below must be described as covering tagged patches with at least one break
# cell, not cleanly-broken patches.
byv <- ct_by[!is.na(ct_by$break_year), ]
modal_by <- byv[order(byv$patch_id, -byv$n_cells), ]
modal_by <- modal_by[!duplicated(modal_by$patch_id), c("patch_id", "break_year")]
names(modal_by)[2] <- "break_year_modal"

ev_patch <- sf::st_drop_geometry(pat_sv)[, c("patch_id", "transition", "area_ha",
                                             "flag_sliver", "flag_boundary", "flag_reciprocal")]
for (d in list(tot, nas, fl, br, modal_by)) ev_patch <- merge(ev_patch, d, by = "patch_id", all.x = TRUE)
for (cc in c("n_valid", "n_na", "n_flicker", "n_break")) ev_patch[[cc]][is.na(ev_patch[[cc]])] <- 0L
ev_patch$flicker_frac <- ifelse(ev_patch$n_valid > 0, ev_patch$n_flicker / ev_patch$n_valid, NA_real_)
ev_patch$break_frac <- ifelse(ev_patch$n_valid > 0, ev_patch$n_break / ev_patch$n_valid, NA_real_)

# Disturbance tags, by patch_id. Published rows are unique on patch_id in all four groups
# (measured), but a straddling patch would repeat it, so collapse defensively: any() for the
# flags, and the year of the largest fragment for the date.
pubd <- sf::st_drop_geometry(published)[, c("patch_id", "area_ha", "in_fire", "fire_year",
                                            "fire_number", "in_harvest",
                                            "harvest_start_year_calendar")]
pubd <- pubd[order(pubd$patch_id, -pubd$area_ha), ]
# na.action = na.pass, and an all.x merge. aggregate.formula applies na.omit to the model
# frame BEFORE FUN runs, so the `na.rm = TRUE` inside FUN is dead code and any row with NA in
# EITHER flag is deleted outright -- an inner merge would then drop the patch, and the
# all.x merge below would set both flags to 0, turning a tagged patch into an untagged one.
# Measured: all four published layers currently carry these as logical with zero NAs, so this
# is latent rather than live; it is guarded because `event_rows()` above already assumes NA is
# possible, and two consumers of one column disagreeing is how that becomes live silently.
flags <- stats::aggregate(cbind(in_fire, in_harvest) ~ patch_id, pubd,
                          FUN = function(v) as.integer(any(v == 1, na.rm = TRUE)),
                          na.action = stats::na.pass)
firstrow <- pubd[!duplicated(pubd$patch_id), c("patch_id", "fire_year", "fire_number",
                                               "harvest_start_year_calendar")]
pubd <- merge(flags, firstrow, by = "patch_id", all.x = TRUE)
ev_patch <- merge(ev_patch, pubd, by = "patch_id", all.x = TRUE)
# `tag_evaluated` before the NA fill, and it is load-bearing for Phase 3. ev_patch is built
# from the sieved UNCLIPPED patches; the tags come from the clipped published layer. A patch
# the zone clip dropped has no published row, so the fill below would turn it into
# in_fire = 0, in_harvest = 0 -- indistinguishable from a patch floodplains evaluated against
# both layers and found matching neither. It was never evaluated: it lies outside the
# sub-basin. The contamination is one-directional (such a patch can only ever join the
# residual, never a tagged population) and group-dependent: 30 / 18 / 9 patches on
# bulk / necr / lnth but 219 on kotl, where it would be 4.4% of the residual by count and up
# to ~4.9% by area weight -- an order of magnitude apart, which would also break the
# cross-group comparability the note's Q3 conclusion leans on.
ev_patch$tag_evaluated <- ev_patch$patch_id %in% published$patch_id
# The clip does not only DROP patches, it also TRIMS the ones that straddle the sub-basin
# boundary -- those keep tag_evaluated = TRUE while their tags were evaluated on the fragment
# only. Weighting Phase 3 by the full unclipped `area_ha` would give such a patch more weight
# than the geometry the tag actually saw, the same one-directional contamination as the
# dropped patches, one axis over. `area_ha_eval` is the published (clipped) area where the
# patch was evaluated and NA otherwise, and it is what Phase 3 weights by.
pub_area <- stats::aggregate(area_ha ~ patch_id, sf::st_drop_geometry(published), sum)
names(pub_area)[2] <- "area_ha_eval"
ev_patch <- merge(ev_patch, pub_area, by = "patch_id", all.x = TRUE)
# aggregate.formula na.omits the model frame BEFORE FUN, so a published row with an NA
# area_ha yields NO pub_area row -- which would make `tag_evaluated & is.na(area_ha_eval)` a
# THIRD state, silently excluded from every Phase 3 population and counted nowhere.
# `na.action = na.pass` is not the fix (sum(c(1, NA)) is NA, so the state persists); make it
# loud instead. Latent today -- all four published layers carry non-NA area_ha.
n_eval_no_area <- sum(ev_patch$tag_evaluated & is.na(ev_patch$area_ha_eval))
if (n_eval_no_area > 0) {
  stop(n_eval_no_area, " patches are tag_evaluated but have no published area; Phase 3 would ",
       "drop them from every population without counting them")
}
n_trimmed <- sum(ev_patch$tag_evaluated &
                   (ev_patch$area_ha - ev_patch$area_ha_eval) > 1e-6)
trimmed_ha <- sum(ev_patch$area_ha[ev_patch$tag_evaluated] -
                    ev_patch$area_ha_eval[ev_patch$tag_evaluated])
for (cc in c("in_fire", "in_harvest")) ev_patch[[cc]][is.na(ev_patch[[cc]])] <- 0L
utils::write.csv(ev_patch, file.path(out_dir, "summary_patch_join.csv"), row.names = FALSE)

# Phase 3 keys on the FLAG (a touching question) while Phases 0 and 2 group on the YEAR, so a
# patch flagged with no date is in one and not the others. Correct in both, but the two
# populations differ, and an uncounted difference between two definitions of "fire-tagged" is
# how the next reader draws them as one number.
pubf <- sf::st_drop_geometry(published)
audit <- rbind(audit, data.frame(
  # `patches_no_valid_flip_cells` is the third state this file previously excluded from one
  # population and included in another with nothing counting it: a patch whose every cell has
  # n_flips = NA has flicker_frac = break_frac = NA, so Phase 3 drops it while offset_rows()
  # keeps it (its break_frac is filled to 0, which is value-correct). Both behaviours are
  # right; the count is what makes the two denominators reconcilable.
  # `fire_flag_without_number` matters because `length(unique(x))` counts NA as one distinct
  # value, so an unnumbered fire would otherwise read as an event.
  metric = c("patches_trimmed_by_clip", "trimmed_ha", "fire_flag_without_year",
             "harvest_flag_without_year", "fire_flag_without_number",
             "patches_no_valid_flip_cells", "no_valid_flip_ha"),
  value = c(n_trimmed, round(trimmed_ha, 2),
            sum(pubf$in_fire == 1 & is.na(pubf$fire_year), na.rm = TRUE),
            sum(pubf$in_harvest == 1 & is.na(pubf$harvest_start_year_calendar), na.rm = TRUE),
            sum(pubf$in_fire == 1 & is.na(pubf$fire_number), na.rm = TRUE),
            sum(ev_patch$n_valid == 0),
            round(sum(ev_patch$area_ha[ev_patch$n_valid == 0]), 2))))
utils::write.csv(audit, file.path(out_dir, "join_audit.csv"), row.names = FALSE)
print(audit)

# Phase 2: the offset distribution over tagged patches that have a modal break year at all
# (see the definition note above -- this is NOT restricted to cleanly-broken patches).
# `break_frac_area_wtd` here is weighted by the UNCLIPPED area, the same footprint the
# measurand is computed over and the same one Phase 3 uses, so the column means one thing in
# both files.
# Rows whose disturbance year discriminates nothing are kept and labelled rather than
# dropped, so the reader can see what was excluded and why.
offset_rows <- function(src, flag_col, year_col) {
  # NOT filtered on break_year_modal. A tagged patch with no clean break cell gets a row with
  # offset = NA, so `n_tagged` and `n_with_break` are two subsets of ONE population in ONE
  # file. Deriving the denominator from summary_events.csv instead crossed populations --
  # that counts published ROWS (a straddling patch twice) while this counts pat_sv PATCHES
  # after fragment collapse, and the two also diverge whenever the reconciliation does not
  # close. Flicker is 40-49% of changed area (#62), so the no-break set is not small and the
  # ratio must say which denominator it used.
  q <- ev_patch[ev_patch$tag_evaluated & ev_patch[[flag_col]] == 1 &
                  !is.na(ev_patch[[year_col]]), ]
  if (!nrow(q)) {
    return(data.frame(source = src, disturbance_year = integer(0), offset = integer(0),
                      n_patches = integer(0), area_ha_unclipped = numeric(0),
                      break_frac_area_wtd = numeric(0), discriminating = character(0)))
  }
  q$offset <- as.integer(q$break_year_modal) - as.integer(q[[year_col]])   # NA => no break
  q$break_frac[is.na(q$break_frac)] <- 0
  # addNA() on the offset: aggregate's `by` DROPS NA groups silently, which would delete the
  # very rows added above.
  a <- stats::aggregate(cbind(n_patches = rep(1, nrow(q)), area_ha = q$area_ha,
                              break_frac_sum = q$break_frac * q$area_ha),
                        by = list(disturbance_year = as.integer(q[[year_col]]),
                                  offset = addNA(factor(q$offset), ifany = TRUE)),
                        FUN = sum)
  a$offset <- suppressWarnings(as.integer(as.character(a$offset)))
  a$break_frac_area_wtd <- round(a$break_frac_sum / a$area_ha, 3)
  a$break_frac_sum <- NULL
  a$source <- src
  a$area_ha <- round(a$area_ha, 1)
  a$discriminating <- discriminates_v(a$disturbance_year)
  names(a)[names(a) == "area_ha"] <- "area_ha_unclipped"
  a[, c("source", "disturbance_year", "offset", "n_patches", "area_ha_unclipped",
        "break_frac_area_wtd", "discriminating")]
}
off <- rbind(offset_rows("fire", "in_fire", "fire_year"),
             offset_rows("harvest", "in_harvest", "harvest_start_year_calendar"))
utils::write.csv(off, file.path(out_dir, "summary_break_offset.csv"), row.names = FALSE)
print(off[off$discriminating %in% c("full", "partial"), ])

# Phase 3: flicker, harvest-TOUCHING against the untagged residual, stratified on the #44
# signature. Unstratified this is confounded: in_harvest is st_intersects, change
# concentrates at cutblock edges, and #62 measured slivers flickering more than wider
# patches -- so the harvest population is enriched in exactly the high-flicker shape.
# The residual is !in_fire & !in_harvest; the flags are ADDITIVE (salvage is both), so it
# is never a subtraction of totals.
strata <- list(all = rep(TRUE, nrow(ev_patch)),
               sliver = ev_patch$flag_sliver %in% TRUE,
               wider = !(ev_patch$flag_sliver %in% TRUE),
               # thresholded on the unclipped area, the same footprint the measurand and
               # weight use and the same one `area_ha_unclipped` reports
               ge_0.5_ha = ev_patch$area_ha >= 0.5)
# Every population is gated on tag_evaluated, so the residual means "was offered the chance to
# match a disturbance layer and matched none", not "has no tag for any reason".
pops <- list(harvest_touching = ev_patch$tag_evaluated & ev_patch$in_harvest == 1,
             fire_touching = ev_patch$tag_evaluated & ev_patch$in_fire == 1,
             untagged_residual = ev_patch$tag_evaluated & ev_patch$in_harvest == 0 &
               ev_patch$in_fire == 0)
fl_rows <- do.call(rbind, lapply(names(strata), function(s) {
  do.call(rbind, lapply(names(pops), function(p) {
    # ONE FOOTPRINT for the measurand, the weight and the stratum threshold, and the column
    # names say which. flicker_frac / break_frac are cell fractions over the UNCLIPPED patch
    # (pid_r rasterizes pat_sv, and rasterizing the clipped published polygons instead would
    # drop sub-cell fragments -- see fact 1 in the header). An earlier fix weighted these by
    # the clipped area, which produced neither the clipped statistic nor the unclipped one.
    # The residual bias that choice was reacting to -- a trimmed patch carrying more weight
    # than the geometry its tag was evaluated over -- is real, so it is REPORTED here
    # (`area_ha_eval` beside `area_ha_unclipped`) rather than half-corrected.
    k <- strata[[s]] & pops[[p]] & !is.na(ev_patch$flicker_frac)
    data.frame(stratum = s, population = p, n_patches = sum(k),
               area_ha_unclipped = round(sum(ev_patch$area_ha[k]), 1),
               area_ha_eval = round(sum(ev_patch$area_ha_eval[k]), 1),
               flicker_frac_area_wtd = if (sum(k) > 0)
                 round(stats::weighted.mean(ev_patch$flicker_frac[k], ev_patch$area_ha[k]), 3)
               else NA_real_,
               break_frac_area_wtd = if (sum(k) > 0)
                 round(stats::weighted.mean(ev_patch$break_frac[k], ev_patch$area_ha[k]), 3)
               else NA_real_)
  }))
}))
utils::write.csv(fl_rows, file.path(out_dir, "summary_flicker_strata.csv"), row.names = FALSE)
print(fl_rows)

# --- 6. Metadata and timings ----
# `props[["missing"]]` is NULL and data.frame() silently DROPS a NULL argument, so a
# catalogue rename would ship a group_meta.csv quietly missing a column while the run still
# printed ALL STAGES DONE. R2-3 guarded the read side of this trap; this is the write side.
stopifnot(all(c("nge:drift_version", "gross_loss_ha") %in% names(props)))
# script_sha, and a sub-day run_started. The per-group marker proves "every CSV beside
# group_meta.csv came from the same RUN"; it says nothing about whether the four groups came
# from the same SCRIPT. `date` is day-resolution and `terra` / `running_drift_version` do not
# move when a definition in THIS file changes, so a mid-session edit (exactly what produced
# this file) leaves four metas that look identical while their siblings carry two different
# definitions of one measurand. Today that fails loudly only because an earlier round renamed
# a column at the same time it redefined it; a redefinition keeping its name would assemble,
# write the marker, and report success.
meta <- data.frame(
  group = g, item = item, crs = paste0("EPSG:", epsg),
  script_sha = script_sha,
  run_started = format(t0, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
  nrow = nrow(ref), ncol = ncol(ref), ncell = terra::ncell(ref), res_m = terra::res(ref)[1],
  patch_min_m2 = patch_min_m2,
  discriminating_full = paste(years[vapply(years, discriminates, character(1)) == "full"], collapse = "|"),
  discriminating_partial = paste(years[vapply(years, discriminates, character(1)) == "partial"], collapse = "|"),
  published_drift_version = props[["nge:drift_version"]],
  running_drift_version = as.character(utils::packageVersion("drift")),
  published_gross_loss_ha = props[["gross_loss_ha"]],
  subbasin_file = subbasin_file, subbasin_md5 = subbasin_md5, subbasin_n = nrow(subbasins),
  reconciled = reproduced, n_fire_events_disc = n_fire_events_disc,
  patches_dropped_by_clip = length(dropped_ids),
  rows_split_by_clip = split_rows, join_zero_cell_patches = length(zero_cell),
  date = format(Sys.Date()), terra = as.character(utils::packageVersion("terra")))
utils::write.csv(meta, file.path(out_dir, "group_meta.csv"), row.names = FALSE)

timings[["wall"]] <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
utils::write.csv(data.frame(stage = names(timings), seconds = unlist(timings)),
                 file.path(out_dir, "timings.csv"), row.names = FALSE)
message("ALL STAGES DONE")

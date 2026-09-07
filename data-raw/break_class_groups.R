# Temporal QA across the watershed groups whose published annual IO LULC series
# is complete (drift#62): does the BULK split (sustained break / endpoint-only
# break / flicker) generalise?
#
# Reads the seven `classified_<year>` COGs of each stac-floodplains-bc item that
# carries them (bulk_co_ff04, necr_ch_ff04, lnth_ch_ff04, kotl_bt_ff04 — PINE was
# dropped upstream, floodplains#76), so there is no fetch and no AOI mask: the
# published rasters are already clipped to the floodplain. Otherwise the BULK
# pipeline (data-raw/benchmark_break_class_bulk.R) minus the fetch, plus the
# floodplain-shape columns Q3 needs.
#
# Usage (from the repo root; one group per process so an RSS trace is per group):
#   Rscript data-raw/break_class_groups.R necr        # or lnth, bulk, kotl
#   Rscript data-raw/break_class_groups.R summarize   # assemble summary_groups.*
#   Rscript data-raw/break_class_groups.R article-bulk  # BULK figure data for the #66 article
#
# Sample RSS from outside while a group runs (KiB every 2 s):
#   Rscript data-raw/break_class_groups.R necr > data-raw/logs/break_class_groups/necr/run.log 2>&1 &
#   PID=$!; while kill -0 $PID 2>/dev/null; do
#     ps -o rss= -p $PID >> data-raw/logs/break_class_groups/necr/rss.txt; sleep 2; done
#
# Outputs, data-raw/logs/break_class_groups/<group>/ (the .tif, .gpkg, .json and
# .log files and summary_patches.csv are gitignored; the other CSVs and rss.txt
# are the committed evidence record):
#   group_meta.csv           - grid, CRS, cells, run date, terra version
#   summary_class_freq.csv   - cells per class per year (clouds, valid-cell parity)
#   summary_pixels.csv       - res$summary (from, to, status, break_year, cells, area)
#   summary_break_year.csv   - clean-break area by break_year (Q2)
#   summary_change.csv       - endpoint-changed pixels by temporal category (Q1)
#   summary_patch_groups.csv - per-patch temporal evidence by #44 geometric signature (Q4)
#   summary_shape.csv        - floodplain ff02/ff04/ff06 areas, ff06/ff02, 2A/P width (Q3)
#   timings.csv              - stage timings and wall clock
# and from the summarize stage, in data-raw/logs/break_class_groups/:
#   summary_groups.csv / .md - one row per group, every number the note quotes
#   summary_bulk_reconcile.csv - the published-grid BULK run against the #9 run
# and, for the pkgdown article (drift#66), in inst/extdata/temporal-composition/:
#   summary_groups.csv            - a column subset of the object above
#   summary_class_temporal.csv    - temporal category per transition class
#   summary_treeloss_temporal.csv - Trees -> non-Trees, under two named class sets
# and from the article-bulk stage, in the same directory:
#   bulk_grid_1km.csv / bulk_window.csv / bulk_window.rds - the article's BULK figures

suppressMessages({
  library(sf)
  library(terra)
  pkgload::load_all(".", quiet = TRUE)
})

groups <- c(bulk = "bulk_co_ff04", necr = "necr_ch_ff04",
            lnth = "lnth_ch_ff04", kotl = "kotl_bt_ff04")
years <- 2017:2023
base_url <- "https://stac-floodplains-bc.s3.us-west-2.amazonaws.com"
api_url <- "https://images.a11s.one/collections/stac-floodplains-bc/items"
log_root <- file.path("data-raw", "logs", "break_class_groups")

arg <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(arg) || !(arg %in% c(names(groups), "summarize", "article-bulk"))) {
  stop("usage: Rscript data-raw/break_class_groups.R <", paste(names(groups), collapse = "|"),
       "|summarize|article-bulk>", call. = FALSE)
}

# --- helpers ---------------------------------------------------------------

# fetch to a temp file and rename on 200 only: a transport error mid-body would
# otherwise leave a truncated file under the name the next run trusts
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

# the item's `file:checksum` is a sha256 multihash: 0x12 (sha2-256), 0x20 (32
# bytes), then the digest. A 200 + rename says the transfer completed; this says
# the bytes are the ones the catalogue published.
verify_checksum <- function(path, asset, item_json) {
  mh <- asset[["file:checksum"]]
  stopifnot(is.character(mh), startsWith(mh, "1220"), nchar(mh) == 68)
  got <- digest::digest(path, algo = "sha256", file = TRUE)
  if (!identical(got, substr(mh, 5, 68))) {
    # the cached item.json goes too: a mismatch after an upstream republish is
    # a stale checksum, not a bad download, and keeping it would repeat this
    # on every re-run
    unlink(c(path, item_json))
    stop(basename(path), ": sha256 ", got, " != published ", substr(mh, 5, 68),
         " — deleted it and item.json; re-run to fetch both again")
  }
  invisible(TRUE)
}

# The four-level vocabulary the committed runs were made under, kept only to READ
# their output -- read_change() maps it, and passes a five-level file through
# untouched, so a group re-run after #72 and the files already on disk both work. The closure that produced
# it is gone: drift::dft_rast_break_category() is the definition now (#72), and
# the article-bulk stage below asserts it reproduces this run cell for cell.
# benchmark_break_class_bulk.R is left exactly as it ran -- it is the committed
# producer of the BULK evidence, not a script to keep current.
cat_labels <- c("stable", "break_sustained", "break_endpoint", "flicker")

# Every committed summary_change.csv records a run made under that four-level
# vocabulary, in which `flicker` is every n_flips >= 2 and the two populations
# are told apart only by the `changed` column. drift >= 0.16.0 names them apart
# (dft_break_category(), #72). Map on READ rather than rewriting the evidence:
# those files are the record of what was measured, and the map is a bijection
# with (changed, four-level), so nothing is lost either way.
read_change <- function(path) {
  chg <- utils::read.csv(path, stringsAsFactors = FALSE)
  lv <- break_category_levels()
  if (all(chg$category_label %in% lv)) {
    return(chg)                                   # written by a run since #72
  }
  if (!all(chg$category_label %in% cat_labels)) {
    stop(path, " carries a category_label in neither vocabulary: ",
         paste(setdiff(chg$category_label, union(lv, cat_labels)), collapse = ", "))
  }
  fl <- chg$category_label == "flicker"
  chg$category_label[fl] <- ifelse(as.integer(chg$changed[fl]) == 1L,
                                   "unsettled", "stable_flicker")
  # the map must not collide two rows onto one key, or the comparisons that use
  # it would compare one row twice
  if (anyDuplicated(paste(chg$changed, chg$category_label))) {
    stop("mapping ", path, " to the five-level vocabulary collided two rows")
  }
  chg
}

# effective width of a polygon set in metres: 2 * area / perimeter (a rectangle
# of width w and length L >> w gives ~w). st_length(st_boundary()) rather than
# st_perimeter(), which needs lwgeom on projected data. Perimeter-dominated on a
# fragmented floodplain, so the perimeter and polygon count are reported beside it.
shape_row <- function(g, label) {
  a <- as.numeric(sf::st_area(g))
  p <- as.numeric(sf::st_length(sf::st_boundary(g)))
  data.frame(layer = label, area_km2 = round(sum(a) / 1e6, 2), perimeter_km = round(sum(p) / 1e3, 1),
             n_polygons = length(sf::st_cast(sf::st_geometry(g), "POLYGON")),
             width_m = round(2 * sum(a) / sum(p), 1))
}

# --- summarize stage -------------------------------------------------------

if (arg == "summarize") {
  have <- names(groups)[file.exists(file.path(log_root, names(groups), "summary_change.csv"))]
  if (length(have) < length(groups)) {
    stop("missing summary_change.csv for: ", paste(setdiff(names(groups), have), collapse = ", "))
  }
  pick <- function(df, sel, col) { x <- df[sel, col]; if (length(x) == 1) x else NA_real_ }
  shares <- function(chg) {
    chg1 <- chg[chg$changed == 1, ]
    changed_ha <- sum(chg1$area_ha)
    pct <- function(lbl) round(100 * pick(chg1, chg1$category_label == lbl, "area_ha") / changed_ha, 1)
    list(valid_ha = sum(chg$area_ha), changed_ha = changed_ha,
         pct_sustained = pct("break_sustained"), pct_endpoint = pct("break_endpoint"),
         pct_unsettled = pct("unsettled"),
         # unrounded, for the derived columns: dividing by a share already
         # rounded to one decimal moves the last digit of the factor
         sustained_ha = pick(chg1, chg1$category_label == "break_sustained", "area_ha"),
         stable_flicker_ha = pick(chg, chg$category_label == "stable_flicker", "area_ha"))
  }
  rows <- lapply(have, function(g) {
    d <- file.path(log_root, g)
    meta <- utils::read.csv(file.path(d, "group_meta.csv"))
    sh <- shares(read_change(file.path(d, "summary_change.csv")))
    byyr <- utils::read.csv(file.path(d, "summary_break_year.csv"))
    pg <- utils::read.csv(file.path(d, "summary_patch_groups.csv"))
    shp <- utils::read.csv(file.path(d, "summary_shape.csv"))
    freq <- utils::read.csv(file.path(d, "summary_class_freq.csv"))
    tim <- utils::read.csv(file.path(d, "timings.csv"))
    rss <- file.path(d, "rss.txt")
    brk_ha <- function(yr) { x <- byyr$area_ha[byyr$break_year == yr]; if (length(x)) x else 0 }
    cloud <- freq[freq$class_name == "Clouds", ]
    data.frame(
      group = g, item = groups[[g]], crs = meta$crs, ncell = meta$ncell,
      valid_ha = round(sh$valid_ha, 1),
      changed_ha = round(sh$changed_ha, 1), pct_changed_of_valid = round(100 * sh$changed_ha / sh$valid_ha, 2),
      pct_sustained = sh$pct_sustained, pct_endpoint = sh$pct_endpoint,
      pct_unsettled = sh$pct_unsettled,
      # how far the two-epoch layer overstates change sustained two years each side
      overstatement_factor = round(sh$changed_ha / sh$sustained_ha, 2),
      stable_flicker_ha = round(sh$stable_flicker_ha, 1),
      pct_stable_flicker_of_valid = round(100 * sh$stable_flicker_ha / sh$valid_ha, 2),
      # the flicker the two-epoch layer cannot see, relative to what it reports
      stable_flicker_over_changed = round(sh$stable_flicker_ha / sh$changed_ha, 2),
      break_2018_ha = round(brk_ha(2018), 1), pct_break_2018 = round(100 * brk_ha(2018) / sh$changed_ha, 1),
      break_2023_ha = round(brk_ha(2023), 1), pct_break_2023 = round(100 * brk_ha(2023) / sh$changed_ha, 1),
      ratio_2018_2023 = round(brk_ha(2018) / brk_ha(2023), 2),
      cloud_cells_2017 = sum(cloud$n_cells[cloud$year == 2017]),
      cloud_cells_other = sum(cloud$n_cells[cloud$year != 2017]),
      ff02_km2 = pick(shp, shp$layer == "ff02", "area_km2"),
      ff04_km2 = pick(shp, shp$layer == "ff04", "area_km2"),
      ff06_km2 = pick(shp, shp$layer == "ff06", "area_km2"),
      ff06_over_ff02 = round(pick(shp, shp$layer == "ff06", "area_km2") / pick(shp, shp$layer == "ff02", "area_km2"), 3),
      ff04_width_m = pick(shp, shp$layer == "ff04", "width_m"),
      ff04_perimeter_km = pick(shp, shp$layer == "ff04", "perimeter_km"),
      ff04_n_polygons = pick(shp, shp$layer == "ff04", "n_polygons"),
      n_patches = pick(pg, pg$group == "all", "n_patches"),
      break_frac_all = pick(pg, pg$group == "all", "break_frac_area_wtd"),
      break_frac_artifact = pick(pg, pg$group == "artifact_signature", "break_frac_area_wtd"),
      break_frac_other = pick(pg, pg$group == "other", "break_frac_area_wtd"),
      pct_area_artifact = round(100 * pick(pg, pg$group == "artifact_signature", "area_ha") /
                                  pick(pg, pg$group == "all", "area_ha"), 1),
      n_flips_sliver = pick(pg, pg$group == "sliver", "n_flips_area_wtd"),
      n_flips_wider = pick(pg, pg$group == "wider", "n_flips_area_wtd"),
      break_frac_sliver = pick(pg, pg$group == "sliver", "break_frac_area_wtd"),
      break_frac_wider = pick(pg, pg$group == "wider", "break_frac_area_wtd"),
      wall_s = pick(tim, tim$stage == "wall", "seconds"),
      break_class_s = pick(tim, tim$stage == "break_class", "seconds"),
      peak_rss_gib = if (file.exists(rss)) round(max(scan(rss, quiet = TRUE)) / 1024^2, 1) else NA_real_
    )
  })
  out <- do.call(rbind, rows)
  print(t(out))
  utils::write.csv(out, file.path(log_root, "summary_groups.csv"), row.names = FALSE)
  # the note includes these tables verbatim, so `diff` is the check that its
  # numbers are the script's
  md <- c("<!-- generated by data-raw/break_class_groups.R summarize; do not edit -->", "",
          "## Q1: split of the 2017 -> 2023 changed area", "",
          knitr::kable(out[c("group", "valid_ha", "changed_ha", "pct_changed_of_valid", "pct_sustained",
                             "pct_endpoint", "pct_unsettled", "overstatement_factor",
                             "stable_flicker_ha", "pct_stable_flicker_of_valid",
                             "stable_flicker_over_changed")], format = "markdown"), "",
          "## Q2: endpoint-only breaks by year", "",
          knitr::kable(out[c("group", "break_2018_ha", "pct_break_2018", "break_2023_ha", "pct_break_2023",
                             "ratio_2018_2023", "cloud_cells_2017", "cloud_cells_other")], format = "markdown"), "",
          "## Q3: floodplain shape against the unsettled share", "",
          knitr::kable(out[c("group", "ff02_km2", "ff04_km2", "ff06_km2", "ff06_over_ff02", "ff04_width_m",
                             "ff04_perimeter_km", "ff04_n_polygons", "pct_unsettled", "pct_sustained",
                             "n_flips_sliver", "n_flips_wider")], format = "markdown"), "",
          "## Q4: temporal evidence by geometric signature (area-weighted clean-break share)", "",
          knitr::kable(out[c("group", "n_patches", "break_frac_all", "break_frac_artifact", "break_frac_other",
                             "pct_area_artifact", "break_frac_sliver", "break_frac_wider")], format = "markdown"), "",
          "## Run", "",
          knitr::kable(out[c("group", "crs", "ncell", "wall_s", "break_class_s", "peak_rss_gib")],
                       format = "markdown"))
  writeLines(md, file.path(log_root, "summary_groups.md"))

  # BULK on the published grid (14651 x 11552) against the #9 run on the grid
  # dft_stac_fetch() tiled from Planetary Computer (16000 x 12000). Same script
  # logic, same AOI mask to within a few cells; the deltas are reported, not
  # asserted, and a delta beyond about a percentage point is a finding.
  old <- read_change(file.path("data-raw", "logs", "benchmark_break_class", "summary_change.csv"))
  new <- read_change(file.path(log_root, "bulk", "summary_change.csv"))
  # unrounded per run, so the delta row is a difference of measurements rather
  # than of their one-decimal displays; each is rounded once, for display
  rec <- function(chg) {
    sh <- shares(chg)
    chg1 <- chg[chg$changed == 1, ]
    share <- function(lbl) 100 * pick(chg1, chg1$category_label == lbl, "area_ha") / sh$changed_ha
    data.frame(valid_cells = sum(chg$n_cells), valid_ha = sh$valid_ha, changed_ha = sh$changed_ha,
               pct_sustained = share("break_sustained"), pct_endpoint = share("break_endpoint"),
               pct_unsettled = share("unsettled"), stable_flicker_ha = sh$stable_flicker_ha)
  }
  r_old <- rec(old)
  r_new <- rec(new)
  recon <- rbind(data.frame(run = "bulk_pc_fetch_issue9", round(r_old, 2)),
                 data.frame(run = "bulk_published_issue62", round(r_new, 2)),
                 data.frame(run = "delta", round(r_new - r_old, 2)))
  print(recon)
  utils::write.csv(recon, file.path(log_root, "summary_bulk_reconcile.csv"), row.names = FALSE)
  # the note must carry these tables byte for byte: a hand-edited number in the
  # note is exactly what the round-8 review of #9 found
  note <- file.path("inst", "notes", "temporal-qa-groups.md")
  if (file.exists(note)) {
    body <- paste(readLines(note), collapse = "\n")
    if (!grepl(paste(md[-1], collapse = "\n"), body, fixed = TRUE)) {
      stop("inst/notes/temporal-qa-groups.md does not contain summary_groups.md verbatim; ",
           "rebuild the note from the generated tables")
    }
    message("note tables match summary_groups.md")
  }

  # --- article tables (#66) --------------------------------------------------
  # The pkgdown article quotes composition by transition class, and its
  # acceptance requires every quoted value to trace to a committed CSV emitted
  # by a committed script. summary_pixels.csv already carries status x
  # break_year per transition class, so the composition is a rollup of it — but
  # a rollup nobody had written down, which is the gap this closes.
  #
  # Identity, for a consecutive series: break_year is the FIRST year of the new
  # class, so the second year of the series leaves n_before = 1 and the last
  # leaves n_after = 1. Both fail pmin(n_before, n_after) >= 2 and are
  # endpoint-only; everything between them is sustained. Derived from `years`
  # rather than written as 2018/2023 so the identity follows the series if it
  # ever moves. Checked against summary_change.csv on integers, below.
  art_dir <- file.path("inst", "extdata", "temporal-composition")
  dir.create(art_dir, recursive = TRUE, showWarnings = FALSE)
  yr_endpoint <- c(years[2], years[length(years)])

  # The definition is drift's, not this script's: dft_break_category() (#72).
  # It splits what the four-level vocabulary pooled -- `flicker` becomes
  # `unsettled` where the endpoints differ and `stable_flicker` where they
  # agree -- so the two populations cannot be summed by a reader who drops the
  # `changed` column. yr_endpoint is kept as the premise this script asserts
  # against that export, below.

  per_class <- do.call(rbind, lapply(names(groups), function(g) {
    px <- utils::read.csv(file.path(log_root, g, "summary_pixels.csv"),
                          stringsAsFactors = FALSE)
    if (!all(px$break_year[px$status == "break"] %in% years[-1])) {
      stop("break_year outside the declared series in ", g)
    }
    px$group <- g
    if (anyNA(px$status)) {
      stop("summary_pixels.csv carries an NA status in ", g,
           "; dft_break_category() labels it NA and the guards below refuse it")
    }
    px <- dft_break_category(px, years = years)
    # premise: drift's endpoint threshold is pmin(n_before, n_after) < 2, and
    # for a consecutive series that is exactly break_year in the second or last
    # observation -- the rule this script used to apply itself. Assert the two
    # agree rather than trusting they do; if drift's rule ever moves, this is
    # what says so, instead of the numbers moving silently.
    brk <- px$status == "break"
    expect_end <- ifelse(px$break_year[brk] %in% yr_endpoint,
                         "break_endpoint", "break_sustained")
    if (!identical(as.character(px$category[brk]), expect_end)) {
      stop("dft_break_category() no longer agrees with the endpoint-year rule in ", g)
    }
    px$category <- as.character(px$category)
    px$changed <- px$from_class != px$to_class
    # area, not `pct`: summary_pixels.csv's pct is the share of ALL valid pixels,
    # so reusing it here would silently answer a different question
    a <- stats::aggregate(px[c("n_cells", "area")],
                          by = px[c("group", "from_class", "to_class", "changed", "category")],
                          FUN = sum)
    names(a)[names(a) == "area"] <- "area_ha"
    pair <- paste(a$from_class, a$to_class, sep = "\r")
    a$pct_of_pair <- 100 * a$n_cells / ave(a$n_cells, pair, FUN = sum)
    a[order(a$from_class, a$to_class, a$category), ]
  }))

  # --- guard: five checks, all before any write ------------------------------
  # so a failing run leaves no CSV behind for the next one to trust
  stopifnot(
    nrow(per_class) > 0L,
    identical(sort(unique(per_class$group)), sort(names(groups))),
    !anyNA(per_class$category), !anyNA(per_class$n_cells)
  )
  chg_cats <- c("break_endpoint", "break_sustained", "unsettled")
  for (g in names(groups)) {
    pc <- per_class[per_class$group == g, ]
    got <- sort(unique(pc$category[pc$changed]))
    # identical() on a sorted character vector: a category that vanished fails
    # here rather than passing on a pooled set where another group still has it
    if (!identical(got, chg_cats)) {
      stop("changed categories in ", g, " are (", paste(got, collapse = ", "),
           "), expected (", paste(chg_cats, collapse = ", "), ")")
    }
    if (sum(pc$changed) < 40L) stop("only ", sum(pc$changed), " changed pairs in ", g)
    # conservation: cells in equals cells out. This is the tripwire for an
    # aggregate() that silently drops a group -- nothing else would notice.
    px_n <- sum(utils::read.csv(file.path(log_root, g, "summary_pixels.csv"))$n_cells)
    if (!identical(as.integer(sum(pc$n_cells)), as.integer(px_n))) {
      stop("cells lost rolling up ", g, ": ", px_n, " in, ", sum(pc$n_cells), " out")
    }
  }

  # cross-check the rollup against the committed per-group totals, on integers.
  # Verified delta 0 in all four groups, so identical() is the right strength --
  # there is no tolerance to tune and no float drift to absorb.
  agrees <- function(roll, chg) {
    key_roll <- paste(as.integer(roll$changed), roll$category)
    key_chg <- paste(chg$changed, chg$category_label)
    # walk the EXPECTED set, not only the rollup's own rows. Indexing by
    # match(key_roll, key_chg) compares exactly nrow(roll) values, so a category
    # present in summary_change.csv and absent from the rollup is invisible --
    # and the conservation check above cannot see it either, because it compares
    # per_class against the same file per_class was built from.
    if (anyDuplicated(key_roll) || anyDuplicated(key_chg)) {
      stop("a (changed, category) key repeats, so match() would compare one row twice: ",
           paste(unique(c(key_roll[duplicated(key_roll)], key_chg[duplicated(key_chg)])),
                 collapse = ", "))
    }
    if (!setequal(key_roll, key_chg)) {
      stop("category sets differ; only in summary_change.csv: (",
           paste(setdiff(key_chg, key_roll), collapse = ", "), "), only in the rollup: (",
           paste(setdiff(key_roll, key_chg), collapse = ", "), ")")
    }
    idx <- match(key_roll, key_chg)
    identical(as.integer(roll$n_cells), as.integer(chg$n_cells[idx]))
  }
  for (g in names(groups)) {
    pc <- per_class[per_class$group == g, ]
    roll <- stats::aggregate(pc["n_cells"], by = pc[c("changed", "category")], FUN = sum)
    chg <- read_change(file.path(log_root, g, "summary_change.csv"))
    if (!agrees(roll, chg)) stop("rollup does not reproduce summary_change.csv for ", g)
    # positive control: the comparator must be capable of returning FALSE.
    # Without this, two empty or two all-NA objects compare equal and the check
    # above reads green having compared nothing.
    bad <- roll; bad$n_cells[1] <- bad$n_cells[1] + 1L
    if (agrees(bad, chg)) stop("the rollup comparator cannot fail; it is not a check")
    # agrees() has two failure modes and the control above moves only a count, so
    # it leaves both key sets identical and exercises the value arm alone. Drive
    # the structural arm too, or half the comparator is never seen to fail.
    if (!inherits(try(agrees(roll[-1, ], chg), silent = TRUE), "try-error")) {
      stop("the structural arm does not fire on a rollup missing a row")
    }
  }
  message("rollup reproduces summary_change.csv in all ", length(groups), " groups")

  # --- write -----------------------------------------------------------------
  # area_ha unrounded: the article rounds once, at display. Summing a rounded
  # column disagrees with summary_change.csv in the last digit.
  utils::write.csv(per_class[c("group", "from_class", "to_class", "changed", "category",
                               "n_cells", "area_ha", "pct_of_pair")],
                   file.path(art_dir, "summary_class_temporal.csv"), row.names = FALSE)

  # Tree loss, as the two class sets the article must choose between. The set is
  # a literal column, so "which classes is this share computed over" is answered
  # by the data rather than by prose that can drift away from it.
  tree_sets <- list(
    trees_to_non_trees_excl_clouds = c("Trees", "Clouds"),
    trees_to_non_trees_excl_clouds_water = c("Trees", "Clouds", "Water")
  )
  treeloss <- do.call(rbind, lapply(names(tree_sets), function(set) {
    keep <- per_class$from_class == "Trees" & !(per_class$to_class %in% tree_sets[[set]])
    d <- per_class[keep, ]
    a <- stats::aggregate(d[c("n_cells", "area_ha")],
                          by = d[c("group", "category")], FUN = sum)
    a$class_set <- set
    a$pct_of_set <- 100 * a$area_ha / ave(a$area_ha, a$group, FUN = sum)
    a[order(match(a$group, names(groups)), a$category),
      c("group", "class_set", "category", "n_cells", "area_ha", "pct_of_set")]
  }))
  stopifnot(nrow(treeloss) == 2L * length(groups) * length(chg_cats))
  utils::write.csv(treeloss, file.path(art_dir, "summary_treeloss_temporal.csv"),
                   row.names = FALSE)

  # the article's group table is a COLUMN SUBSET of the object that produced
  # summary_groups.csv above -- one derivation, so the two cannot disagree
  utils::write.csv(out[c("group", "item", "valid_ha", "changed_ha", "pct_changed_of_valid",
                         "pct_sustained", "pct_endpoint", "pct_unsettled", "overstatement_factor",
                         "stable_flicker_ha", "pct_stable_flicker_of_valid",
                         "stable_flicker_over_changed")],
                   file.path(art_dir, "summary_groups.csv"), row.names = FALSE)
  message("article tables written to ", art_dir)

  message("SUMMARIZE DONE")
  quit(save = "no", status = 0)
}


# --- article BULK figure data (#66) ----------------------------------------
# Figures 1 and 2 of the pkgdown article. Runs the same scan the per-group stage
# runs, on the same published COGs, and composes the category with
# drift::dft_rast_break_category() -- the package's one definition, so there is
# no second copy of the closure to diverge from the committed numbers.
#
# Needs ~16 GiB of RAM and the gitignored BULK COGs, so it never runs in CI.
# Same posture as data-raw/vignette_data_break.R.

if (arg == "article-bulk") {
  g <- "bulk"
  item <- groups[[g]]
  out_dir <- file.path(log_root, g)
  art_dir <- file.path("inst", "extdata", "temporal-composition")
  dir.create(art_dir, recursive = TRUE, showWarnings = FALSE)

  rasters <- lapply(stats::setNames(years, as.character(years)), function(yr) {
    dest <- file.path(out_dir, sprintf("classified_%d.tif", yr))
    if (!file.exists(dest)) stop("missing ", dest, " -- run the ", g, " stage first")
    terra::rast(dest)
  })
  classified <- dft_rast_classify(rasters, source = "io-lulc")
  res <- dft_rast_break_class(classified)
  cell_ha <- prod(terra::res(res$raster)) * 1e-4

  # Five levels, ids 0:4 -- the split the four-level run could not express is
  # already in here, so the old two-pass cat_fun() + fig_fun() composition is
  # one call. crosstab() and segregate() below want the integer codes, and
  # crosstab() reports LABELS the moment a layer is a factor, so keep a
  # levels-free copy for them. deepcopy() then set.cats() in place is one copy.
  cat5 <- dft_rast_break_category(res, filename = tempfile(fileext = ".tif"))
  category <- terra::deepcopy(cat5[["category"]])
  terra::set.cats(category, layer = 1, value = NULL)

  codes <- terra::deepcopy(res$raster)
  terra::set.cats(codes, layer = 1, value = NULL)
  # refuse a bare vector: app() tries apply(chunk, 1, fun) FIRST and only falls
  # back to fun(chunk) when that errors, so a closure that tolerates a scalar
  # runs once per cell -- 169M R calls here, with identical values and nothing
  # in the output to say which path ran.
  changed <- terra::app(codes, fun = function(v) {
    if (!is.matrix(v)) stop("matrix chunks only")
    as.integer((v[, 1] %/% 1000L) != (v[, 1] %% 1000L))
  }, filename = tempfile(fileext = ".tif"), wopt = list(datatype = "INT1U"))

  # --- self-check BEFORE deriving anything -----------------------------------
  # If this run does not reproduce the committed BULK numbers cell for cell,
  # every figure below is drawn from a different raster than the article's
  # tables describe, and nothing downstream would say so. `changed` is derived
  # from the transition layer rather than read off the category, so this is not
  # the category compared against itself.
  ct <- terra::crosstab(c(changed, category), long = TRUE, useNA = TRUE)
  names(ct) <- c("changed", "category", "n_cells")
  ct <- ct[!is.na(ct$changed), ]
  ct$category_label <- break_category_levels()[as.integer(as.character(ct$category)) + 1L]
  ref <- read_change(file.path(out_dir, "summary_change.csv"))
  k_now <- paste(as.integer(ct$changed), ct$category_label)
  k_ref <- paste(ref$changed, ref$category_label)
  if (anyDuplicated(k_now) || anyDuplicated(k_ref) || !setequal(k_now, k_ref)) {
    stop("category sets differ from the committed BULK run: (",
         paste(setdiff(k_ref, k_now), collapse = ", "), ") missing, (",
         paste(setdiff(k_now, k_ref), collapse = ", "), ") unexpected")
  }
  if (!identical(as.integer(ct$n_cells), as.integer(ref$n_cells[match(k_now, k_ref)]))) {
    stop("this run does not reproduce ", out_dir, "/summary_change.csv cell for cell")
  }
  message("reproduces the committed BULK summary_change.csv cell for cell")

  # The two populations the four-level vocabulary pooled: 2032.93 ha of
  # changed-but-unsettled and 3186.53 ha that flickers while reading identical
  # at both endpoints. Summing them as one "flicker" overstated changed area by
  # 69%, and the conservation check below is what caught it. The figure raster
  # IS the five-level category now -- there is no second composition step.
  fig_cat <- category

  # --- per-patch temporal composition ----------------------------------------
  patches <- dft_transition_vectors(res$raster, changes_only = TRUE)
  pid <- terra::rasterize(terra::vect(patches), res$raster, field = "patch_id",
                          filename = tempfile(fileext = ".tif"))
  # crosstab, not zonal: zonal() outside its six-function fast path materialises
  # the whole grid in R, and this grid is 169M cells
  pc <- terra::crosstab(c(pid, category), long = TRUE, useNA = FALSE)
  names(pc) <- c("patch_id", "category", "n_cells")
  pc$patch_id <- as.integer(as.character(pc$patch_id))
  pc$category <- as.integer(as.character(pc$category))

  wide <- stats::reshape(pc, idvar = "patch_id", timevar = "category", direction = "wide")
  for (k in 1:3) {
    cn <- paste0("n_cells.", k)
    if (!cn %in% names(wide)) wide[[cn]] <- 0L
    wide[[cn]][is.na(wide[[cn]])] <- 0L
  }
  wide$n_tot <- wide$n_cells.1 + wide$n_cells.2 + wide$n_cells.3
  # Every pixel of a change patch has from != to at the endpoints, so n_flips >= 1
  # and BOTH the categories defined by equal endpoints -- 0 (stable) and 4
  # (stable_flicker) -- are structurally impossible inside one. Assert it rather
  # than assume it: if either appears, the shares below have a missing
  # denominator. The five-level vocabulary adds the second arm; under four
  # levels those pixels were pooled into 3 and this check could not see them.
  for (k in c(0L, 4L)) {
    cn <- paste0("n_cells.", k)
    if (cn %in% names(wide) && sum(wide[[cn]], na.rm = TRUE) > 0) {
      stop(break_category_levels()[k + 1L], " cells inside a change patch; ",
           "the composition denominator is wrong")
    }
  }

  cand <- merge(sf::st_drop_geometry(patches)[c("patch_id", "transition", "area_ha")],
                wide[c("patch_id", "n_cells.1", "n_cells.2", "n_cells.3", "n_tot")],
                by = "patch_id")
  n0 <- nrow(cand)
  # n0 is published as n_candidates_all and quoted in the article's caption, so
  # it must be the patch count, not whatever an inner merge() happened to keep
  stopifnot(identical(n0, nrow(patches)))
  cand <- cand[cand$transition == "Trees -> Rangeland", ]
  n1 <- nrow(cand)
  cand <- cand[cand$area_ha >= 1 & cand$area_ha <= 4, ]
  n2 <- nrow(cand)
  sh <- function(i) cand[[paste0("n_cells.", i)]] / cand$n_tot
  cand$share_min <- pmin(sh(1), sh(2), sh(3))
  cand <- cand[cand$share_min >= 0.10, ]
  n3 <- nrow(cand)
  message(sprintf("patch filters: %d all -> %d Trees->Rangeland -> %d 1-4 ha -> %d all three >=10%%",
                  n0, n1, n2, n3))
  if (n3 == 0L) {
    stop("no patch survives the selection rule; relaxing a filter silently is how a ",
         "hand-picked example gets published as a derived one")
  }
  # most balanced patch: the one showing all three behaviours at once.
  # Tie-break on patch_id so the choice is reproducible.
  cand <- cand[order(-cand$share_min, cand$patch_id), ]
  sel <- cand[1, ]
  message("selected patch ", sel$patch_id, " (", round(sel$area_ha, 2), " ha, min share ",
          round(sel$share_min, 3), ")")

  # --- windows ---------------------------------------------------------------
  geom <- patches[patches$patch_id == sel$patch_id, ]
  ctr <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(geom)))[1, ]
  win <- function(half_cells) {
    r <- terra::res(res$raster)[1]
    cl <- terra::cellFromXY(res$raster, matrix(ctr, ncol = 2))
    xy <- terra::xyFromCell(res$raster, cl)
    terra::ext(xy[1] - (half_cells + 0.5) * r, xy[1] + (half_cells + 0.5) * r,
               xy[2] - (half_cells + 0.5) * r, xy[2] + (half_cells + 0.5) * r)
  }
  e_patch <- win(30)    # 61 x 61 cells, 610 m -- odd, so the centroid cell is central
  e_reach <- win(200)   # 401 x 401 cells, ~4 km

  # one shared ext per figure, then assert the grids agree: crop() with a
  # per-layer extent hands back subtly different grids and nothing says so
  # dft_rast_classify() returns a named LIST, so crop each year and stack the
  # crops. Stacking first would build a 7-layer 169M-cell object to throw away.
  lulc <- terra::rast(lapply(classified, function(r) terra::crop(r, e_patch)))
  cat_patch <- terra::crop(fig_cat, e_patch)
  cat_reach <- terra::crop(fig_cat, e_reach)
  stopifnot(terra::compareGeom(lulc, cat_patch, stopOnError = FALSE))

  # store bare integer codes: a factor written out drops a .tif.aux.xml RAT
  # sidecar whose loss is silent, and a cropped factor keeps every level so the
  # legend fills with classes the panel does not contain. The article
  # re-attaches labels and colours from dft_class_table().
  # varnames also has to be set, and it is the one that bites: terra carries the
  # basename of whatever `filename =` produced, so an app() written to
  # tempfile() leaks a per-process random path into a committed artifact. Same
  # shape as terra::sources() on a derived raster, one slot over, and just as
  # silent -- values, extent and CRS all round-trip identically while the file
  # churns on every run. Pinning it removes the PER-PROCESS variation; `meta`
  # still carries the run date, so a regeneration on a later day is a real diff,
  # which is the same provenance convention group_meta.csv follows.
  strip <- function(x, vname) {
    y <- terra::deepcopy(x)
    # per layer for BOTH: `coltab(y) <- NULL` removes layer 1 only, so a 7-layer
    # stack keeps six palettes and the helper silently fails its own contract
    for (i in seq_len(terra::nlyr(y))) {
      terra::set.cats(y, layer = i, value = NULL)
      terra::coltab(y, layer = i) <- NULL
    }
    terra::varnames(y) <- rep(vname, terra::nlyr(y))
    terra::longnames(y) <- rep("", terra::nlyr(y))
    y
  }
  lulc <- strip(lulc, "io_lulc_class")
  names(lulc) <- as.character(years)
  cat_patch <- strip(cat_patch, "temporal_category")
  cat_reach <- strip(cat_reach, "temporal_category")
  names(cat_patch) <- "category"
  names(cat_reach) <- "category"

  # --- 1 km grid for the locator panel ---------------------------------------
  # terra::aggregate(fun = "sum", na.rm = TRUE) returns 0, NOT NA, for an
  # all-NA block. BULK is 97.7% NA, so the naive call draws a solid rectangle
  # over 146 x 115 km with the floodplain invisible inside it. Aggregate a
  # valid indicator alongside and drop every block that holds no data.
  ind <- terra::segregate(fig_cat, classes = 0:4, other = 0)
  names(ind) <- c("stable", "sustained", "endpoint", "unsettled", "stable_flicker")
  valid <- terra::app(category, fun = function(v) as.integer(!is.na(v)),
                      filename = tempfile(fileext = ".tif"), wopt = list(datatype = "INT1U"))
  names(valid) <- "valid"
  agg <- terra::aggregate(c(valid, ind), fact = 100, fun = "sum", na.rm = TRUE,
                          filename = tempfile(fileext = ".tif"))
  grid <- terra::as.data.frame(agg, xy = TRUE, na.rm = FALSE)
  grid <- grid[!is.na(grid$valid) & grid$valid > 0, ]
  for (cn in c("valid", "stable", "sustained", "endpoint", "unsettled", "stable_flicker")) {
    grid[[paste0(cn, "_ha")]] <- grid[[cn]] * cell_ha
  }
  grid <- grid[c("x", "y", "valid_ha", "stable_ha", "sustained_ha", "endpoint_ha",
                 "unsettled_ha", "stable_flicker_ha")]
  # Conservation, not a cell count. A floodplain is threads, not a blob, so the
  # number of 1 km blocks it touches is many times its area / 100 -- an earlier
  # version of this guard asserted that ratio and fired on a correct grid.
  # What actually catches an all-NA block counted as zero is that the retained
  # blocks must carry the whole floodplain and nothing more.
  n_drop <- terra::ncell(agg) - nrow(grid)
  message(sprintf("1 km grid: %d blocks retained, %d dropped as empty (%.1f%% of the extent)",
                  nrow(grid), n_drop, 100 * n_drop / terra::ncell(agg)))
  if (n_drop <= 0) {
    stop("the valid > 0 filter dropped nothing, so it is decoration: every all-NA ",
         "block is being carried as a run of zeros")
  }
  valid_ha <- sum(grid$valid_ha)
  ref_valid_ha <- sum(ref$n_cells) * cell_ha
  if (abs(valid_ha - ref_valid_ha) > cell_ha / 2) {
    stop("floodplain hectares in the 1 km grid (", round(valid_ha, 1), ") do not match the ",
         "committed total (", round(ref_valid_ha, 1), ")")
  }
  chg_ha <- sum(grid$sustained_ha + grid$endpoint_ha + grid$unsettled_ha)
  ref_ha <- sum(ref$n_cells[ref$changed == 1]) * cell_ha
  if (abs(chg_ha - ref_ha) > cell_ha / 2) {
    stop("changed hectares in the 1 km grid (", round(chg_ha, 1), ") do not match the ",
         "committed total (", round(ref_ha, 1), ")")
  }
  # the population that the pooled category 3 was hiding, asserted separately
  sf_ha <- sum(grid$stable_flicker_ha)
  # `stable_flicker` after read_change(); the four-level files spelled it
  # `flicker` and told it apart from the changed half by the `changed` column
  # alone, which is the pooling this vocabulary exists to prevent
  ref_sf <- sum(ref$n_cells[ref$category_label == "stable_flicker"]) * cell_ha
  if (abs(sf_ha - ref_sf) > cell_ha / 2) {
    stop("stable-flicker hectares in the 1 km grid (", round(sf_ha, 1), ") do not match the ",
         "committed total (", round(ref_sf, 1), ")")
  }
  message(sprintf("1 km grid conserves %.1f floodplain ha, %.1f changed ha, %.1f stable-flicker ha",
                  valid_ha, chg_ha, sf_ha))
  utils::write.csv(grid, file.path(art_dir, "bulk_grid_1km.csv"), row.names = FALSE)

  # --- provenance ------------------------------------------------------------
  # the realised extent, not the requested one: crop() silently truncates a
  # window that runs off the grid, and compareGeom() below cannot see it because
  # both sides were cropped by the same extent. The article's locator rect()
  # draws from these numbers.
  ep <- as.vector(terra::ext(cat_patch))
  er <- as.vector(terra::ext(cat_reach))
  if (!isTRUE(all.equal(ep, as.vector(e_patch))) ||
      !isTRUE(all.equal(er, as.vector(e_reach)))) {
    message("note: a window was truncated at the grid edge; the CSV records what was realised")
  }
  prov <- data.frame(
    patch_id = sel$patch_id, transition = sel$transition, area_ha = sel$area_ha,
    n_cells_sustained = sel$n_cells.1, n_cells_endpoint = sel$n_cells.2,
    n_cells_flicker = sel$n_cells.3, share_min = sel$share_min,
    patch_xmin = ep[1], patch_xmax = ep[2], patch_ymin = ep[3], patch_ymax = ep[4],
    reach_xmin = er[1], reach_xmax = er[2], reach_ymin = er[3], reach_ymax = er[4],
    crs = terra::crs(res$raster, describe = TRUE)$code,
    n_candidates_all = n0, n_candidates_transition = n1, n_candidates_area = n2,
    n_candidates_balanced = n3,
    rule = paste(
      "Trees -> Rangeland; 1 to 4 ha; all three changed categories at 10% or more",
      "of the patch's cells; ranked by the largest minimum share, ties by patch_id."
    ),
    terra = as.character(utils::packageVersion("terra")),
    drift = as.character(utils::packageVersion("drift")),
    date = format(Sys.Date()), stringsAsFactors = FALSE)
  utils::write.csv(prov, file.path(art_dir, "bulk_window.csv"), row.names = FALSE)

  # --- artifact --------------------------------------------------------------
  # crop THEN wrap: wrap() pulls a file-backed raster's values into memory, so
  # wrapping first would serialise all 169M cells into the .rds
  art <- list(lulc = terra::wrap(lulc), category = terra::wrap(cat_patch),
              reach = terra::wrap(cat_reach), patch = geom["patch_id"], meta = prov)
  rt <- terra::unwrap(art$lulc)
  stopifnot(
    identical(terra::values(rt), terra::values(lulc)),
    terra::ext(rt) == terra::ext(lulc),
    identical(terra::crs(rt), terra::crs(lulc))
  )
  # size-check a temp copy first: a stop() after the real write would leave the
  # .rds and the two CSVs describing different runs
  out_rds <- file.path(art_dir, "bulk_window.rds")
  tmp_rds <- tempfile(fileext = ".rds")
  saveRDS(art, tmp_rds, compress = "xz")
  if (file.size(tmp_rds) > 500e3) {
    stop("artifact is ", round(file.size(tmp_rds) / 1024), " KB, over the 500 KB budget; ",
         "shrink the reach window")
  }
  if (!file.copy(tmp_rds, out_rds, overwrite = TRUE)) stop("could not write ", out_rds)
  message("wrote ", out_rds, " (", round(file.size(out_rds) / 1024), " KB)")

  message("ARTICLE BULK DONE")
  quit(save = "no", status = 0)
}

# --- per-group stage -------------------------------------------------------

g <- arg
item <- groups[[g]]
sp_layer <- paste(strsplit(item, "_")[[1]][2:3], collapse = "_")   # e.g. co_ff04
sp <- strsplit(item, "_")[[1]][2]                                   # e.g. co
out_dir <- file.path(log_root, g)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

t0 <- Sys.time()
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
assets <- jsonlite::fromJSON(item_json, simplifyVector = FALSE)[["assets"]]
stopifnot(all(sprintf("classified_%d", years) %in% names(assets)), "floodplain" %in% names(assets))
tifs <- vapply(years, function(y) {
  key <- sprintf("classified_%d", y)
  p <- fetch_once(assets[[key]][["href"]], file.path(out_dir, paste0(key, ".tif")))
  verify_checksum(p, assets[[key]], item_json)
  p
}, character(1))
gpkg <- fetch_once(assets[["floodplain"]][["href"]], file.path(out_dir, "floodplain.gpkg"))
verify_checksum(gpkg, assets[["floodplain"]], item_json)
tick("download", t1)

rasters <- lapply(tifs, terra::rast)
names(rasters) <- years
stopifnot(identical(as.integer(names(rasters)), 2017:2023))   # Q2's year <-> n_before/n_after identity
for (r in rasters[-1]) stopifnot(terra::compareGeom(rasters[[1]], r, stopOnError = FALSE))
stopifnot(!any(vapply(rasters, terra::inMemory, logical(1))))  # the file-backed floor is the point
ref <- rasters[[1]]
epsg <- terra::crs(ref, describe = TRUE)$code
message(item, ": ", paste(dim(ref)[1:2], collapse = " x "), " at ",
        paste(terra::res(ref), collapse = " x "), " m, EPSG:", epsg, ", ",
        format(terra::ncell(ref), big.mark = ","), " cells")

# --- 2. Classify; per-year class frequencies ----
t1 <- Sys.time()
classified <- dft_rast_classify(rasters, source = "io-lulc")
tick("classify", t1)

t1 <- Sys.time()
freq <- do.call(rbind, lapply(years, function(y) {
  f <- terra::freq(classified[[as.character(y)]])
  data.frame(year = y, class_name = f$value, n_cells = f$count)
}))
valid_by_year <- stats::aggregate(n_cells ~ year, freq, sum)
if (length(unique(valid_by_year$n_cells)) != 1) {
  stop("valid-cell count differs across years: ", paste(valid_by_year$n_cells, collapse = ", "))
}
tick("class_freq", t1)
utils::write.csv(freq, file.path(out_dir, "summary_class_freq.csv"), row.names = FALSE)
print(freq[freq$class_name %in% c("Clouds", "No Data"), ])

# --- 3. Scan ----
t1 <- Sys.time()
res <- dft_rast_break_class(classified)
tick("break_class", t1)
utils::write.csv(res$summary, file.path(out_dir, "summary_pixels.csv"), row.names = FALSE)
cell_ha <- prod(terra::res(res$raster)) * 1e-4

# Q2: a clean break dated 2018 is exactly n_flips == 1 & n_before == 1 (2017 alone
# differs); dated 2023 is exactly n_after == 1 (2023 alone differs)
byyr <- res$summary[res$summary$status %in% "break", ]
byyr <- stats::aggregate(cbind(n_cells, area) ~ break_year, byyr, sum)
names(byyr) <- c("break_year", "n_cells", "area_ha")
byyr$pct_of_break <- round(100 * byyr$n_cells / sum(byyr$n_cells), 2)
utils::write.csv(byyr, file.path(out_dir, "summary_break_year.csv"), row.names = FALSE)
print(byyr)

# --- 4. Endpoint-changed pixels by temporal category (Q1) ----
t1 <- Sys.time()
# drift::dft_rast_break_category(), the package's one definition (#72). Five
# levels: what this stage used to write as `flicker` is now `unsettled` where
# the endpoints differ and `stable_flicker` where they agree. `changed` stays,
# because it is a fact about the row and because read_change() needs it to map
# the four-level files already committed.
cat5 <- dft_rast_break_category(res, filename = tempfile(fileext = ".tif"))
category <- terra::deepcopy(cat5[["category"]])
terra::set.cats(category, layer = 1, value = NULL)   # crosstab reports LABELS on a factor
codes <- terra::deepcopy(res$raster)
terra::set.cats(codes, layer = 1, value = NULL)
# refuse a bare vector, or app() runs this once per CELL -- 169M R calls on a
# floodplain grid, with identical values and nothing in the output to say so
changed <- terra::app(codes, fun = function(v) {
  if (!is.matrix(v)) stop("matrix chunks only")
  as.integer((v[, 1] %/% 1000L) != (v[, 1] %% 1000L))
}, filename = tempfile(fileext = ".tif"), wopt = list(datatype = "INT1U"))
ct <- terra::crosstab(c(changed, category), long = TRUE, useNA = TRUE)
names(ct) <- c("changed", "category", "n_cells")
ct <- ct[!is.na(ct$changed), ]
ct$category <- as.integer(as.character(ct$category))
ct$area_ha <- ct$n_cells * cell_ha
ct$category_label <- break_category_levels()[ct$category + 1L]
ct$pct_of_changed <- NA_real_
chg <- ct$changed == 1
ct$pct_of_changed[chg] <- round(100 * ct$n_cells[chg] / sum(ct$n_cells[chg]), 2)
tick("category_crosstab", t1)
utils::write.csv(ct, file.path(out_dir, "summary_change.csv"), row.names = FALSE)
print(ct)

# --- 5. Patches: the #44 pipeline with per-patch temporal evidence (Q4) ----
t1 <- Sys.time()
patches <- dft_transition_vectors(res$raster, changes_only = TRUE)
tick("transition_vectors", t1)
message(nrow(patches), " change patches, ", round(sum(patches$area_ha), 1), " ha")

t1 <- Sys.time()
tagged <- dft_transition_artifact(patches, res$raster)
tick("transition_artifact", t1)

t1 <- Sys.time()
pid <- terra::rasterize(terra::vect(patches), res$raster, field = "patch_id",
                        filename = tempfile(fileext = ".tif"))
is_break <- terra::app(res$breaks[["n_flips"]], fun = function(v) as.integer(v == 1L),
                       filename = tempfile(fileext = ".tif"), wopt = list(datatype = "INT1U"))
z <- terra::zonal(c(is_break, res$breaks[["break_year"]], res$breaks[["n_flips"]]),
                  pid, fun = "mean", na.rm = TRUE)
names(z) <- c("patch_id", "break_frac", "break_year_mean", "n_flips_mean")
tagged <- merge(sf::st_drop_geometry(tagged), z, by = "patch_id", all.x = TRUE)
tick("patch_zonal", t1)
utils::write.csv(tagged, file.path(out_dir, "summary_patches.csv"), row.names = FALSE)

art <- tagged$flag_sliver & (tagged$flag_boundary | tagged$flag_reciprocal)
art[is.na(art)] <- FALSE
grp <- function(sel, label) {
  q <- tagged[sel, ]
  data.frame(group = label, n_patches = nrow(q), area_ha = round(sum(q$area_ha), 1),
             break_frac_area_wtd = round(stats::weighted.mean(q$break_frac, q$area_ha, na.rm = TRUE), 3),
             pct_no_break_cell = round(100 * mean(q$break_frac == 0, na.rm = TRUE), 1),
             pct_all_break = round(100 * mean(q$break_frac == 1, na.rm = TRUE), 1),
             n_flips_area_wtd = round(stats::weighted.mean(q$n_flips_mean, q$area_ha, na.rm = TRUE), 2))
}
pgroups <- rbind(grp(art, "artifact_signature"), grp(!art, "other"),
                 grp(tagged$flag_sliver, "sliver"), grp(!tagged$flag_sliver, "wider"),
                 grp(tagged$area_ha >= 0.5, "ge_0.5_ha"), grp(rep(TRUE, nrow(tagged)), "all"))
print(pgroups)
utils::write.csv(pgroups, file.path(out_dir, "summary_patch_groups.csv"), row.names = FALSE)

# --- 6. Floodplain shape (Q3) ----
# Confinement is not a field in the data. Two proxies from the published
# floodplain polygons, derived here rather than read from the item properties:
# how much the floodplain widens as the flood factor rises (ff06 / ff02 — a
# confined valley barely does, a wide one does) and the ff04 effective width.
# The per-stream `_by_blue_line_key` layer was rejected for this: its polygons
# overlap 1.7-2.2x (tributary floodplains nested in the mainstem's) and kotl
# has none (planning findings, drift#62).
t1 <- Sys.time()
shape <- do.call(rbind, lapply(c("ff02", "ff04", "ff06"), function(ff) {
  lyr <- sf::st_read(gpkg, layer = paste0(sp, "_", ff), quiet = TRUE)
  lyr <- sf::st_transform(sf::st_make_valid(sf::st_geometry(lyr)), sf::st_crs(ref))
  shape_row(sf::st_as_sf(sf::st_union(lyr)), ff)
}))
tick("shape", t1)
print(shape)
utils::write.csv(shape, file.path(out_dir, "summary_shape.csv"), row.names = FALSE)

# --- 7. Group metadata and timings ----
meta <- data.frame(
  group = g, item = item, layer = sp_layer, crs = paste0("EPSG:", epsg),
  nrow = nrow(ref), ncol = ncol(ref), ncell = terra::ncell(ref), res_m = terra::res(ref)[1],
  valid_cells = valid_by_year$n_cells[1], n_patches = nrow(tagged),
  date = format(Sys.Date()), terra = as.character(utils::packageVersion("terra")),
  drift = as.character(utils::packageVersion("drift")))
utils::write.csv(meta, file.path(out_dir, "group_meta.csv"), row.names = FALSE)

timings[["wall"]] <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
utils::write.csv(data.frame(stage = names(timings), seconds = unlist(timings)),
                 file.path(out_dir, "timings.csv"), row.names = FALSE)
message("ALL STAGES DONE")

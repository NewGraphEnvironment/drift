# Benchmark + terra-semantics gate for the #34 / #28 OOM fix.
#
# Two independent memory drivers in the land-cover change pipeline:
#   (1) dft_rast_transition() (producer) builds 6+ full-grid R vectors incl. two
#       full-grid CHARACTER vectors  -> ncell-driven ~13 GB floor (issue #28).
#   (2) dft_transition_vectors() polygonizes the whole floodplain's *stable*
#       mosaic before the caller discards it -> floodplain-area-driven (the field
#       OOM that kills NECR, 551 km^2).
#
# This script is data-raw only (NOT sourced by the package, zero DESCRIPTION
# footprint). It (A) asserts the terra semantics the rewrite rests on, and (B)
# profiles R-side peak memory of the pipeline on a synthetic classified pair with
# independently-tunable grid size and transition density.
#
# Usage:
#   Rscript data-raw/benchmark_transition_oom.R semantics
#   Rscript data-raw/benchmark_transition_oom.R profile <ncol> <nrow> <change_frac>
#
# Verified on terra 1.9.11 / R 4.5.2. The ops used (factor-strip via `*1L`, ifel,
# freq, classify, subst, set.cats, SpatRaster `%in%`) are stable terra features
# predating the DESCRIPTION floor 1.8-10; the only floor-relevant fix is the
# patches(values=TRUE) edge-wraparound bug (rspatial/terra#1675), unrelated here.

suppressPackageStartupMessages(library(terra))

# ---- helpers ---------------------------------------------------------------

# small projected factor raster mimicking io-lulc codes, from an integer matrix
mk_factor_rast <- function(m, codes = sort(unique(as.vector(m[!is.na(m)])))) {
  r <- terra::rast(nrows = nrow(m), ncols = ncol(m),
                   xmin = 0, xmax = ncol(m) * 10, ymin = 0, ymax = nrow(m) * 10,
                   crs = "EPSG:32609")
  terra::values(r) <- as.vector(t(m))
  terra::set.cats(r, layer = 1,
                  value = data.frame(id = codes,
                                     class_name = paste0("class_", codes)))
  r
}

vals <- function(r) terra::values(r)[, 1]

# ---- (A) terra-semantics gate ----------------------------------------------

run_semantics <- function() {
  ok <- function(cond, msg) if (!isTRUE(cond)) stop("SEMANTICS FAIL: ", msg, call. = FALSE)

  # 3x3 with an out-of-AOI NA cell; codes mimic io-lulc (2 Trees, 5 Crops, 7 Built...)
  mf <- matrix(c(2, 5, 7,
                 5, NA, 2,
                 7, 2, 5), nrow = 3, byrow = TRUE)
  mt <- matrix(c(2, 2, 7,     # (1,1) stable 2->2; others change
                 5, NA, 5,
                 7, 5, 2), nrow = 3, byrow = TRUE)
  r_from <- mk_factor_rast(mf)
  r_to   <- mk_factor_rast(mt)

  # 1. `*1L` strips factor -> raw codes, NA preserved, DOES NOT mutate input
  code_from <- r_from * 1L
  ok(!terra::is.factor(code_from), "`r_from * 1L` should be non-factor")
  ok(terra::is.factor(r_from),     "`r_from * 1L` must NOT mutate r_from (still factor)")
  ok(identical(which(is.na(vals(code_from))), which(is.na(vals(r_from)))),
     "`*1L` must preserve NA positions")
  ok(all(vals(code_from) == vals(r_from) | is.na(vals(code_from))),
     "`*1L` values must equal raw codes")
  code_to <- r_to * 1L

  # 2. NA propagates through `* / +`
  r_trans <- code_from * 1000L + code_to
  na_expected <- is.na(vals(code_from)) | is.na(vals(code_to))
  ok(identical(which(is.na(vals(r_trans))), which(na_expected)),
     "trans_code arithmetic must be NA where either input is NA")
  ok(vals(r_trans)[1] == 2002, "encoding from*1000+to wrong")   # (1,1): 2->2

  # 3. SpatRaster `%in%` is FALSE (not NA) at NA cells -> matches base `name %in% sel`
  sel <- code_from %in% c(2, 5)
  ok(vals(sel)[which(na_expected)[1]] == 0,
     "`code %in% set` must be FALSE (0), not NA, at NA cells")
  ok(vals(sel)[3] == 0, "code 7 should be FALSE for %in% c(2,5)")

  # 4. freq(integer raster): value==code, NA excluded, sum(count)==n_nonNA
  ft <- terra::freq(r_trans)
  ok(!any(is.na(ft$value)), "freq() must exclude NA by default")
  ok(sum(ft$count) == sum(!is.na(vals(r_trans))),
     "sum(freq$count) must equal non-NA cell count (total_valid)")
  ok(2002 %in% ft$value, "freq value must equal the actual code")

  # 5. empty-RHS `%in%` ERRORS (guard needed); classify/subst with a set work
  err <- tryCatch({ code_from %in% integer(0); FALSE }, error = function(e) TRUE)
  ok(err, "SpatRaster `%in%` on empty RHS must error (so we guard length>0)")
  cl <- terra::classify(code_from, cbind(7, NA))
  ok(all(is.na(vals(cl)[vals(code_from) == 7 & !is.na(vals(code_from))])),
     "classify(cbind(id, NA)) must NA-out the id")
  sb <- terra::subst(code_from, 7, NA)
  ok(all(is.na(vals(sb)[vals(code_from) == 7 & !is.na(vals(code_from))])),
     "subst(id, NA) must NA-out the id")

  # 6. patches + `p %in% small_ids` FALSE at p==NA
  r_changed <- terra::ifel(!is.na(r_trans) & (code_from != code_to), 1L, NA)
  p <- terra::patches(r_changed, directions = 8)
  small <- terra::freq(p)$value[1]                      # pick one patch id
  sm <- p %in% small
  ok(all(vals(sm)[is.na(vals(p))] == 0),
     "`p %in% ids` must be FALSE at p==NA cells")

  # 7. set.cats on the double-valued arithmetic raster -> factor, correct labels
  codes <- sort(ft$value)
  terra::set.cats(r_trans, layer = 1,
                  value = data.frame(id = codes,
                                     transition = paste0(codes %/% 1000L, "->",
                                                         codes %% 1000L)))
  ok(terra::is.factor(r_trans), "set.cats on arithmetic raster must yield a factor")
  ok(any(grepl("->", terra::freq(r_trans)$value)),
     "factor freq must return the transition labels")

  cat("SEMANTICS GATE: ALL PASS (terra", as.character(packageVersion("terra")), ")\n")
}

# ---- (B) synthetic profiling ------------------------------------------------

# build a classified pair with COHERENT patches (a coarse seeded random field
# disaggregated to full res, ~floodplain-like block sizes), NOT salt-and-pepper.
# `change_frac` of coarse cells change class between years (drives transition-patch
# count); the rest are stable. ~10% NA (out-of-AOI mask). Seeded for reproducibility.
mk_synthetic_pair <- function(ncol, nrow, change_frac = 0.05, block = 20L) {
  codes <- c(2L, 5L, 7L, 8L, 11L)                       # io-lulc-ish subset
  set.seed(42)
  cn <- ceiling(ncol / block); rn <- ceiling(nrow / block)
  coarse_from <- sample(codes, cn * rn, replace = TRUE)
  coarse_to   <- coarse_from
  chg <- sample(cn * rn, size = round(change_frac * cn * rn))
  coarse_to[chg] <- vapply(coarse_from[chg],
                           function(cf) sample(setdiff(codes, cf), 1), integer(1))
  # ~10% NA blocks (out-of-AOI); same mask both years
  na_blk <- sample(cn * rn, size = round(0.10 * cn * rn))
  coarse_from[na_blk] <- NA; coarse_to[na_blk] <- NA

  mk <- function(v) {
    rc <- terra::rast(nrows = rn, ncols = cn, xmin = 0, xmax = cn * block * 10,
                      ymin = 0, ymax = rn * block * 10, crs = "EPSG:32609")
    terra::values(rc) <- v
    r <- terra::disagg(rc, fact = block)                # blow up to full res
    r <- r[[1]]
    terra::set.cats(r, layer = 1,
                    value = data.frame(id = codes, class_name = paste0("class_", codes)))
    r
  }
  list("2017" = mk(coarse_from), "2023" = mk(coarse_to))
}

run_profile <- function(ncol, nrow, change_frac, block = 20L) {
  devtools::load_all(quiet = TRUE)
  pair <- mk_synthetic_pair(ncol, nrow, change_frac, block = block)
  cat(sprintf("Synthetic %d x %d = %.1fM cells, change_frac=%.3f\n",
              terra::ncol(pair[[1]]), terra::nrow(pair[[1]]),
              terra::ncell(pair[[1]]) / 1e6, change_frac))
  # Whole-process peak RSS is the honest meter (run under `/usr/bin/time -l`).
  # Patch count is the unambiguous O(patches) proxy: dft_transition_vectors
  # polygonizes ALL patches (stable mosaic + changes); `changes_only` will drop
  # the stable ones. Report both so before/after (this branch) is comparable.
  trans <- drift::dft_rast_transition(pair, from = "2017", to = "2023",
                                      patch_area_min = 500)
  mode <- if (length(commandArgs(TRUE)) >= 5) commandArgs(TRUE)[5] else "all"
  if (identical(mode, "changes")) {
    v <- drift::dft_transition_vectors(trans$raster, changes_only = TRUE)
    cat(sprintf("dft_transition_vectors(changes_only=TRUE): %d patches polygonized\n",
                nrow(v)))
  } else {
    v_all <- drift::dft_transition_vectors(trans$raster)   # default (all patches)
    n_stable <- sum(vapply(strsplit(v_all$transition, " -> ", fixed = TRUE),
                           function(p) identical(p[1], p[2]), logical(1)))
    cat(sprintf("dft_transition_vectors(default): %d patches total, %d stable (%.0f%%), %d change\n",
                nrow(v_all), n_stable, 100 * n_stable / nrow(v_all),
                nrow(v_all) - n_stable))
  }
}

# ---- dispatch ---------------------------------------------------------------

arg_or <- function(x, default) if (length(x) == 0 || is.na(x)) default else x

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0 || args[1] == "semantics") {
  run_semantics()
} else if (args[1] == "profile") {
  run_profile(as.integer(arg_or(args[2], 3000)),
              as.integer(arg_or(args[3], 3000)),
              as.numeric(arg_or(args[4], 0.05)),
              block = as.integer(arg_or(args[6], 20)))
} else {
  stop("unknown mode: ", args[1])
}

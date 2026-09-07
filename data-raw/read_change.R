# Read a committed summary_change.csv in either temporal vocabulary.
#
# ONE definition, sourced by data-raw/break_class_groups.R and
# data-raw/benchmark_break_category_bulk.R. Both need it, and a second copy of a
# mapping is exactly the shape drift#72 exists to remove.
#
# The committed per-group files record runs made under a FOUR-level vocabulary,
# in which `flicker` was every n_flips >= 2 and the two populations were told
# apart only by the `changed` column. They are the record of what was measured
# and are not rewritten. drift >= 0.16.0 names them apart
# (dft_break_category(), #72), and the map is a bijection with
# (changed, four-level), so nothing is lost either way.
#
# Requires drift to be loaded (break_category_levels()).

# The retired vocabulary, kept only to READ its output.
cat_labels <- c("stable", "break_sustained", "break_endpoint", "flicker")

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

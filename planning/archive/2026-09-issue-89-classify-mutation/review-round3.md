# Review round 3 — #89 (`dft_rast_classify()` mutates the caller's raster)

## Clean

No issues found. Probes ran read-only from the scratchpad; the repo is untouched apart from this
file.

## What was checked (not a repeat of rounds 1-2)

- **`coltab<-` cannot skip its deepcopy.** At 1.9.50 the only method is signature
  `x = "SpatRaster"` (`showMethods("coltab<-")`), so a data.frame `value` cannot dispatch
  anywhere else. `x@pntr <- x@pntr$deepcopy()` is the first statement of `.local`, ahead of the
  `layer=` handling, the `NULL` early `return(x)`, and both `error()` branches. So no path through
  it both reaches `set.cats()` and skips the copy. The branch on `inherits(value, "list")` does not
  catch a data.frame either, because `inherits()` reads the class attribute and that is just
  `"data.frame"`. `coltab_df` is built with `data.frame()`, not taken from the class-table tibble.
- **Colours cannot be lost by the reorder, at the 1.8-10 floor or at 1.9.50.** I pulled
  `terra_1.8-10.tar.gz` from the CRAN archive. `SpatRaster::setCategories()` writes only
  `source[].cats` / `hasCategories`, and `setColors()` writes only `source[].cols` / `hasColors`,
  so neither resets the other and their order does not matter. The R-level `set.cats()` at 1.8-10
  touches the pointer only through `setNames(nms, FALSE)`, `setCategories()` and
  `removeCategories()`, never the colours. A `setColors()` failure is a warning through
  `messages()` in both orders, so the outcome is the same either way.
- **The error paths moved in the safe direction.** Before, a `coltab<-` error (for example an
  invalid colour string, which makes `col2rgb()` abort) came after `set.cats()` had already
  renamed and factored the caller's raster. Now it comes before anything is touched. The
  `set.cats()` errors (NA id, duplicate id) cannot be reached: the class-table codes are unique,
  and `%in% present_codes` removes NA because `unique()` drops NA by default.
- **Memory:** the old order also paid the `coltab<-` deepcopy. The new order moves that copy but
  adds none.
- **Can the new test pass for the wrong reason?** No. Each platform-dependent assumption can only
  fail loudly:
  - The layer name `"data"` and the file having no colour table are asserted directly.
  - `inMemory(r_mem)` is asserted, and the tile is 314 x 326.
  - The list case checks `x[["2017"]]`, and `lapply` hands that same object's pointer to the
    function.

  The bug makes all three inputs `is.factor` and renames them to `"class_name"`, and the test
  asserts against both.

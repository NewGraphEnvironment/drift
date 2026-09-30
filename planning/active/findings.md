# Findings — dft_rast_classify() mutates the caller's raster in place (set.cats on the input) (#89)

## Issue context

## Problem

`dft_rast_classify()` calls `terra::set.cats(x, ...)` on the raster it was given (`R/dft_rast_classify.R:49`). `set.cats()` works in place, so the caller's object turns into a factor named `class_name`. When `remap = NULL`, `x` is the caller's own SpatRaster, not a copy.

```r
r <- terra::rast(system.file("extdata", "example_2017.tif", package = "drift"))
names(r); terra::is.factor(r)        # "data" FALSE
cl <- dft_rast_classify(list("2017" = r), source = "io-lulc")
names(r); terra::is.factor(r)        # "class_name" TRUE   <- the input changed
```

Found in #81. A test built `c(r17, r23)` from the raw tiles after an earlier test had classified `r17`, and the layer names were no longer the file's. Any caller that classifies a raster and then reuses the original for anything that reads names or levels is affected, for example stacking it or passing it back into a function that validates it.

CLAUDE.md's spatial conventions already name the trap: `set.cats()` "mutates whatever raster it is given, so use it on a copy you own".

## Fix

Take a copy before `set.cats()` (`x <- terra::deepcopy(x)`, or `levels<-`, which copies first), and add a test asserting that the caller's raster keeps its names and stays a non-factor. Check the other `set.cats()` / `set.names()` / `set.values()` call sites in `R/` for the same shape.

Not fixed in #81: it is outside that issue, and #81's tests now avoid relying on it.

## Plan-mode exploration (2026-09-29)

### Probe and call-site sweep

`dft_rast_classify()` calls `terra::set.cats(x, ...)` (`R/dft_rast_classify.R:49`) on the raster it
was handed. `set.cats()` works in place, so with `remap = NULL` the caller's object becomes a factor
named `class_name`. Found in #81; NEWS 0.19.0 already names it as "found on the way".

**Probed (terra 1.9.50, in memory, source tree):**

| input | caller after the call |
|---|---|
| file-backed single raster | `class_name`, factor — **mutated** |
| in-memory raster (`r * 1L`) | **mutated** |
| element of a named list | **mutated** |
| `remap =` supplied | untouched (`terra::classify()` returns a new raster) |

**Fix found by probe, zero extra copy:** swap the two setters — `coltab<-` first (it deep-copies
unconditionally, the same fact `strip_copy()` in `R/dft_rast_break_class.R:350` already relies on
and documents), then `set.cats()` on that copy. Output is identical to today's
(`identical()` on `cats()` and `coltab()`), and the caller comes back `data` / non-factor.

Chosen over the issue's `x <- terra::deepcopy(x)`: that adds a second full copy, because `coltab<-`
still copies afterwards. For an in-memory BULK year (what `dft_stac_fetch()` returns when it fits,
~1.5 GB) that is +1.5 GB transient per year. The reorder's reliance on `coltab<-` copying is guarded
by the new test, which goes red if terra ever makes it in place.

**Other call sites checked — all act on rasters the function itself created, none need a change:**
`dft_rast_transition.R` (141/158/177: `r_trans`/`r_removed` from arithmetic / `ifel`),
`dft_rast_consensus.R:92` (`r_out <- terra::rast(x[[1]])`, an empty template),
`dft_rast_break_category.R:153` (`app()` output), `dft_rast_break_class.R` (207: stack from
`rast(list)`, already guarded by the caller-unmutated test at `test-dft_rast_break_class.R:329`;
267/302: `out[["transition"]]` subset; 362: `strip_copy()` after `coltab<-`),
`dft_transition_artifact.R:308` (explicit `deepcopy`), `dft_stac_cube.R:287` (`names<-` on its own
`stk`).

## Errors Encountered

| Error | Resolution |
|-------|------------|

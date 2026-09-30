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

## BULK scale check (2026-09-29, Phase 3)

`bulk_co_ff04/classified_2017.tif` (14651 x 11552, 169,248,352 cells), terra 1.9.50, 64 GB machine.
Each variant a fresh `R -f` process under `/usr/bin/time -l` (kernel max RSS), two reps each, identical
to 0.01 GiB. "mem" is `r * 1L` (in memory, the shape `dft_stac_fetch()` returns when it fits). Script:
scratchpad `bulk_classify2.R`; `main` is `git show origin/main:R/dft_rast_classify.R` sourced into
the namespace; `deepcopy` is main's order with `x <- terra::deepcopy(x)` before it (the issue's fix).

| variant | input | max RSS (GiB) | classify (s) | caller untouched |
|---|---|---|---|---|
| main | file-backed | 1.05 | 0.8 | no |
| branch | file-backed | 1.05 | 0.8 | yes |
| main | in memory | 4.21 | 0.8 | no |
| branch | in memory | 4.21 | 0.9 | yes |
| deepcopy | in memory | 5.46 | 1.2 | yes |

The reorder costs nothing; `deepcopy()` costs +1.25 GiB, one 169M-cell double copy, per year classified.
Branch and main outputs are `identical()` in `cats()` and `coltab()` in both modes.

"Caller untouched" for file-backed is from a `cats()`/`coltab()`/`names()`/`is.factor()` snapshot
compared before and after. The published raster is ALREADY a factor (RAT with `class_name`, palette),
so a names-only check reads it as mutated whatever happens — the first run of the script did exactly
that and briefly looked like the fix failing at scale.

### Wrong turns (kept as evidence)

- **Diagnosed, then retracted: "`Rscript` forks `R`, so the sampler watched the wrapper."** A 2 s
  `ps` sampler gave 0.26 GiB for a 169M-cell in-memory raster, and I blamed the PID. Wrong: measured
  afterwards, `Rscript` execs in place. The backgrounded PID's `comm` is `.../bin/exec/R`, it has no
  children, and it equals R's own `Sys.getpid()`. Switching to `R -f` changed nothing that mattered.
- **The actual cause: a 2 s sampler on a ~1 s call.** Samples land at arbitrary instants, and the
  classify peak lasts well under the interval. Readings for the same variant ranged from 0.26 to
  2.31 GiB, and the deepcopy variant read 0.25 GiB, below the size of its own in-memory input.
  `/usr/bin/time -l` reports the kernel's true peak and gave identical numbers across two reps. The
  CLAUDE.md "RSS every 2 s" recipe fits the minutes-long pipeline functions it was written for, not
  a sub-second call.

### Found on the way: factor input gives empty levels (drift#91)

On the published (already-factor) raster the output had no levels and no colours on main and on the
branch. `terra::unique(x)[, 1]` returns labels on a factor, so no code matches `class_table$code`.
Pre-existing, out of scope for #89; filed as drift#91. Round-1 review found it independently.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| BULK RSS 0.26 GiB for an in-memory 169M-cell raster | Not the PID (`Rscript` execs in place, verified). A 2 s sampler misses a sub-second peak; use `/usr/bin/time -l` |
| `cmd && V=... && R ... & PID=$!` lost `$PID` | `&` backgrounds the whole `&&` list; split setup and the backgrounded command |

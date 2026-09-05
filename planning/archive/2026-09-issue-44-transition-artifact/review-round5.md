# Review round 5 — `artifact_boundary_frac()` disk-backed rewrite (PR #60)

Reviewer: code-check subagent, 2026-09-05. Scope: staged diff to
`R/dft_transition_artifact.R` (helper rewrite only; tests and helper-artifact.R
unchanged). terra 1.9.34. All probes read-only via `pkgload::load_all()`; scripts in
the session scratchpad (`probe5.R`, `probe5b.R`, `probe5c.R`).

## Verdict: Clean

No bug, security or data-loss finding. Every requested probe was run and passed;
the one guard whose fragility was asked about (layer ordering) is exercised by an
existing test.

## Probe results

| # | question | result |
|---|---|---|
| 1 | `deepcopy()` + `levels(x) <- NULL` mutates caller's `transition`? | No. `is.factor()` TRUE and `cats()` byte-identical after the call; a second `dft_transition_artifact()` on the same object returns identical fracs. `levels(copy) <- NULL` leaves the source factor. |
| 2 | `app(fun = x %/% 1000L)` vs `(transition * 1L) %/% 1000L` | Identical on all cells, including a raster with 9 NA cells (same NA pattern, same values). Also measured: `app()` on the *factor* raster directly gives the same codes (with a `[app] factors are coerced to numeric` warning), so the `deepcopy`/`levels<-NULL` pair suppresses the warning rather than changing the numbers. Not load-bearing for correctness. |
| 3 | `segregate()` layer order / NA / all-zero class / length 1 | Layers come back in **ascending numeric order regardless of the order of `classes=`** (`classes = c(4,2,3)` gives names `2,3,4` and layer 1 is class 2). The code's `sort(unique(to_code))` therefore lines up with it; the `sort()` is load-bearing. A class absent from the raster (`99`) is kept as an all-zero layer, not dropped. `classes` of length 1 gives 1 layer. NA preserved in every layer. |
| 4 | `focal()` multi-layer with `filename=` | Per-layer results identical to `focal()` on each layer separately. Layer names carried through (`2,3,4`). |
| 5 | `zonal(near, pid, "mean", na.rm=TRUE)` | Returns `patch_id` then one double column per layer, named by class; zones in ascending `patch_id` order. An all-zero layer still produces its column (`patch_id,2,99`). Length-1 gives 2 columns. The all-NA-zone case cannot arise: `near` is NA only where `code_from` is NA, and every rasterized patch cell has a non-NA transition value (`focal(na.rm=TRUE)` in fact *fills* NA cells that have a non-NA neighbour — 9 -> 4 NA — which is irrelevant to patch cells and matches the previous implementation). |
| 6 | temp files and dangling references | Zero `dft_artifact_*` files (including `.aux.xml`) left in `tempdir()` after the calls; the closure-captured `files` vector is read at exit time so late appends are included. Helper returns a plain numeric vector; no SpatRaster pointing at an unlinked file escapes. (Windows behaviour of `unlink()` on a file terra may still hold open was not measured — no Windows CI in this repo — and would at worst leave files until session end, not corrupt results.) |
| 7 | `tempfile()` collisions under fork | `parallel::mclapply` x4 returned four distinct names. |
| 8 | `match(patch_id, z[[1]])` int vs double | `z[[1]]` is double, `patch_id` integer; `match()` compares numerically and hit every id. Also checked the `rasterize(filename=)` datatype: terra writes `Float32` for the fixture ids but switches to **`Float64`** when ids exceed 2^24 (`16777217..16777220` round-tripped exactly from a fresh `rast(file)` read), so the disk-backed `pid` does not lose precision for large patch counts. |

### Restore-the-bug: would a silent layer reorder be caught?

Yes. Reversing the class-to-column mapping (columns swapped for the road fixture)
yields `Trees -> Bare = 0.05` (test pins `4/20`), `Rangeland -> Bare = 1` (pins `0`),
and the two `Trees -> Rangeland` bands `0,0` (pins `1,1`). The road test's three
distinct to-classes with three distinct expected fractions is what makes the guard
discriminating; the river fixture alone (both fracs `1`) would not be. This is not a
finding — the guard fires.

### Disk footprint (checked, not a finding)

The intermediates are written as `Float32` GeoTIFFs, LZW-compressed by terra's
default. Measured on a 1000 x 1000 x 8-layer random-class stack: `segregate` output
0.17 bytes/cell/layer, `focal` output ~0.26. Extrapolated to 169M cells x 8 classes:
~0.2 GB + ~0.4 GB, and real data is more compressible than random. No temp-disk
risk on the target grid.

## Checklist items consulted

- Code Check — Spatial, terra entries: `%in%` dispatch (not used), `freq()` on
  all-NA (not used), `minmax()` cached stats (not used), `mask()` touches (not
  used), `sources()` (not used). None applicable to the diff.
- "A proxy is not the property": the per-class column lookup relies on segregate's
  ordering contract, not on a proxy for it; the property (column i is class ks[i]) is
  asserted indirectly by pinned fraction values in the road test.
- "Restore the bug and prove the guard fires": done above; the guard fires.
- Accepted tradeoffs (lintr `bad`, NA for stable patches, 0.5 threshold,
  unfiltered-raster requirement, 143 s runtime) not re-flagged.

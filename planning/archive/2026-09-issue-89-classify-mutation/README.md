## Outcome

`dft_rast_classify()` modified the raster it was given: it called the in-place `terra::set.cats()` on the caller's own object, so the original came back as a factor named `class_name`. That held for file-backed, in-memory and list-element inputs, and for a `remap =` that matched no class. The fix swaps the two setters. `coltab<-` deep-copies as its first statement at every supported terra (checked at the 1.8-10 floor and at 1.9.50), so the levels are now set on that copy. The output is `identical()` to 0.19.0, and no second copy is made. A new test pins the caller as unmodified and goes red on the old order with 6 failures. Code-check ran three rounds, all clean. The BULK run found a separate, pre-existing defect: a raster that is already a factor gets empty levels, because `terra::unique()` returns labels. It is filed as drift#91.

## Measurement

BULK `classified_2017.tif` (169,248,352 cells), terra 1.9.50. Kernel max RSS from `/usr/bin/time -l`, two reps, identical to 0.01 GiB:

| variant | input | max RSS (GiB) | caller untouched |
|---|---|---|---|
| 0.19.0 order | in memory | 4.21 | no |
| reorder (shipped) | in memory | 4.21 | yes |
| `deepcopy()` then 0.19.0 order (the issue's proposal) | in memory | 5.46 | yes |
| 0.19.0 / reorder | file-backed | 1.05 / 1.05 | no / yes |

The reorder costs nothing. `deepcopy()` would add 1.25 GiB, one full double copy, per year classified in memory. That number decided the design.

**Wrong turn, kept.** The first measurement used a 2 s `ps` sampler and read 0.26 GiB for the in-memory run. I blamed sampling the `Rscript` PID instead of R, then retracted that: `Rscript` execs in place and the PID is R's own. The real cause was a 2 s sampler on a call whose peak lasts under a second; its readings for one variant ranged from 0.26 to 2.31 GiB. The same run also briefly suggested the fix failed at scale. That came from a names-only check against an input that was already a factor, and a `cats()`/`coltab()` snapshot resolved it. The resulting CLAUDE.md note says to use `/usr/bin/time -l` for sub-minute scale checks.

## Evidence

The scripts were one-off and ran in the session scratchpad; the numbers above and in `findings.md` are the record.

Closed by: PR for #89 (branch `89-dft-rast-classify-mutates-the-caller-s-r`)

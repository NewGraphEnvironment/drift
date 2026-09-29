## Outcome

Added dated reference imagery for floodplains#93's accuracy assessment:

- `dft_stac_composite()`: per-year, cloud-masked median reflectance composites, cached as COGs, on a read path now shared with `dft_stac_cube()`;
- dated RGB layers in `dft_map_interactive(rgb =)`, with one stretch shared across years;
- NDWI and MNDWI.

HLS was split to #82 after a live spike. The plan gate pivoted the work twice. #80 (gdalcubes archived on CRAN) went first as its own PR, #84. The scale requirement, sample points across whole floodplains, set the design. The plan review then showed the planned chip path (one tiled call over all points) would return a floodplain-sized raster under a single key, so chips became one call per point.

What was learned is mostly about failure modes that stay silent at reach scale:

- terra reads gdalcubes' multi-variable NetCDF alphabetically, so a true-colour request came back blue-green-red. The live e2e's layer-order guard caught it.
- A NetCDF-derived time made the COG writer strand a sidecar. The first fix missed it because its fixture carried no time. Code-check R2 caught that, and R3 closed the class by enumerating every raster write and every stub.
- Classified layers had always reached leaflet misregistered (4326 passed as 3857).
- A date-only STAC end bound drops the last day.
- At BULK scale: Planetary Computer's ~1 MiB search body limit made the floodplain unqueryable (fixed: convex hull), and ~45-min SAS tokens silently holed a long tiled read (fixed: re-sign per extent). A full floodplain-wide read then completed, but clipping the merged mosaic failed and did not reproduce offline (#88, open).

The durable findings are in `inst/notes/gdalcubes-pc-gotchas.md`, section "Floodplain scale and multi-band reads".

## Measurement

**Refactor identity.** An untiled NDVI cube (packaged AOI, 2021-07/08, parallel 4) from main and from the refactor gave identical values and NA pattern, max diff 0 (77.1 s vs 77.7 s). The network e2e passed 110 for the cube, including tiled vs untiled, and 64 for the composite.

**Per-point chips on BULK** (100 points, 300 m buffers, 2023 Jul-Aug):

- 84.1 min total;
- per chip: median 40.2 s, mean 50.5 s, max 140.9 s;
- 3,660 cells per chip, a 3.8 MB cache, peak RSS 0.48 GiB.

Splitting by stage: the STAC query is 1.4-2.5 s, and the rest is about 64 remote COG opens per chip. That turned "query once for all chips" into "run chips concurrently" (#85).

**STAC body limit.** Planetary Computer accepted 21,348 vertices (860 KB) and returned HTTP 413 at 26,508 (1.07 MB). BULK is 104,584 vertices (4.2 MB). The hull is used above 20,000 vertices.

**Tokens.** A token issued at 17:16:55Z expired at 18:01:55Z (about 45 min). Run 2 lost 15 of 30 tiles in 54 min. With corrupted tokens, re-signing read 102,364 cells against 0.

**Detecting failed chunks.** Capturing stderr caught the gdalcubes chunk-error line in 1 of 4 configurations (never at parallel > 1), so it was not shipped as a guard.

**Floodplain-wide BULK** (`tile_size = 20000`, 30 tiles), in order:

1. Run 1: HTTP 413 in 9 s.
2. Run 2: 54 min, 15 tiles lost, then the COG write failed. The first diagnosis, that the write failed because of the failed tiles, was **retracted**: run 4 failed the same way with every tile read.
3. Run 3: killed at a 2-h cap after 16 tiles (5.4-11.9 min each), no chunk failures.
4. Run 4: all 30 tiles in 3 h 16 min, peak RSS 3.90 GiB, then `terra::mask` "cannot read from" the merged mosaic's temp file.

Ruled out for run 4 (#88):

- disk space (1 TB free);
- a floodplain-size COG write (82 s, 459 MB);
- terra deleting the temp file on GC;
- merging and masking 30 synthetic NetCDF tiles on the same grid with the real polygon, which took 0.7 min.

The live run is not reproduced.

## Evidence

- `data-raw/logs/benchmark_composite_bulk/*`: chips per-chip times, RSS and wall clock for the chips run and the last floodplain run. Earlier floodplain runs were overwritten by the wrapper; their numbers are above.
- `data-raw/benchmark_composite_bulk*.{R,sh}`: the benchmark. Its floodplain stage now inventories temp files on failure.
- `review-plan.md`, `review-79-round{1,2,3}.md`: the plan review and code-check rounds, each with its verdicts.

Closed by: PR #86

# Findings — Adopt the fixed filter_geom (#47)

## Issue context

Issue #47 proposes calling `gdalcubes::filter_geom()` in `dft_stac_cube()` so the AOI enters the
**read**, dropping the redundant output-side `terra::mask()`; the same for `dft_stac_fetch()`; a smoke
test asserting non-NA coverage inside the polygon; and an explicit decision on dependency posture
(runtime capability probe vs hard-requiring the fork via `Remotes:`).

Its stated value: on the packaged Neexdzii AOI, area/bbox ≈ 0.105, so ~90% of the streamed bounding box
is outside the polygon — a ~10× streaming overhead. It notes that client-side tiling was the alternative
and was measured and rejected upstream (NewGraphEnvironment/floodplains#8), so `filter_geom` is
"the one left".

Related: #38 (parent, closed naming `filter_geom` as the way out), #32 (the `terra::mask()` workaround),
#36 / floodplains#8 (client-side tiling, measured and rejected),
`inst/notes/gdalcubes-pc-gotchas.md` (records the original segfault).

## Pre-implementation exploration (2026-09-01)

### The fork is installed, and its version string collides with the broken CRAN build

```
installed version:   0.7.4
filter_geom exported: TRUE
RemoteUsername:      NewGraphEnvironment
RemoteRepo:          gdalcubes
RemoteRef:           newgraph
RemoteSha:           8bad203afa18af873882784951967ba3e35c62c4
```

CRAN gdalcubes is **also 0.7.4** (published 2026-05-29, per crandb). Upstream `appelmar/gdalcubes#110`
is **open**; the fix PR `appelmar/gdalcubes#111` is **open and unmerged**. So:

- a `packageVersion()` / `compareVersion()` check **cannot** distinguish fixed from broken;
- `"filter_geom" %in% getNamespaceExports("gdalcubes")` cannot either — CRAN exports it too. Presence
  is not provenance.

The fork's `newgraph` branch is `2cc0d46 v0.7.4 release candidate` + `67c3480 Fix segfault when
computing filter_geom() cubes` + `7c7cbf3 Add regression test`.

### The failure is bimodal, and one mode is silent

From upstream #110, reproducible **offline** with a 200×200 local GeoTIFF and a plain rectangle:

```
*** caught segfault ***
address 0x120, cause 'invalid permissions'
 1: gdalcubes:::gc_exec_worker(...)
[ERROR] worker process #0 returned 11
```

`inst/notes/gdalcubes-pc-gotchas.md:8-9` records the other mode: "segfaults / returns an **all-NA
cube**". A hard segfault cannot be caught by `tryCatch`, and an all-NA cube raises nothing at all.
Consequences for any guard: it must run in a **subprocess**, and it must assert on **values**, not on
"the call returned".

### What the fix actually is

`67c3480` touches `src/gdalcubes/src/filter_geom.cpp` only (+20/-5). The load-bearing hunk:

```cpp
-    OGRSpatialReference srs_cube = st_reference()->srs_ogr();
...
-    pp.assignSpatialReference(&srs_cube);
+    // no SRS is assigned to pp: assignSpatialReference() takes refcounted ownership
+    // and ~OGRGeometry() calls Release() on it, which crashes for stack-allocated
+    // SRS objects; Contains() / Intersects() below do not use the SRS anyway
```

plus null-guards on the GPKG driver, the first feature, and `GDALRasterize`, and leak fixes on the
error paths. The crash is in `filter_geom`'s own chunk logic — not in the COG reader. That bounds what
a probe can claim (see Phase 2).

### The read reduction is real, but its granularity is the CHUNK

`filter_geom_cube::read_chunk()` (fork, `newgraph`):

```cpp
if (outside) {
    GDALClose(in_ogr_dataset);
    return out;                              // empty chunk
}
std::shared_ptr<chunk_data> in = _in_cube->read_chunk(id);   // <- never reached when outside
```

There are two skips: a cheap chunk-index prefilter from the polygon's bbox
(`_min_chunk_x`/`_max_chunk_x`/…, set in the constructor), then a per-chunk
`geom->Intersects(&pp)` test. Both return before the underlying cube is read. So COGs genuinely are not
streamed for skipped chunks — but the unit is a chunk, never a pixel.

### **Default chunking makes the skip a no-op on drift's own example AOI**

`gdalcubes::raster_cube(image_collection, view, mask, chunking = .pkgenv$default_chunksize, ...)`, and
`default_chunksize` is a *function*:

```r
function (nt, ny, nx) {
    nparallel = .pkgenv$parallel
    target_nchunks_space = ceiling(2 * nparallel)
    cx = sqrt(nx * ny/target_nchunks_space)
    cx = ceiling(cx/64) * 64
    cy = cx
    cx = min(cx, 1024); cy = min(cy, 1024)
    cx = max(cx, 64);   cy = max(cy, 64)
    cx = min(nx, cx);   cy = min(ny, cy)
    return(c(1, ceiling(cy), ceiling(cx)))
}
```

`.pkgenv$parallel` defaults to **1**, so it targets **2** spatial chunks over the whole cube. Measured
against the packaged AOI:

```
features: 1
crs EPSG:32609  bbox 3258 x 3130 m  -> at res=10: 326 x 313 px
area 1039643 m2 ; bbox area 10199685 m2 ; ratio 0.1019
default chunking (t,y,x): 1,256,256  -> chunk 2560 m x 2560 m
n chunks: 2 x 2
```

**A 2 × 2 chunk grid over a corridor: every chunk intersects the polygon, so nothing is skipped.**
Out of the box, `filter_geom` on drift's own example AOI reduces the read by zero. The issue's ~10×
is not reachable without setting `chunking` explicitly.

The clamp `cx = max(cx, 64)` puts the finest achievable granularity at **64 px = 640 m** at `res = 10`.
That is genuinely finer than a typical `tile_size`, so a gain exists — but it must be measured, and it
is bounded well short of polygon-exact.

### The polygon must be strictly interior to the cube, and drift's is not

`filter_geom_cube`'s constructor:

```cpp
bool within = iminx >= 0 && uint32_t(iminx) < ...->nx() && imaxx >= 0 && uint32_t(imaxx) < ...->nx() && ...;
if (!within) {
    GCBS_ERROR("Polygon must be located completely within the data cube");
    throw std::string("Polygon must be located completely within the data cube");
}
```

drift's cube extent **is** `st_bbox(aoi_target)` (`R/dft_stac_cube.R:329-332`), so the polygon touches
every edge and `imaxx == nx`, failing `imaxx < nx`. gdalcubes enlarges the untiled extent symmetrically
to align with `dx`/`dy` (~0.5 px, per `gdalcubes-pc-gotchas.md:36-44`), which *may* save it by a hair —
far too thin to rely on. Phase 1 measures the minimum padding.

### Multi-feature AOIs are handled at the R level

The C++ reads only the first feature (`// assumption, there is only one feature`), but
`gdalcubes::filter_geom()` does `if (length(geom) > 1) geom = sf::st_combine(geom)` before handing over
a single WKT. drift will still pass an explicitly unioned geometry, matching the `st_union` already used
for the STAC `intersects` query (`R/dft_stac_cube.R:231-234`).

### drift already has a working read-bound, so the comparison is not against zero

`tile_size` (#36/#38) tiles the `cube_view` and mosaics. Its known costs: the tiled cube is **not
co-lattice** with the untiled one (sub-pixel offset, `gdalcubes-pc-gotchas.md:36-51`), and it pays
per-tile round trips. `filter_geom`'s advantages over it are structural — one cube, one grid, no
`terra::merge`, no sub-pixel offset, and it subsumes the output clip. Whether those are worth two code
paths is what Phase 1 decides.

## Errors Encountered

| Error | Resolution |
|-------|------------|

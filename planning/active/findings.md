# Findings — corrupt cache trusted as a hit on resume (#41)

## Measured damage taxonomy — three shapes, not one

Probed on 2026-09-02 with terra 1.9.34, GDAL 3.8.5, gdalcubes 0.7.4 (macOS), against a **real
gdalcubes-written** cache file (`~/Library/Caches/drift/io-lulc/2020_fa29496cfb81.nc`, 199 KB).

| shape | `terra::rast()` | geometry | pixel read |
|---|---|---|---|
| tail-truncated (10/50/90/99%, and 0 bytes) | **errors** | — | — |
| broken geotransform (the issue's traceback) | succeeds **+ warns** | **degenerate** | `mask()` fails |
| content-damaged, size preserved | succeeds **silently** | **valid** | `NetCDF: HDF error` |

Each row kills an otherwise-obvious design:

- `tryCatch(terra::rast())` alone catches only the first row. It passes the reported case and the
  content-damage case.
- A metadata/geometry check passes content damage entirely — dim, res, CRS all correct, and
  `terra::mask()` succeeds on it.
- Content damage is detectable **only via the warning raised during the read**. Values come back
  looking plausible (`nNA = 0`), so nothing is inferable by inspecting them. This is the
  "a valid response is not a correct one" shape.

## The reported failure is not reproducible by truncation

The issue's traceback shows `rast()` **succeeding** (warning `cannot open this file with the
multidim API`, then `Cannot invert geotransform`) and the failure landing later at
`terra::mask()`. Every truncation fraction I tried instead makes `rast()` **error outright**.

So a fixture built by truncating a file exercises arm (a) and proves nothing about arm (b). Arm
(b)'s test must drive the predicate with a constructed degenerate raster and say so, rather than
truncate and imply coverage it does not have.

## Cost of the read probe

On a 13 MB cache file: `terra::values(x, row = 1, nrows = 1)` = **0.08 s**;
`terra::minmax(x, compute = TRUE)` = **2.4 s**. The warning fires on the one-row read, so the cheap
probe is the one that works. It **samples rather than proves** — damage confined to a region row 1
does not touch may not warn — and that limit is documented rather than overstated.

## No existing corruption to reconcile

Scanned all **168** files in `~/Library/Caches/drift`: 0 open failures, 0 warnings, 0 bad
geometry. The corrupt file from the original report was already deleted by hand. Therefore this
fix needs **no cache-key break** and no migration — unlike #51, where a salt was added to
invalidate rasters built from truncated item sets.

## The same defect exists in `dft_stac_cube()`

`R/dft_stac_cube.R:429` writes `terra::writeRaster(stk, cache_file, overwrite = TRUE)` directly to
the canonical path, and `:264` is a presence-only gate. Not named in the issue; user scoped it in.
Its cache is the costlier one to lose — a multi-hour Sentinel-2 stream against fetch's small
annual rasters.

`cube_check_nonempty()` (`:449`) does **not** cover any of the three arms — it answers "is this
cube all-NA", a different question, and it assumes an already-readable raster.

## Design notes

- The temp file must **keep the real extension**: `terra::writeRaster()` infers its driver from it,
  so a `.tmp` suffix picks the wrong driver or fails.
- `file.rename()` signals failure by **returning `FALSE`**, not by erroring — an unchecked move is
  the classic way a missing file reaches a consumer.
- `on.exit()` covers R-level error and interrupt but **not SIGKILL**, so a hard kill still leaves a
  `drift-partial-*` orphan. That orphan is never a cache hit (wrong name), which is the point.
- The issue proposed a `.tmp` sweep in `dft_cache_clear()`; that function already `unlink()`s the
  directory recursively (`R/dft_cache.R:47`), so orphans are removed today. A sweep at *fetch* time
  was rejected — it would delete a concurrently-running second process's temp file.

## Plan-review findings, verified against measurement

A `Plan` subagent reviewed the design. Its findings were probed rather than adopted — **two of its
three empirical premises are refuted**, and one is right in substance for the wrong reason.

### Refuted: "a truncated `.tif` opens fine and row 1 decodes"

The review argued the row probe silently passes truncated GeoTIFFs, so half the package
(tiled fetch + all of cube) would be uncovered, and that the probe must read the **last** row.

Measured on 11 MB terra-written GeoTIFFs, both striped and `TILED=YES BLOCKXSIZE=256`, truncated
to 30/60/90/99%: `terra::rast()` **errors in every case**. Terra writes the IFD at the end of the
file, so truncation always destroys the open. Arm (a) therefore covers truncated `.tif`
completely, and the premise for switching probes does not hold.

The last row is still what gets probed — same cost, and for any partially-written file the tail is
the least likely part to be complete — but on that reasoning, not the refuted one.

### Refuted: PAM sidecar hazard on the cube write

The review flagged that `terra::writeRaster()` might emit a `<file>.tif.aux.xml` sidecar which a
single rename would strand. Measured on the exact cube write shape (12-layer stack with
`terra::time()` and `names()` set immediately before writing): **one file, no sidecar**. No
dual-rename needed.

### Confirmed in substance, wrong mechanism: arm (c)'s fixture

The review predicted a terra-written `.nc` would be classic NC3, so zeroing its tail would yield
valid zero *data* and the test would pass while never reaching the arm.

The format claim is wrong — terra writes **NC4/HDF5** (magic `89 48 44 46`). But the conclusion
holds by measurement: zeroing the tail of a terra-written `.nc` produces **no warning at all**
(opens clean, first and last row both read clean), where the same damage to a *gdalcubes*-written
`.nc` warned. Whether arm (c) fires depends on whether the damaged bytes carried structure or bulk
data — which is precisely why the probe **samples rather than proves**.

So arm (c)'s CI test drives the handler with an injected warning-raising probe and is named for
that, and the fixture-based version is env-guarded and asserts its own premise (skip, don't pass,
if the damage fails to warn).

### Adopted: validate the TEMP before renaming

The review's strongest point, and one I had missed. On the **miss** branch the freshly written file
flows straight into `terra::mask(terra::rast(cache_file), ...)` at `R/dft_stac_fetch.R:192`
completely unvalidated — which is exactly where the reported #41 traceback dies. Validating the
temp before the rename also covers `force = TRUE`, which a read-side gate by construction never
reaches, and costs nothing extra because the bytes are hot in page cache.

### Adopted: fold the cube's arm (c) into the scan it already pays for

`cube_check_nonempty()` (`R/dft_stac_cube.R:449`) calls `terra::global(stk, "notNA")` — it already
reads **every pixel** on the cache-hit path. Wrapping that existing call in a warning handler gives
the cube a whole-file read probe at zero added cost, strictly stronger than any row probe. The two
functions stay separate: an empty cube *aborts* (re-fetching will not fix a non-overlapping AOI), a
corrupt one *re-fetches*. Validity is checked first so a truncated file that happens to read all-NA
is reported as corrupt rather than as an AOI mismatch.

### Also adopted

- **`force = TRUE` currently destroys a good cache in place.** Lines 480/497/429 truncate the
  canonical file before writing, so an interrupted forced re-fetch loses a previously valid cache.
  A second instance of #41, fixed for free by the atomic write. NEWS-worthy.
- **Concurrency:** two sessions fetching the same key today interleave writes onto one path.
  Unique temp + rename turns that into clean last-writer-wins. Temp name carries PID and a counter.
- **No leading dot on the temp** — `dft_cache_info()`/`dft_cache_clear()` call `list.files()` with
  the default `all.files = FALSE`, so a hidden temp would be invisible to the size report and
  under-report the removal count.
- **Arm (a) catches errors only, never the multidim open warning** — that warning is a capability
  message, and the suite already `suppressWarnings()` around writing a `.nc` through terra
  (`test-dft_stac_fetch.R:560`). Failing on it would refuse healthy `.nc` files.
- **Empty CRS is checked as a conjunction** with the identity geotransform (`res == 1`, extent
  `c(0, ncol, 0, nrow)`), not alone — two independent signals, and that conjunction is exactly the
  shape the issue's traceback describes.
- **Predicate split from extraction** (`cache_geom_ok()` over plain numerics) because terra refuses
  to construct a zero-dim / non-finite-res / collapsed-extent raster, so three of four sub-checks
  would otherwise ship with no test able to reach them.
- **`unlink(tile_files)` at `R/dft_stac_fetch.R:189` only runs on success** — a `mosaic_tiles()`
  error leaks every tile. Fixed with `on.exit(add = TRUE)`.
- **Docs at `R/dft_stac_fetch.R:44-47` and `R/dft_stac_cube.R:110-111`** promise that an
  earlier-returned raster "may silently pick up the rewritten contents". After the rename the old
  object keeps reading the unlinked inode on POSIX, so that text becomes wrong.

### Noted, not fixed (out of scope)

- `build_index_stack()` (`R/dft_stac_cube.R:350`) never unlinks its `tempfile()`, and returns a
  raster file-backed on it.
- `dft_cache_clear()` races an in-flight fetch (`R/dft_cache.R:47` removes the source dir that
  `R/dft_stac_fetch.R:152` recreates). Pre-existing; not made worse here.

## Errors Encountered

| Error | Resolution |
|-------|------------|

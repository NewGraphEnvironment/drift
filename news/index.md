# Changelog

## drift 0.12.0

- **Bug fix: the cache key moved on an rlang upgrade, silently orphaning
  every cached cube and fetch
  ([\#48](https://github.com/NewGraphEnvironment/drift/issues/48)).**
  The key **is** the cache filename (`<year>_<key>.nc`,
  `cube_<key>.tif`), and
  [`rlang::hash()`](https://rlang.r-lib.org/reference/hash.html) was
  rewritten in rlang 1.3.0. Its own NEWS says so: *“with this version
  all hash values will now be different… you should assume it’s always
  possible for a new version to invalidate existing hashes.”* So every
  cache entry became unreachable — no error, no warning, no log line;
  the only symptom was “the pipeline got slower”, which is exactly the
  kind of thing nobody files. The frozen goldens were the only reason it
  was known.
- **The reported diagnosis was wrong, and the correction changed the
  fix.** The issue suspected sf/PROJ drift under
  [`sf::st_as_binary()`](https://r-spatial.github.io/sf/reference/st_as_binary.html).
  Measured: the key function extracted from its own pinning commit
  reproduces today’s value exactly, so nothing in drift moved. Both
  pre-rlang-1.3.0 goldens fail to reproduce and the one re-pinned
  *after* the upgrade holds — and rlang 1.3.0 was installed between
  them. A fix aimed at the geometry member would have left the real
  cause untouched.
- **Keys are now a function of content alone.** Each member is rendered
  to a canonical string (geometry WKB as hex, numerics as IEEE-754
  bytes, characters through
  [`enc2utf8()`](https://rdrr.io/r/base/Encoding.html), a one-character
  type tag per member) and that string is hashed **by its bytes** with
  `digest::digest(algo = "xxhash64", serialize = FALSE)` — no R
  serializer, no library traversal of an R object. `digest` joins
  Imports. It is a categorically different bet from rlang: it implements
  a **published** algorithm and pins this exact call shape to the
  upstream XXH64 reference vector in its own test suite, where rlang
  explicitly reserves the right to change. drift pins that same vector
  as a control test, so a future failure distinguishes “the hashing
  layer moved” from “our inputs changed” — a distinction the goldens
  alone could not make.
- **No rlang pin is needed**: rlang is no longer in the key path at all.
- **The key is now 16 characters, not 12**, which changes the documented
  `attr(, "cache_key")` return value. A key collision does not crash —
  it silently serves the **wrong raster**, and nothing downstream can
  detect it. 48 bits to 64 costs four characters of filename and buys a
  65,536x margin, and re-keying was already being paid for, so this was
  the only moment it was free.
- **Cache entries move under a scheme directory,
  `<cache>/v2/<source>/`.** A deliberate key change is now a *migration*
  rather than a silent orphaning: superseded generations stay findable,
  [`dft_cache_info()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_info.md)
  reports them (`n_files_superseded`, `size_mb_superseded`), and
  `dft_cache_clear(scheme = "superseded")` reclaims that space. Nothing
  is deleted automatically.
- **What this costs you once:** every existing entry is superseded —
  measured on one real cache, 204 files / 1.09 GB. Re-fetch is **~10 s
  per entry** and **flat in entry size** (0.05 / 0.12 / 0.36 MB all took
  ~10 s; the cost is STAC query, signing and COG opens, not bytes), and
  it happens on demand rather than all at once. The issue’s “10–30 min
  per cube” is real for Sentinel-2 cubes but was not a cost anyone was
  paying — that cache held no cube entries at all. It is the
  forward-looking reason this matters: the next rlang bump would have
  destroyed those silently.
- **Cross-machine:** the key is now identical on any machine, R version,
  rlang version and architecture, so a cache can be shared or copied
  between machines and stay valid. It does **not** avoid a first-run
  rebuild on a new machine — the cache is machine-local — and the
  goldens double as the check, since they are now portable facts rather
  than facts about one environment.
- Three canonicalization hazards are guarded because they were measured,
  not assumed: `digest(serialize = FALSE)` silently hashes **only the
  first element** of a character vector (a length \> 1 would collapse
  every key to one value),
  [`sf::st_as_binary()`](https://r-spatial.github.io/sf/reference/st_as_binary.html)
  returns a **list** so [`is.raw()`](https://rdrr.io/r/base/raw.html) is
  `FALSE` on it, and
  [`is.logical()`](https://rdrr.io/r/base/logical.html) must be branched
  before [`is.numeric()`](https://rdrr.io/r/base/numeric.html) or `TRUE`
  renders as `1`. Numerics use IEEE-754 bytes rather than
  `sprintf("%.17g")`, which keeps `NaN` and `NA_real_` apart
  (`is.na(NaN)` is `TRUE`) and avoids a libc call whose formatting is a
  platform variable — this package has no cross-platform CI, so these
  goldens are verified on one machine.

## drift 0.11.0

- **Bug fix: an interrupted fetch left a corrupt cache entry that every
  later run trusted as a hit
  ([\#41](https://github.com/NewGraphEnvironment/drift/issues/41)).**
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  wrote each year’s raster straight to its canonical cache path, and the
  cache gate was presence-only — so a process killed mid-download left a
  partial file under the name a later run reports as `cached`, returns,
  and then breaks on (`[mask] rasterization failed`). Recovery was
  manual deletion of the specific `<year>_<hash>.nc`. Cache entries are
  now written to a unique temp file in the same directory and renamed
  into place only after a complete, validated write, so a killed fetch
  leaves at most a `*.tmp*` orphan that the gate can never serve. Latent
  on small AOIs, which is why it surfaced on long large-floodplain runs.
- **The same fix lands on
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)**,
  which had the identical defect and was not named in the issue. It is
  the more expensive path to lose — a cube entry is a multi-hour
  Sentinel-2 stream rather than a small annual raster.
- **A second instance of the same bug, which the issue did not name:
  `force = TRUE` destroyed a good cache.** It truncated the canonical
  file *before* writing, so an interrupted forced re-fetch lost an entry
  that had been perfectly valid — the exact situation in which someone
  reaches for `force`. There is a regression test.
- **Concurrent fetches of the same key no longer interleave.** Two
  sessions writing one canonical path previously produced a mixed file;
  a unique temp per writer makes it clean last-writer-wins.
- **Cached entries are validated before they are served.** Three damage
  shapes were measured rather than assumed, and no single cheaper check
  sees all of them: a tail-truncated or zero-byte file makes
  [`terra::rast()`](https://rspatial.github.io/terra/reference/rast.html)
  **error**; the shape in the issue’s own traceback **opens with a
  warning** and a degenerate geotransform; and a content-damaged file
  whose size is preserved **opens silently**, with correct dim/res/CRS,
  masks fine, and returns plausible-looking values (`nNA = 0`) — its
  damage is visible *only* in the warning raised during the pixel read.
  So `tryCatch(terra::rast())` alone passes the second and third, and a
  geometry check alone passes the third. A failing entry is re-fetched
  with a warning naming the reason, never an abort telling the user to
  delete a file by hand.
- Two limits of that check are deliberate and documented at the call
  sites, so they are not later “tightened” by someone reading them as
  oversights. The open check catches **errors only**, never the
  multidim-API warning — that is a capability message, and failing on it
  would refuse healthy `.nc` entries across the whole cache. The
  empty-CRS check fires only **in conjunction with** an identity
  geotransform, since an absent CRS alone is not proof of damage and the
  cost of a false refusal is a silent, permanent re-download.
- **The read probe samples rather than proves, and says so.** It reads
  one row, so interior damage that leaves the container walkable can
  pass it; the guarantee against partial entries is the atomic write. On
  the cube path the probe is free and strictly stronger:
  `cube_check_nonempty()` already scans every pixel via
  [`terra::global()`](https://rspatial.github.io/terra/reference/global.html),
  so wrapping that existing call in a warning handler gives a whole-file
  check at no added cost. Validity is checked *before* it, so a
  truncated file that happens to read all-`NA` is reported as corrupt
  rather than as “your AOI does not overlap the collection”.
- **No cache-format break.** Unlike
  [\#51](https://github.com/NewGraphEnvironment/drift/issues/51),
  nothing needs invalidating: all 168 entries in a real cache were
  checked and none is corrupt. The same 168 (123 `.nc`, 45 `.tif`) are
  the false-refusal control for the new validator — it rejects none of
  them, at 41 ms each.
- [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  no longer strands per-tile files when `mosaic_tiles()` errors, and the
  GDAL PAM sidecar is carried across the rename
  ([`terra::writeRaster()`](https://rspatial.github.io/terra/reference/writeRaster.html)
  emits one writing `.nc`, though not `.tif`), so it cannot be left
  behind under a dead temp name.

## drift 0.10.0

- **Bug fix:
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  read only the first page of STAC items, so a wide AOI could silently
  build a raster from a truncated item set
  ([\#51](https://github.com/NewGraphEnvironment/drift/issues/51)).** It
  called
  [`rstac::get_request()`](https://brazil-data-cube.github.io/rstac/reference/request.html)
  with no
  [`rstac::items_fetch()`](https://brazil-data-cube.github.io/rstac/reference/items_functions.html),
  and the partial item collection went straight to
  [`gdalcubes::stac_image_collection()`](https://rdrr.io/pkg/gdalcubes/man/stac_image_collection.html)
  — no error, no warning, a plausible-looking raster with missing tiles
  over whatever the missing items covered. Because it depends on AOI
  size it would have appeared first on the largest, most-published area
  rather than in a test. The sibling
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  has always paged correctly;
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  was simply never brought across. Fetch now pages to exhaustion through
  a new internal `stac_items_paged()`, signing **after** paging (signing
  first leaves every item from page 2 onward unsigned).
- **The obvious guard for this is wrong, and drift deliberately does not
  implement it.** Erroring when a `rel="next"` link survives — what the
  issue proposed — would abort every *correctly*-paged fetch:
  `rstac:::items_fetch.doc_items` mutates only `items$features` and
  never `items$links`, so a fully-paged collection still carries page
  1’s [`next`](https://rdrr.io/r/base/Control.html). Measured on the
  packaged AOI (`io-lulc-annual-v02`, 14 items ground truth): at
  `limit=1` and `limit=3` the fetch returns the complete 14 items
  **and** still reports a [`next`](https://rdrr.io/r/base/Control.html)
  link, while at `limit=NULL` and `limit=500` it returns 14 with none.
  The link is stale, so it is now stripped before
  `attr(result, "stac_items")` reaches callers — otherwise anyone
  re-running `items_fetch()` on that attribute re-fetches pages 2..N
  into an already-complete feature list and silently duplicates them.
  Recorded in `inst/notes/gdalcubes-pc-gotchas.md` so it is not
  re-litigated.
- The strip matches [`next`](https://rdrr.io/r/base/Control.html)
  **exactly**, as `rstac` does, and a case-variant is deliberately
  **kept** rather than removed. `rstac:::items_next.doc_items` selects
  with `links(items, rel == "next")`, which is case-sensitive (measured:
  [`next`](https://rdrr.io/r/base/Control.html) matches, `NEXT` and
  `Next` do not). So a `NEXT` link is inert to `items_fetch()` and
  cannot cause the duplicate it would otherwise be stripped to prevent —
  what it means instead is that rstac *could not follow it and stopped
  after page one*, which is the very truncation this release fixes. On
  Planetary Computer nothing else can detect that (`items_matched()` is
  NULL and duplicate ids cannot see a short read), so that link is the
  last local evidence.
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  now warns and leaves it attached. An earlier draft of this fix
  stripped it case-insensitively, which would have deleted the evidence.
- An item with no usable `id` is now its own error rather than being
  folded into the duplicate check, which used to report two id-less
  items as `duplicate item id: NA — pages overlapped` — naming a cause
  that had not occurred.
- Two completeness checks with deliberately different reach: **duplicate
  item ids** (never skipped, and the only signal available on Planetary
  Computer —
  [`gdalcubes::stac_image_collection()`](https://rdrr.io/pkg/gdalcubes/man/stac_image_collection.html)
  drops duplicates behind a debug-only message, so nothing downstream
  would ever report them), and **`items_matched()` against the item
  count** (fires only where the API reports a total; PC sends no
  `numberMatched`, so this never executes there and is fixtured in the
  tests rather than left as dead code). `limit = 500` is a round-trip
  reducer, not the fix — `items_fetch()` is.
- **Cache-format break: existing
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  caches rebuild once.** The paging fix changes no cache-key parameter,
  so without a deliberate break a raster written from a truncated item
  set would keep being served by the
  [`file.exists()`](https://rdrr.io/r/base/files.html) short-circuit —
  and the wide-AOI users the bug hit hardest would get no fix at all on
  upgrade, silently and permanently under `force = FALSE`.
  `stac_cache_key()` therefore gains a constant salt and the frozen-hash
  guardian moves from `79f67b7b9dae` to `2264b5dbef6e`. The cost is a
  one-time re-fetch of small annual land-cover rasters, not the
  multi-hour Sentinel-2 stream — which is why
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  chose a read-path check for its analogous problem and fetch can afford
  a key break.
  **[`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  caches were unaffected *by
  [\#51](https://github.com/NewGraphEnvironment/drift/issues/51)*** —
  `stac_cube_cache_key()` is a separate function and was untouched
  there. **Superseded by
  [\#48](https://github.com/NewGraphEnvironment/drift/issues/48) in
  0.12.0**, which re-keys both functions and moves every entry under a
  `v2/` scheme directory; cube caches are invalidated too.
- [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  now attaches `attr(, "cache_key")` alongside the existing
  `attr(, "stac_items")`, so a caller can record which cache entry
  served a fetch. It is **per call, not per year** — cached files are
  named `<year>_<cache_key>`, so one key covers every year the call
  returned.
- Note for anyone reading warnings after upgrading:
  [`gdalcubes::stac_image_collection()`](https://rdrr.io/pkg/gdalcubes/man/stac_image_collection.html)
  skips an unreadable item with a warning, so a now-complete (larger)
  item set can surface warnings that the truncated set never reached.
  That is the paging working, not a regression introduced here.

## drift 0.9.0

- [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  gains `parallel` (default `NULL` = `min(4, cores - 1)`), and is
  roughly **2× faster out of the box** on a machine with 5 or more cores
  as a result
  ([\#47](https://github.com/NewGraphEnvironment/drift/issues/47); the
  auto value is `min(4, cores - 1)`, so a 1- or 2-core machine resolves
  to 1 and is unchanged). drift never called
  [`gdalcubes::gdalcubes_options()`](https://rdrr.io/pkg/gdalcubes/man/gdalcubes_options.html)
  anywhere, so every cube read has run single-threaded since the
  function existed — not a considered choice, just the consequence of
  never setting it. (gdalcubes also derives its default chunk size
  *from* `parallel`, so raising it changes chunking as a side effect —
  but note that on this AOI finer chunking measured **worse** in
  isolation, 343.7 s / 693 requests at 128 px against 236.9 s / 462 at
  the default, so the speedup here is attributable to concurrency, not
  to chunk size.) Measured on the packaged AOI (4-month monthly kNDVI):
  236.8 s at `parallel = 1`, **115.8 s at 4**, **96.0 s at 8**. Output
  is byte-identical at every setting — same grid, correlation 1.000, max
  absolute difference 0, same 49,244 non-NA cells — so `parallel` is a
  pure cost knob and deliberately does **not** enter the cache key;
  existing cached cubes stay valid. Capped at 4 by default rather than
  the full core count because each gdalcubes worker holds chunks in
  memory and drift has hit OOM on large AOIs before
  ([\#27](https://github.com/NewGraphEnvironment/drift/issues/27),
  [\#34](https://github.com/NewGraphEnvironment/drift/issues/34)); raise
  it where there is headroom, or pass `1` for the previous behaviour.
- **[`gdalcubes::filter_geom()`](https://rdrr.io/pkg/gdalcubes/man/filter_geom.html)
  was evaluated and rejected on measurement
  ([\#47](https://github.com/NewGraphEnvironment/drift/issues/47),
  [\#38](https://github.com/NewGraphEnvironment/drift/issues/38)).** The
  segfault that originally blocked it is fixed in
  `NewGraphEnvironment/gdalcubes@newgraph`, so it was available to
  adopt; it is simply not worth it. It skips whole *chunks* rather than
  pixels, and gdalcubes clamps a chunk edge to `[64, 1024]` px — coarse
  enough to skip nothing at the default (462 range requests and 236.9 s,
  against the bbox baseline’s 462 / 236.8 s), and fine enough to break
  alignment with the COGs’ 512×512 blocks when forced down (693 requests
  / 348.2 s at 64 px — 1.5× the requests and 47% slower, to skip 26.7%
  of the ground). The AOI/bbox area ratio the proposal rested on is the
  wrong bound: the read is chunk-granular and the cost is
  COG-block-granular. drift therefore keeps its
  [`terra::mask()`](https://rspatial.github.io/terra/reference/mask.html)
  clip, and the reasoning is recorded in
  `inst/notes/gdalcubes-pc-gotchas.md` so it is not re-litigated.
- **Bug fix: the end-to-end cube test passed on an all-`NA` cube.** Its
  coverage assertion was `mean(rowSums(!is.na(values)) == 0) > 0.5`,
  which an entirely empty cube satisfies with `1.0` — as it did the
  layer-count, time and cache-file assertions. Every assertion in
  drift’s only network cube test was satisfied by a cube containing no
  data, i.e. by exactly the gdalcubes failure mode
  [\#32](https://github.com/NewGraphEnvironment/drift/issues/32) exists
  to prevent. Replaced with in-polygon non-`NA`, per-layer non-`NA`, and
  outside-`NA` assertions, with the in-polygon cell set derived from the
  AOI geometry rather than from the cube’s own values.
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  also now aborts, before writing anything to the cache, when the
  assembled cube has no data on **any** layer (deliberately the whole
  stack, not the first layer: an individual layer being empty is
  documented `months` behaviour, so a first-layer check would abort the
  package’s own `months = 6:9` example after the full COG stream) — so
  an empty cube can no longer be cached and served for every later call.
- **Documentation fix: `stac_cube_clip()` documented the wrong clip
  rule.** It claimed cells whose *centre* falls outside the polygon
  become `NA`;
  [`terra::mask()`](https://rspatial.github.io/terra/reference/mask.html)
  defaults to `touches = TRUE`, so the clip is inclusive at the boundary
  by up to one cell. The difference is 15.5% of the analysed footprint
  on the packaged AOI, which matters to anyone reasoning about boundary
  hectares. The rule is now pinned by a test using an irregular polygon
  — the existing test could not catch it, because its polygon is
  axis-aligned on a cell boundary where both rules agree.
- [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)’s
  `tile_size` documentation now carries its measured cost: at 640 m on
  the packaged AOI it is **the slowest option** (1263.6 s / 3213
  requests against an untiled 236.8 s / 462), because every tile
  rebuilds the image collection and reopens the COGs. Prefer `parallel`
  for speed; reach for `tile_size` only when peak memory rather than
  wall clock is the constraint.

## drift 0.8.0

- [`dft_transition_attribute()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_attribute.md)
  tags change patches from
  [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  with columns from any overlay polygon layer — fire perimeters,
  cutblocks, roads, tenures — so a driver can separate mapped
  transitions by cause without hand-rolling spatial joins
  ([\#42](https://github.com/NewGraphEnvironment/drift/issues/42)).
  Deliberately generic: drift carries no BC/domain knowledge; the caller
  supplies the overlay, the columns to carry (`cols`), and optionally a
  numeric temporal filter (`time_col` + `time_interval`, bounds
  inclusive) that keeps only overlay features whose time falls within
  the transition interval — a 2022 fire attributes a 2017→2023 loss, a
  2012 fire does not. Two assignment modes for a patch that straddles
  multiple overlay features: `match_mode = "all"` (left join, one row
  per match) or `"largest"` (one row per patch by greatest overlap
  area). Largest-overlap assignment is intersection-based, so combining
  it with a custom `predicate` is an error rather than a silent
  mis-attribution; the overlay is reprojected to the patch CRS and run
  through
  [`st_make_valid()`](https://r-spatial.github.io/sf/reference/valid.html)
  automatically, since real-world disturbance perimeters routinely fail
  validity checks.

## drift 0.7.0

- [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  gains `tile_size` (default `NULL`), the continuous-path twin of
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)’s
  `tile_size`
  ([\#36](https://github.com/NewGraphEnvironment/drift/issues/36)): an
  opt-in that bounds the STAC *read* to the AOI footprint
  ([\#38](https://github.com/NewGraphEnvironment/drift/issues/38)). By
  default one gdalcubes cube is streamed over the whole AOI bounding
  box, so the COG streaming — the dominant cost (~10-30 min for a
  multi-year monthly Sentinel-2 fetch) — scales with the bbox, not the
  AOI; for a thin, diagonal floodplain corridor the bbox is largely
  empty. When `tile_size` (CRS units — metres for the default UTM CRS)
  is set, the bbox is split into a `res`-aligned grid and only tiles
  that intersect the AOI polygon are streamed — each carrying the full
  SCL mask, spectral index, and 2022 baseline-offset split — then
  mosaicked with
  [`terra::merge()`](https://rspatial.github.io/terra/reference/merge.html),
  so a corridor reads close to its footprint. This is the
  `filter_geom`-independent path (the polygon clip that would do this
  in-cube segfaults on the pinned gdalcubes build). The cube always
  caches a `.tif` and a tiled read keys distinctly, so untiled caches
  are untouched and `tile_size = NULL` is byte-for-byte the previous
  behavior. Because the cube resamples with bilinear, a tiled cube
  faithfully reproduces the untiled cube (bilinear-aligned correlation
  ~0.997, per-layer means within ~1e-3, no tile seams) but lands on a
  bbox-anchored grid that is sub-pixel-offset from — not pixel-identical
  to — the untiled cube; the offset is immaterial to the per-pixel
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
  /
  [`dft_rast_trend()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_trend.md)
  reducers. With `tile_size` set, `clip = FALSE` returns the
  AOI-intersecting tile union (with `NA` where empty tiles were
  skipped), not a gap-free bounding box.

## drift 0.6.0

- [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  gains `tile_size` (default `NULL`), an opt-in that bounds the STAC
  download to the AOI footprint
  ([\#36](https://github.com/NewGraphEnvironment/drift/issues/36)). By
  default a single cube is streamed over the whole AOI bounding box, so
  for a thin, diagonal floodplain corridor (measured ~10% of the bbox
  inside the polygon) roughly 10× more pixels are downloaded than the
  AOI needs. When `tile_size` (CRS units — metres for the default UTM
  CRS) is set, the bbox is split into a `res`-aligned grid and only
  tiles that intersect the AOI polygon are streamed, then mosaicked with
  [`terra::merge()`](https://rspatial.github.io/terra/reference/merge.html)
  — so a corridor fetches close to its footprint. Smaller tiles waste
  less bbox but cost more per-tile round trips (no auto-tuning). This is
  the `filter_geom`-independent path (the polygon-clip that would do
  this in the cube pipeline segfaults on the pinned gdalcubes build).
  Tiled fetches cache a terra GeoTIFF (`.tif`) rather than a gdalcubes
  NetCDF (`.nc`) and key distinctly, so existing untiled caches are
  untouched; `tile_size = NULL` is byte-for-byte the previous behavior.
  The same read residual on the continuous
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  path is tracked as
  [\#38](https://github.com/NewGraphEnvironment/drift/issues/38).

## drift 0.5.0

- [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  gains `clip` (default `TRUE`), restoring AOI-polygon-tight output
  ([\#32](https://github.com/NewGraphEnvironment/drift/issues/32)). The
  assembled index stack is masked to the AOI polygon with
  [`terra::mask()`](https://rspatial.github.io/terra/reference/mask.html)
  — client-side, because
  [`gdalcubes::filter_geom()`](https://rdrr.io/pkg/gdalcubes/man/filter_geom.html)
  segfaults / returns an all-NA cube on the pinned build — so cells
  outside the polygon are `NA` on every layer. The reduced raster from
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)/[`dft_rast_trend()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_trend.md)
  is now polygon-tight with no caller-side mask, and those reducers skip
  out-of-AOI pixels via their valid-observation gate. `clip = FALSE`
  keeps the full bounding box. This is an output change for callers that
  relied on the bounding-box extent, and the clip is folded into the
  cube cache key, so existing cached cubes rebuild once. Note the clip
  affects the *output* only — the full bbox of COGs is still streamed
  either way (the AOI cannot be pushed into the read on the pinned
  gdalcubes build).

## drift 0.4.0

- Categorical land-cover change detection no longer exhausts memory on
  large-floodplain AOIs
  ([\#34](https://github.com/NewGraphEnvironment/drift/issues/34),
  [\#28](https://github.com/NewGraphEnvironment/drift/issues/28)).
  [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  was rewritten to stream entirely through `terra` — transitions are
  encoded and filtered with raster arithmetic,
  [`terra::subst()`](https://rspatial.github.io/terra/reference/subst.html),
  [`patches()`](https://rspatial.github.io/terra/reference/patches.html),
  and a single
  [`terra::freq()`](https://rspatial.github.io/terra/reference/freq.html),
  with no
  [`terra::values()`](https://rspatial.github.io/terra/reference/values.html)
  pull and no full-grid R vectors — so peak memory scales with the
  number of distinct transitions and patches, not the grid size
  (producer-only peak at 16M cells dropped from 2.66 GB to 1.63 GB).
  Output is byte-identical to the previous version, verified by a golden
  snapshot across the full parameter matrix.
- [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  gains `changes_only` (default `FALSE`): when `TRUE`, stable
  (`from == to`) transitions are dropped at the raster level before
  polygonizing, so
  [`terra::as.polygons()`](https://rspatial.github.io/terra/reference/as.polygons.html)
  only builds geometry for actual change patches. On a fragmented
  floodplain — where the stable mosaic is most of the grid and
  polygonization dominates memory — this roughly halves peak use (a
  9M-cell, 415k-patch benchmark went from 3.83 GB to 1.71 GB). The
  result equals the default output filtered to change patches. When
  `patch_area_min` is set, small patches are also dropped before
  polygonizing, with identical output.
- `patch_id` in
  [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  is numbered over the surviving patches when filtering drops any, and
  an empty result now carries the zone column so per-zone results bind
  cleanly.

## drift 0.3.0

- Continuous index-trajectory change detection for floodplain reaches
  ([\#30](https://github.com/NewGraphEnvironment/drift/issues/30)). A
  new fetch-and-reduce pipeline complements the categorical
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  path.
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  builds a cloud-masked monthly spectral-index stack from Sentinel-2
  (via a new `"sentinel-2-l2a"` source);
  [`dft_rast_break()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_break.md)
  reduces it per pixel with
  [`bfast::bfastmonitor()`](https://rdrr.io/pkg/bfast/man/bfastmonitor.html)
  into a two-band raster of *abrupt* break date and magnitude; and
  [`dft_rast_trend()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_trend.md)
  reduces it to a per-pixel *gradual* trend — a robust Theil-Sen slope
  (index change per year) with Mann-Kendall significance — for
  degradation/recovery monitoring the annual labels cannot show.
  Together they let a continuous trajectory validate categorical
  land-cover transitions (confirming which mapped losses carry a real
  spectral decline) and detect gradual change. See the “Trajectories as
  a Check on Land-Cover Change” vignette.
- [`dft_index_expr()`](https://newgraphenvironment.github.io/drift/reference/dft_index_expr.md)
  and
  [`dft_index_table()`](https://newgraphenvironment.github.io/drift/reference/dft_index_table.md)
  add a table-driven spectral-index registry (NDVI, kNDVI, NDMI) whose
  formulas are written over band *roles*, so one index resolves against
  any reflectance source; the reflectance scale/offset is folded into
  each expression.
- Sentinel-2 handling is correctness-focused:
  [`dft_stac_cube()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_cube.md)
  masks cloud/shadow/cirrus/snow, restricts to caller-chosen calendar
  `months` (e.g. the growing season) to sharpen the signal and cut
  scenes streamed, and — because the +1000 DN reflectance offset only
  applies from processing baseline 04.00 (2022-01-25) — splits items at
  that boundary and corrects each side, so a multi-year series carries
  no artificial index step at 2022.
- [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  gains a role-based schema for reflectance cube sources (band roles,
  mask classes, scale/offset, offset boundary), leaving the categorical
  `io-lulc`/`esa-worldcover` sources unchanged. `bfast` added to
  Suggests.
- Known limitation tracked as a follow-up: the cube spans the AOI
  bounding box rather than the polygon (a gdalcubes `filter_geom`
  limitation,
  [\#32](https://github.com/NewGraphEnvironment/drift/issues/32));
  labelling breaks with from/to land-cover classes is
  [\#31](https://github.com/NewGraphEnvironment/drift/issues/31).

## drift 0.2.4

- [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  no longer exhausts memory on large-extent rasters
  ([\#27](https://github.com/NewGraphEnvironment/drift/issues/27)). The
  per-class loop allocated full-grid vectors per class and per patch —
  ncell × n_patches churn that OOM-killed a 102.6M-cell, 56-class
  floodplain. Replaced by a single `terra::patches(values = TRUE)` pass
  plus a sparse patch-to-label map. Output is identical (verified
  patch-by-patch against the old implementation); only `patch_id`
  numbering / row order changes, to raster scan order. Benchmark at 24M
  cells: 1.9 s for a 4,799-patch raster; the old code took 122 s on a
  milder 1,232-patch raster of the same size.
- terra dependency floored at `>= 1.8-10`: earlier versions had an
  edge-wraparound bug in `patches(values = TRUE)` that silently merged
  patches touching opposite raster edges.

## drift 0.2.3

- Fix silent cross-AOI cache collision in
  [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  ([\#25](https://github.com/NewGraphEnvironment/drift/issues/25)).
  Cache files were keyed by source + year only, so fetching a second AOI
  with the same source/year silently returned the first AOI’s raster
  masked to the second AOI’s extent. Cache filenames now include a hash
  of the AOI geometry and all fetch-affecting parameters (`res`, `crs`,
  `dt`, `aggregation`, `resampling`, `stac_url`, `collection`, `asset`).
  Existing caches re-fetch on first use after upgrading;
  [`dft_cache_clear()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_clear.md)
  reclaims the orphaned old-format files.
- `force = TRUE` now overwrites the cached file instead of erroring with
  “File already exists”
  ([\#25](https://github.com/NewGraphEnvironment/drift/issues/25)).

## drift 0.2.2

- Startup quote pool expanded to 113. Adds 52 domain-expert quotes from
  11 voices across floodplain/river process (David Montgomery, Ellen
  Wohl), Indigenous stewardship (Robin Wall Kimmerer, Kyle Whyte, Nancy
  Turner, Jeannette Armstrong), ecosystem valuation (Kai Chan), Canadian
  public voices (David Suzuki, Wade Davis), and legacy conservation
  (Aldo Leopold, Wendell Berry).
- Tim Beechie was on the target list but yielded zero — no public
  interview / podcast / documentary footprint. Process-paper voice only.
- Same rigor as v0.2.1: parallel research agents, independent fact-check
  pass (3 dropped for misattribution or text drift, 2 fixed from
  fact-check flags).

## drift 0.2.1

- Startup quote ritual:
  [`library(drift)`](https://github.com/NewGraphEnvironment/drift)
  prints a random fact-checked quote from 15 hip-hop artists on attach.
  Italic quote, grey attribution, clickable blue `source` hyperlink to
  the primary-source interview. Suppress via
  `options(drift.quote_show_source = FALSE)`.
- Curated via the soul `/quotes-enable` skill using multi-agent
  research + independent primary-source fact-check. 61 entries. See
  `data-raw/quotes_build.R` for full provenance.
- `cli` added to Imports for OSC 8 hyperlinks and styling in `R/zzz.R`.

## drift 0.2.0

- [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  — add `patch_area_min` parameter to filter small connected patches of
  changed pixels; return `$removed` raster for visual QA of filtered
  patches; add `from_class`/`to_class` filters
- [`dft_transition_vectors()`](https://newgraphenvironment.github.io/drift/reference/dft_transition_vectors.md)
  — vectorize transition raster into sf polygons with per-patch area,
  transition labels, and optional zone attribution
- [`dft_rast_consensus()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_consensus.md)
  — per-pixel mode across classified rasters for temporal noise
  filtering; optional confidence layer
- [`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md)
  — new `transition` parameter overlays transition layers as checkboxes;
  Google Satellite and Esri Satellite basemaps; custom tile URL support
- `dft_check_crs()` — internal helper that errors on geographic CRS
  input; wired into
  [`dft_rast_transition()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_transition.md)
  and
  [`dft_rast_summarize()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_summarize.md)
- Vignette: transition detection, tree loss filtering, patch area
  filtering with comparison table, interactive map with transition
  overlays

## drift 0.1.0

Initial public release.

- [`dft_stac_fetch()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_fetch.md)
  — fetch classified rasters from STAC catalogs via gdalcubes
- [`dft_rast_classify()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_classify.md)
  — apply class labels, colors, and optional remap to SpatRasters
- [`dft_rast_summarize()`](https://newgraphenvironment.github.io/drift/reference/dft_rast_summarize.md)
  — compute area by class and year with unit conversion
- [`dft_map_interactive()`](https://newgraphenvironment.github.io/drift/reference/dft_map_interactive.md)
  — interactive leaflet map with layer toggle, legend, fullscreen, and
  titiler COG support
- [`dft_class_table()`](https://newgraphenvironment.github.io/drift/reference/dft_class_table.md)
  — shipped class tables for IO LULC and ESA WorldCover
- [`dft_stac_config()`](https://newgraphenvironment.github.io/drift/reference/dft_stac_config.md)
  — STAC endpoint registry
- Cache management:
  [`dft_cache_path()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_path.md),
  [`dft_cache_info()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_info.md),
  [`dft_cache_clear()`](https://newgraphenvironment.github.io/drift/reference/dft_cache_clear.md)
- Vignette: Neexdzii Kwa floodplain land cover change 2017-2023

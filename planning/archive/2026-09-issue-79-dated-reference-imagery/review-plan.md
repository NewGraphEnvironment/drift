# Plan review — #79 (Plan agent, 2026-09-28)

This is the reviewer's report, condensed. Each finding carries the verdict reached after probing it. The reviewer ran read-only while Phase 2 was still uncommitted.

## Blockers

| # | Finding | Verdict |
|---|---|---|
| B1 | leafem ignores `domain` unless `quantiles = NULL`, and its defaults are `r=3,g=2,b=1`. `domain` is one range for all bands, so false-colour NIR saturates. | The draft already passes `r=1,g=2,b=3, quantiles=NULL`. **Real on the stretch:** change it to per-band quantiles pooled across composites, so years stay comparable, clamped in terra and passed with `domain = c(0, 1)`. |
| B2 | In a composite window, `cover(pre, post)` at the 2022-01-25 offset boundary is not a median. It applies only when a window contains Jan 2022 and has items on both sides. | **Real.** The composite refuses that case with a named error. It is pre-existing for the cube's Jan 2022 layer; note it in the gotchas file. |
| B3a | The network e2e lists `file.path(cache, "sentinel-2-l2a")`, but the cache has been under `v2/` since #48 (lines 405, 444). | **Real.** It was found independently in the #80 run. Fixed on the #80 branch and on this one. |
| B3b/c | A same-key run is a cache hit, and the baseline must come from HEAD. | **Already met.** The identity run used fresh caches, main-tree code and the same gdalcubes 0.7.5 build: identical values, max diff 0. |
| B3d | Nothing pins how `dft_stac_cube()` *calls* the key (argument order at the call site). The frozen test calls the function directly, and the gate tests mock it. | **Real.** Add a characterization test: seed at the real key, stub rstac, and assert the file is served. |

## Gaps

| # | Finding | Verdict |
|---|---|---|
| G1 | Chips via buffered points and `tile_size` produce a floodplain-sized, mostly-NA mosaic (merge over the tile union). One key covers all the points, so adding a point invalidates everything. | **Real, and it breaks the approved chip path.** Resolution, which stays within the plan's intent: one composite per point. The documented pattern is a loop over buffered points, one small cached entry per point, which also matches floodplains#93's "map zoomed to the point". The tile-count claim is dropped. |
| G2 | Composite key missing params | The draft already covers aggregation, resampling, url, collection, offset_before and a `"composite"` salt, with order tests. |
| G3 | One empty or clouded year aborts a multi-year call | **Real.** Warn and drop that year. Classed conditions replace message matching. Abort only if every year is empty. |
| G4 | COG write options, NoData, round trip | Pass `COMPRESS=DEFLATE`, `PREDICTOR=YES`, `OVERVIEW_RESAMPLING=AVERAGE` and `BLOCKSIZE=512`. The e2e asserts `LAYOUT=COG` and a NoData value. Make the cache-read warning label generic. |
| G5 | Multi-variable NetCDF read-back order is unverified | **Real risk:** renaming by position would mislabel silently. Assert that terra's layer names match the bands before renaming. |
| G6 | `x = NULL` touch points; rgb/x name clash; en dash in source | Touch points are handled. Add the clash check. Keep the en dash as `–` in code, and write "Jun-Jul" in roxygen. |
| G7 | Reuse `scale_token()` (done). Share the titiler URL base. `stac_cube_items` lacks the #51 paging safeguards. | Share the titiler URL base. The paging safeguards are a behaviour change for the cube and become a follow-up issue. |
| G8 | `clip = TRUE` removes the context a reviewer needs | **Agree:** the composite defaults to `clip = FALSE`. |
| G9 | A window that wraps the year (Dec–Feb) cannot be expressed | Document it; the label names the months actually composited. |

## Ordering / assumptions / scope

- A1: verified `nt == 1` for spans equal to dt. A span that is not a multiple of dt extends `t1`, so dt must equal the span, which it does by construction. The layer-count guard is in place.
- A2: a date-only STAC end bound may exclude the last day's ~19:00Z scenes. **Probe it**; it affects the cube too.
- A3: repeat `rescale=` per band. This is done, but was not verified against a live titiler; none is configured.
- A4: `image_mask(bits=)` exists, which answers part of the HLS spike.
- A6: the SCL mask may be read bilinear. Pre-existing; add to the gotchas note.
- A7: record temp disk alongside RSS in the scale test.
- S1: **Real, pre-existing, and it blocks the overlay.** Classified and transition layers are projected to 4326 and then passed with `project = FALSE`. leaflet stretches them linearly into Mercator bounds, so at floodplain extent they do not register with leafem's 3857 RGB. Fix: project to EPSG:3857.
- S2 / AC1: there is no titiler instance and no upload step. The COG path is tested offline by URL shape only; the PR says so.

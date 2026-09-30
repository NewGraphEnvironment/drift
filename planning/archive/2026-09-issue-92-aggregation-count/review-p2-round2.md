# Code-check review: #92 Phase 2, round 2

Snapshot: `scratchpad/p2snap`, gdalcubes 0.7.5. Work copy: `scratchpad/p2r2/mut`, restored and
checked with `cmp` afterwards. On the unmutated copy the composite test file passes:
`[ FAIL 0 | SKIP 2 | PASS 92 ]`.

## Clean

No bug, security or fragility finding. The round-1 fix discriminates, and the rest of the diff
held up under probing.

## The fix: does the pixel_fn assertion discriminate?

I swapped the count branch of `pixel_fn` (R/dft_stac_composite.R:186) for each variant below and
ran the test file:

| pixel_fn mutation | result |
|---|---|
| identity (`cube`, a 31-step passthrough) | red (2 fail) |
| `reduce_time(sum(B04))`, which is reflectance-scale | red |
| `count(...)` with `names = band_assets` | red |
| scale-then-count (`apply_pixel(B04*1e-4-0.1)` then `count`) | green, but equivalent: scaling does not change which cells are NaN, so the count is the same |
| `count(SCL)` | green, but equivalent: `image_mask` NaN-masks every band, the mask band included, so it gives the same count |

Both survivors produce the same output as the real code, so they are not defects the test ought
to catch. Round 1 already accepted the reflectance `apply_pixel` closure as a red mutation.

- **Counting items rather than days** cannot happen inside `pixel_fn`. Same-day items are
  collapsed by the `cube_view` (P1D, `"first"`) before `pixel_fn` sees the cube. So that property
  belongs to the view, and it is pinned by `seen$dt == "P1D"` and `seen$aggregation == "first"`,
  plus the separate fixture test with duplicate same-day items. The pixel_fn fixture having one
  item per day does not weaken it.
- **Single-step passthrough:** the fixture view runs 07-01..07-31 at P1D, which is 31 steps, so
  it cannot reach it. I measured the passthrough claim in the docstring and the notes: a one-day
  view (`t0 = t1`) returns `500` (the input), and a two-day view returns `1`. A composite window
  is always at least one whole month, so production never reaches it.

## Probed, not covered by round 1

- **Swath-edge nodata as a "clear day".** SCL 0 (NO_DATA) is not in `mask_values`, and
  `stac_image_collection()` sets band `nodata = ""`. So the only guard is the COG's own
  NoData. Fixture probe: when the B04 file declares `NoData=0`, the 0 pixels are not counted
  (1 vs 2). When the file declares no NoData, they are counted, which would inflate the count.
  Checked live: a PC `sentinel-2-l2a` item (S2A_MSIL2A_20210710T192911_R142_T09UXA) has
  `NoData Value=0` on both B04 and SCL. So production is safe. The test fixture declares
  `"nodata": 0` in its format JSON instead of in the file, and the effect is the same.
- **Case:** `aggregation_check()` returns lower case, so `"COUNT"` → `is_count` TRUE.
- **Claims in the notes:** #96 exists and is the resampling fallback.
- **Cache-hit path:** a count file is not passed through `count_zero_na()` again, and does not
  need to be (NA is stored as NoData 65535).

## Notes (not findings)

- The docstring of `count_zero_na()` justifies NA-not-0 by saying that "a failed chunk read is
  NaN". That is true when every time chunk of a spatial block fails. A **partial** failure
  (#87: an expired token or an HTTP error on some days' chunks, reported only on stderr) is
  reduced as missing days and published as a plausible undercount (for example 5 instead of 7).
  The median composite has the same exposure (a plausible wrong median), so this is the
  existing #87 class and not new with this diff. The Phase 3 docs could state that the count is
  a lower bound under read failure.
- `stac_cube_items()` still prints "offset split at …: N pre / M post" on a straddling count
  window before `is_pre` is reset, so the message describes a split that does not happen. This
  is cosmetic.

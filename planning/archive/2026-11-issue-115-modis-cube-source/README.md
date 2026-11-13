## Outcome

`dft_stac_cube()` and `dft_stac_composite()` gained a second cube source, MODIS MOD13Q1 v6.1 (`modis-13Q1-061`, Planetary Computer, 250 m 16-day composites from 2000-02-18). `evi` joined the index registry, computed from the reflectance roles for both sources: the owner chose this at the gate over reading MODIS's published NDVI/EVI assets. Four facts about the collection shaped the read path, all measured live:

- items carry `datetime: null` with a 16-day window, so the `months` filter dropped every item until drift set the window midpoint (gdalcubes' own rule);
- there is no `eo:cloud_cover`, so a filter on it returns zero items, and drift now skips it and refuses a value;
- the asset names start with a digit, which gdalcubes' tinyexpr cannot parse, so bands are renamed to their roles before any pixel expression;
- `pixel_reliability` is `Byte` NoData 255 on disk, although STAC says `int8`.

The plan review and the first live run independently found the digit-name failure the same afternoon. The plan had no step for it; the run failed at `token 39`. Sentinel-2 defaults and cache keys are unchanged, and tests pin the values the callers hand the key builders. Filed along the way: #116, a pre-existing bug where `dft_stac_cube()` labels layers monthly whatever `dt` is. The BULK floodplain item `CLAUDE.md` pointed to has moved (`bulk_co_ff04` → `bulk_all_ff04`, with no `co_ff04` layer), which `CLAUDE.md` now records. The durable notes are in `inst/notes/gdalcubes-pc-gotchas.md`, "MODIS MOD13Q1 on Planetary Computer".

## Measurement

- **Packaged reach (Neexdzii Kwa), 2017 June–September:**
  - 18 items matched by overlap; 16 have their midpoint inside the window.
  - 4 monthly layers at 250 m, 82 cells each.
  - kNDVI 0.33–0.60, EVI 0.23–0.58.
  - 2010 NDVI 0.48–0.80 (before Sentinel-2).
  - Composite minimum reflectance: red 0.018–0.035, NIR 0.094–0.26. No fill reached it (a -1000 fill would read -0.1).
- **BULK floodplain (`co_ff04`, 104,584 vertices, queried by convex hull), MODIS kNDVI 2008–2017 with `months = 6:9`:**
  - 314 items; a 587 x 463 cube with 120 layers.
  - The 40 summer layers carry data (median 16,336 cells); the other 80 are NA by design.
  - 21.7 min wall, peak RSS 1.74 GiB (`/usr/bin/time -l`). At 250 m, memory is not the constraint; the network read is.
  - The run's 160 warnings looked like a defect at first. They were the probe's own `range()` over the empty months, confirmed on the cached cube.
- **Tests:** full suite `[ FAIL 0 | WARN 0 | SKIP 20 | PASS 1774 ]`. 19 new offline tests and one opt-in live test.
- **`/code-check branch`:** four rounds.
  - Rounds 1 and 2 were clean. Round 1 noted two points below the bar, both fixed: the role plural, and a non-UTC window offset.
  - Round 3 found one real defect, now fixed: the composite's all-skipped abort advised a cloud filter that MODIS refuses.
  - Round 4 was clean after a sweep of all 229 condition calls for assumptions only Sentinel-2 meets.

## Owed

- Note on #82 (HLS) that MODIS covers the pre-2017 gap at 250 m with no account. HLS remains the 30 m route.

Closed by: PR for #115 (branch `115-modis-vegetation-indices-mod13q1-as-a-cu`)

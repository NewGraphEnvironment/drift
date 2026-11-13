# Progress — MODIS vegetation indices (MOD13Q1) as a cube source from Planetary Computer (#115)

## Session 2026-11-13

- Plan-mode exploration — phases approved by user (index route: compute + add EVI)
- Created branch `115-modis-vegetation-indices-mod13q1-as-a-cu` off origin/main
- Scaffolded PWF baseline from issue #115 with approved phases
- Next: start Phase 1
- Phase 1: 12 new tests across four files, all red on main (2 index, 1 config, 7 cube, 2 composite); the rest of each file stays green
- Phase 2: modis-13Q1-061 config and evi row; config and index tests green
- Phase 3: stac_items_datetime(), stac_cloud_cover_resolve(), stac_index_roles_check(); res and cloud_cover_max resolved with missing() in cube and composite; the four touched test files green (125 tests)
- First live run (packaged AOI) failed `Cannot parse expression for kndvi ... error at token 39`: MODIS asset names start with a digit (review B1, which arrived minutes later with the same diagnosis from the gdalcubes source)
- Review fold-in: band_expr_names()/cube_bands_rename() (index, composite, count); offline MODIS fixture (digit-led names, -1000 and 255/3 pixels) red on the parse error then green; out-of-window window-only items dropped (mutation: removing the drop turns its test red); refusal names NULL; midpoint test off-UTC
- Live (packaged AOI, 2017-06/09): 16 items (18 before the window drop), 4 monthly layers at 250 m, 82 cells each; kndvi 0.33-0.60, evi 0.23-0.58; 2010 ndvi 0.48-0.80; composite min reflectance red 0.018-0.035, nir 0.094-0.26. Opt-in network test green (10 expectations), with the file's Sentinel-2 network tests
- BULK scale run (co_ff04 from the local floodplains copy; `bulk_co_ff04` now 403s, its successor `bulk_all_ff04` has no co_ff04 layer): MODIS kNDVI 2008-2017 months 6:9, 314 items, 587 x 463 x 120 layers (40 summer layers with data, median 16,336 cells), 21.7 min wall, peak RSS 1.74 GiB (`/usr/bin/time -l`). The run's 160 warnings were the probe's own range() over the 80 empty months, confirmed on the cached cube
- Owner, mid-run: finish #115 to an open PR, then merge it with /gh-pr-merge

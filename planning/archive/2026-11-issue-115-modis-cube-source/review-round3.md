# Code-check round 3 (#115): whole branch vs 16f6a22, mechanism sweep + composite path, docs, inst/notes

## Checklist read

- **INDEX.md**: every heading and first sentence, all four files.
- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, with `|` table rows and evidence blocks skipped: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what generators leave in it", "A wrapper's exit is not the work", "Zero-length, empty, and unset are three different things", "The probe is broken before the world is", "Written data outlives the fix", "Serialization loses meaning silently" and "One fact derived twice". I also read "A pluralisation marker takes the quantity of whatever was substituted last". The other ~30 non-mechanism headings were not read past the index.
- **code-check-r.md**: I read "Cross-function consistency for label/string normalization" and "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared". I checked these against the index only: "`$` on a list partial-matches", "`c(name = x)` keeps `x`'s own name", "`paste()` with a zero-length argument", "A `function(...)` mock hides arguments" and "as.POSIXct on character infers ONE format". The other ~115 were not read past the index.
- **code-check-spatial.md**: I read "An offset regex must be anchored to a time, or a date looks like a zone", "A reader that accepts a UTC offset may not be applying it" and "Planetary Computer STAC: a floodplain-scale read hits three limits a reach never does". I checked the gdalcubes headings (`cube_view()` defaults, `chunk_status`, NetCDF alphabetical order) against the index only. The other ~90 were not read past the index.
- **code-check-shell.md**: none. The diff has no shell, so all ~70 were not read past the index.

## The mechanism behind rounds 1 and 2

Both defects come from one assumption: the code leaned on a library's implicit rule to choose what a token meant. Two libraries, two rules:

- cli's `{?s}` takes its quantity from the last substitution.
- strptime parses a prefix and ignores the rest.

The tests passed because every fixture sat at the one value where the implicit rule and the intended rule agree. There was one missing role, so the index and the role count were both 1. Every window carried `Z`, so prefix and whole string were the same instant. This is "A fixture that cannot reach the failure mode": two rules that happen to agree on the data you have.

Where the same shape reaches in this diff, each place checked:

1. **`band_expr_names()` regex `^[A-Za-z][A-Za-z0-9_]*$`.** This is drift's restatement of tinyexpr's identifier grammar. It agrees with that grammar (letter first, then letters, digits or `_`; gdalcubes lower-cases both sides). No role name (`red`, `green`, `blue`, `nir`, `swir16`) is a tinyexpr builtin. The tests cover only all-valid (S2) and all-invalid (MODIS) sources. I reasoned through a mixed source: it renames only the invalid band, and the expression uses the same `band_expr_names()` output, so the two derivations agree. **OK.**
2. **`stac_items_within()` reads the query bounds by `substr(…, 1, 10)`.** This is a prefix read, the same family as strptime, and it drops a bound's time and offset.
   - The composite always queries `T00:00:00Z/T23:59:59Z`, so its UTC date is the bound.
   - A cube `datetime` with a non-UTC offset or a mid-day time would be compared by its local date. But that string also goes raw to `cube_view(t0, t1)`, so offset-bearing cube datetimes were never a supported path.
   - **Benign, not reported.**
3. **The month filter's `substr(item_dt, 1, 10)` and gdalcubes' placement.** Both read the midpoint string drift wrote, formatted in UTC with `Z`, so they agree by construction. gdalcubes takes `properties$datetime` before `start_datetime`. I checked this against its `stac_image_collection()` source. **OK.**
4. **The three "available roles" lists.** These are `stac_index_roles_check()`, `composite_band_assets()` and `index_resolve_expr()`, and all three are `setdiff(names(cfg$roles), "mask")` or the role map itself. **They agree.**
5. **`missing()`-based defaults** (`res`, `cloud_cover_max`). No internal caller forwards these arguments; I grepped R/, data-raw/ and vignettes/. So `missing()` sees the user's call. **OK.**
6. **`$` partial matching.** `cfg$res`, `cfg$cloud_cover` and `cfg$offset_before` have no prefix sibling in any source config. **OK.**
7. **Error-message remedies.** The remedies are text the caller will run, which is the second implicit-agreement surface. The finding below is the one place where the remedy and the new source disagree.

## Composite path (not covered in rounds 1-2)

All probes were run in a scratchpad copy, with `load_all` and the shipped `modis_fixture()`.

- **The composite `pixel_fn` on MODIS** (`band_expr_names()` + `cube_bands_rename()` + `apply_pixel`) gives red 0.05 and nir 0.30, the fixture's DN × 1e-4. Expressions: `(red * 0.0001)`, `(nir * 0.0001)`. The result is the same with the band order reversed.
- **The count path** (`composite_count_cube()` through `cube_bands_rename()`) on MODIS at P1D reads count 0..1 per band, as expected for a one-date fixture. S2 is untouched, because `B04` is valid and no rename happens.
- **`w$query` (with T-times) passed to `stac_cube_items()`.** `stac_items_within()` handles it by date, and the existing test covers the T form.
- **`composite_offset_check()` with no `offset_boundary`.** `is_pre` is all FALSE, so the check passes and the `{boundary}` message is never reached. **OK.**
- **Default `bands = c("red", "green", "blue")` on MODIS.** `composite_band_assets()` refuses `green` before any query. **OK.**

## Docs and notes against the code path

- **CLAUDE.md MODIS block, vignette section, roxygen (`Sources` section, `res`, `cloud_cover_max`, `source`), and the `inst/notes` MODIS section.** Each claim matches the path a run takes:
  - the midpoint rule, the drop rule and the explicit refusal;
  - `res` 250, and `ndvi`/`kndvi`/`evi` only;
  - the rename before `apply_pixel()`/`reduce_time()`;
  - gdalcubes skipping a window-only item without lubridate, which its source does (`stop()` inside a `tryCatch` that warns "Skipping STAC item").
  
  One small imprecision, not reported: CLAUDE.md says "an explicit `cloud_cover_max` is refused", but an explicit `NULL` is accepted.
- **The CLAUDE.md BULK move paragraph.** It contradicts the unchanged lines below it (three years, `layer = "co_ff04"`), but it says so itself. The new URLs and layer names cannot be checked offline under this round's no-network rule.

## Findings

- **[severity: fragile]** R/dft_stac_composite.R:341-347 — the "No year produced a composite" abort tells the caller to "try more `months` or a higher `cloud_cover_max`".
  - For `source = "modis-13Q1-061"`, following that remedy aborts with `drift_no_cloud_cover`, from `stac_cloud_cover_resolve()` at line 200.
  - Reproduced in a copy: with `stac_cube_items` stubbed to raise `drift_no_items`, a MODIS call ends in that message, and re-running it with `cloud_cover_max = 60` raises `drift_no_cloud_cover`.
  - The remedy was written when every cube source had `eo:cloud_cover`. This branch adds the first one that does not, so the advice is now wrong for exactly that source.
  - Fix: name `cloud_cover_max` only when `!identical(cfg$cloud_cover, FALSE)`, or for MODIS say that the mask does the screening and only more `months` helps.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

No other issues found.

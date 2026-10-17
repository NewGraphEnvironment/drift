# Review: relief basemap and fig-box removal, round 1

Diff: `git diff f28feea HEAD` (58ed8ca, fd658f5), excluding planning/. The article was rendered
from a temp copy (rc 0, 2026-10-16 21:30Z) and the context-map PNG was read.

## Findings

- **[severity: bug, figure claim]** data-raw/floodplain_change_dating.R:99 (`towns <- sf::st_filter(sf::st_transform(bcmaps::bc_cities(), 3857), around)`)
  and the figure the article draws from it at floodplain-change-dating.Rmd:231-234. The rendered map puts
  **Houston about 7 km south-east of the town**, south of the Bulkley in the hills. In fact the town
  sits on the river at the Morice confluence, at the bend where the drawn river turns east. The cause is
  the `bcmaps::bc_cities()` point. Measured against BC Geographical Names (`WHSE_BASEMAPPING.GNS_GEOGRAPHICAL_NAMES_SP`):
  Houston is offset 7.2 km (bc_cities -126.5648, 54.35525 vs GNS -126.6483, 54.39833) and Granisle 8.3 km.
  Smithers, Telkwa, Hazelton and New Hazelton are offset 0.8-1.3 km, which does not show at this scale.
  Houston is the town nearest the study area, so it is the one a reader uses to find the study area. Taking
  the points from GNS (feature types District Municipality / Village / Town) fixes it.

- **[severity: fragile, churn]** data-raw/floodplain_change_dating.R:95-98, 388-391 (`river` -> `simple(river_xy, "river", 100, ...)`).
  The WFS returns the Bulkley River segments in an order that varies from run to run, and
  `st_union()` of lines keeps each part in input order. So a warm rerun rewrites the `river` row of
  context.csv even when the river has not changed. This breaks the header's claim that a warm rerun leaves
  the committed files unchanged unless a live source changed. Measured: a fresh query gives the same 582
  parts and 1594 vertices as the committed row, and the WKT differs from the third part on
  (`(-14079683 7264974, ...)` now vs `(-14110951 7249848, ...)` committed). Shuffling the rows changes
  the WKT as well. The fix is to sort before the union (`river[order(river$LINEAR_FEATURE_ID), ]`). The
  figure itself is unaffected.

- **[severity: fragile, header]** data-raw/floodplain_change_dating.R:8-12 and 401-403. The header says that
  every call except the listed ones goes to drift's cache. The new
  `jsonlite::fromJSON(paste0(esri, svc, "/MapServer?f=json"))$copyrightText` calls are a further live
  read, and the list leaves them out ("basemap tiles" covers the tiles only). Esri's copyright text
  changes on its own: it now reads "Vantor" where it read Maxar. So relief_credit.txt can churn on a
  warm rerun that touches no tiles. Name the service metadata among the live sources.

## Checked, no issue

- **fig-box removal.** Nothing refers to it any more: no `wb_box`, `fig-box`, "figure above/below", `topo_*`
  or `WorldTopoMap` remains in the repo outside planning/. `asp`, `outside`, `draw_fp` and `areas$lab_x/lab_y`
  are still used by fig-lead and the Google links. The dropped guard (newest capture `cover_max >= 0.999`)
  protected only the overview. Each area's views keep their own per-view coverage check (`covers_view`,
  script:286-303), and the article still asserts that `wb_after` is the newest capture for every area seen.
  The Limits line ("the 2016-09-11 capture covers only part of the box") still matches captures.csv.
- **`## ---- context` is never shown.** The article calls `from_script()` for aoi, stac-item, floodplain,
  landcover, dates, composites, wayback and wayback-fetch, but not for context. The floodplain block ends at
  the `## ---- context` line, so none of the new code reaches the page.
- **Caption and legend.**
  - "ground outside the group is dimmed": visible.
  - The floodplain is blue.
  - The river is drawn in #1F4E79 on top and labelled by name. "the darker line" reads as darker than the
    floodplain blue, and the label disambiguates it.
  - The scale bar reads 0-20 km.
  - The credit text in the caption matches relief_credit.txt and the services. maptiles' `Esri.WorldGrayCanvas`
    is `Canvas/World_Light_Gray_Base`, the service the credit is read from.
- **River query.** 582 LINESTRING features, edge types 1000/1050/1200/1250 (main flow), well under the WFS
  cap. Z/M is dropped by `st_zm()` before the union. The geometry is a MULTILINESTRING of short parts that
  draws continuously.
- **Towns.**
  - bc_cities names are already in title case, so `toTitleCase(tolower())` changes none of the six.
  - The "Smithers" / "New Hazelton" lookup matches two rows, so `colMeans` works.
  - Zero towns, or a missing Smithers or New Hazelton, would break the figure. That needs a different
    frame, and bc_cities is a cached, static layer.
- **relief_bulk.tif.** 3 bands, INT1U, values 149-255, no NA, no sidecar.

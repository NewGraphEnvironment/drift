# Review: relief basemap and fig-box removal, round 2

Diff: `git diff f28feea HEAD` (58ed8ca, fd658f5, f7cb977), excluding planning/. Live probes were
read-only: bcdata queries of GNS and FWA, and Esri `?f=json`. The article was rendered from a temp
copy (rc 0, 2026-10-16) and the context-map PNG was read, including a zoomed crop around Hazelton.

## Clean

No issues found.

## Round-1 fixes checked

- **GNS FEATURE_TYPE filter is complete and correct.**
  - Province-wide, GNS holds City 52, District Municipality (1) 50, Village (1) 42, Town 14,
    Resort Municipality 1, Mountain Resort Municipality 1 and Indian Government District 1. That is
    161, BC's municipality count.
  - No `Village`, `Village (2)`, `District Municipality`, `City (1)` or `Town (1)` exists, so the
    "(1)" suffixes are the live spelling and there are no stray variants.
  - The three types left out (Whistler, Sun Peaks, Sechelt) are not in this frame.
  - In the frame (all GNS rows INTERSECTS `around_3005`, 89 Community / Locality / Indian Reserve
    names aside), the filter returns exactly six rows: Granisle, Hazelton and Telkwa (Village (1)),
    Houston and New Hazelton (District Municipality (1)), and Smithers (Town). Burns Lake is outside
    the frame. No municipality is missed, and nothing that is not a municipality is included.
- **Duplicate names / wrong positions.**
  - The six names are unique.
  - Each point is at the town: Houston -126.648, 54.398, at the Morice confluence; Granisle on
    Babine Lake; Smithers, Telkwa, Hazelton and New Hazelton in place.
  - All six fall inside the 3857 frame (`st_within(around)`), so the 3005 reprojection of the
    four-corner frame drops none of them.
  - Two names duplicate province-wide, but those are other municipal rows, not in frame.
- **The river-label lookup.** GNS spells "Smithers" and "New Hazelton" exactly, so `town_xy` has
  2 rows. On the rendered map the label sits beside the reach between Moricetown and the Hazelton
  bend, well clear of the study area.
- **Order dependence.**
  - River: the 582 segments have 582 unique LINEAR_FEATURE_IDs. A fresh query, sorted, and a
    shuffled copy sorted again give byte-identical WKT, and both equal the committed `river` row.
  - Towns: they are ordered by unique ASCII names whose order is the same in C and en_US collation.
  - relief_credit.txt: built from a fixed two-element vector.
  - The other context rows are a single union each from cached or static sources.
- **Attribution.** The live `copyrightText` of both services matches relief_credit.txt exactly
  (Hillshade's "Sources: " prefix stripped).
- **Header live-source list.** It now matches every network call that is not cached in the
  script: the STAC item and its assets, the release list, and bcdata for cutblocks, watershed
  group, river and GNS. It also covers maptiles tiles and the two `fromJSON` attribution reads,
  while bcmaps is cached. "river and town names" undersells the river, whose geometry is read live,
  not just its name, but nothing is missing from the list.
- **Inline note "bcdata cannot translate a call inside filter()".** It is accurate. Measured:
  `INTERSECTS(sf::st_transform(around, 3005))` errors with "No known SQL translation", while
  `local(...)` works. Passing the 3857 object directly returns 0 rows, so bcdata does not reproject
  for you, and the pre-transform is required, not cosmetic.
- **Figure vs caption.**
  - Floodplain blue, the darker labelled Bulkley line, the dimmed exterior, the inset and the
    0-20 km bar all render as the caption says.
  - The Hazelton and New Hazelton labels abut but do not overlap, and both are legible at full
    resolution.

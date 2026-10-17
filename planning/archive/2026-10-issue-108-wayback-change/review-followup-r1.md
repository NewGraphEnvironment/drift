## Findings

- **[severity: claim]** vignettes/articles/wayback-change.Rmd:264-270, 277 (fig-s2 caption), 295-300 — The prose and caption treat `in_harvest` as containment: "each tagged with the dated provincial harvest it falls in", "the outlines are the 55.6 ha of that inside a dated harvest", "tree loss ... inside a dated harvest", "the harvest that started in 2020 (30.5 ha)", "So much of the pale valley floor in the 2023 composite lies inside dated harvest". The repo's own note says otherwise (inst/notes/temporal-qa-disturbance.md:103 and :111): `in_harvest` is `st_intersects`, so touching is enough, and no overlap fraction is published. I measured it by intersecting the five tagged patches (clipped to the box) with the current BC consolidated cutblocks (`VEG_CONSOLIDATED_CUT_BLOCKS_SP`, HARVEST_START_YEAR_CALENDAR >= 2017):
  - Overall, only **13.9 of the 55.6 ha** lie inside any cutblock.
  - Per patch: 6964 (tagged 2023) 7.1 of 25.15 ha; 7017 (2020) 5.6 of 13.36; 7028 (2020) **0.06 of 10.5**; 7003 (2020) 1.07 of 6.58; 7026 0.04 of 0.04.
  - The "30.5 ha" (`hv_ha(2020)`) and "25.1 ha" (`hv_ha(2023)`) are the areas of patches that touch a harvest of that start year, not the area of that harvest. Only 6.8 ha and 7.1 ha respectively are inside cutblocks of that year.

  The figures and sentences therefore overstate how much tree loss is dated harvest by about 4x. The fix is in wording: "patches that touch a dated harvest", and hectares described as patch area rather than harvest area. Caveat: the published tags were made against the cutblock layer as it was at publish time, but `in_harvest` is intersects by definition either way.

- **[severity: claim]** vignettes/articles/wayback-change.Rmd:295-301 (and the comment at data-raw/wayback_change.R:67-70) — The text sets the clearing against "Across the floodplain from it, the harvest that started in 2020" as if the clearing were something else, but the clearing is itself a cutblock that started in 2020. Cutblock part with HARVEST_START_YEAR_CALENDAR = 2020: 8.5 ha, bbox x 684075-684500, y 6028688-6029026, 0 ha in the floodplain, entirely inside the window. That is the clearing with the spur road.
  - Likewise, "New bare strips also run east from it through the forest outside the floodplain, where the change layer has nothing" reads as undated change. Those strips are a 2023 cutblock: 15.9 ha, x 685630-686535, y 6028357-6028937, 0.1 ha in the floodplain.
  - "Has nothing" is literally true of the change layer, but the passage's thesis is that tree loss lines up with dated harvest. The largest dated 2020 and 2023 harvests in the box are the clearing and the eastern strips, both outside the floodplain. The outlined floodplain patches mostly sit beside them (see the finding above).
  - A reader takes away the wrong picture of where the 2020 and 2023 harvest is.

- **[severity: claim]** vignettes/articles/wayback-change.Rmd:297-298 — "much of it is bare by 2022", where "it" is the 2020-tagged patches, 30.5 ha. In the committed s2_2022.tif, the share of pixels with red > green inside each patch is: 7017 (13.4 ha) 0.63, 7028 (10.5 ha) 0.10, 7003 (6.6 ha) 0.03. By that proxy about a third of the 30.5 ha is bare, all of it in 7017, the patch at the west end of the window. The fig-s2 2022 panel agrees: 7017 is orange, and the middle strip (7003) and the southern lobe below the window (7028) read green. "Much of it" is borderline at best; "the western part of it" is what the panel shows.

Checked and fine:
- Offline render: the article re-renders from the committed files alone.
- `in_harvest` reads back as logical, and `harvest_year` as integer with NA.
- The source has no NA in `in_harvest`.
- No empty edge WKT.
- All 21 label points lie inside their clipped patches.
- Ordering is deterministic: `order()` is stable on the ties.
- Directions:
  - The window moved south as stated.
  - The clearing lies between the two floodplain arms and outside both.
  - The road along the floodplain edge and the bare south-west valley floor are visible in the 2020-09-18 panel.
  - 6964 lies east of the 2020 patches, along the river.
  - 6964 is green in 2022 (red > green 0.05) and pale in 2023 (0.47).
- Rendered numbers: 71.3 ha all, 55.6 ha tagged, 30.5 ha (2020), 25.1 ha (2023).

## Mechanism

Every earlier finding is one shared assumption. A spatial claim (what lies where, inside what, and what it was) was written from what a name, a construction or a glance implies, and never measured against the layers the article already holds. Each instance:

- `in_harvest` read as "inside".
- "Built on the floodplain" read as "all of it on the floodplain".
- "Undated by the change layer" read as "not harvest".
- "Bare" written from an impression of the panel.
- A label point read as a readable label.
- One `st_intersection` row assumed per input.

The test for each place: does the sentence agree with the cutblock, tree-loss and floodplain geometries, and with the pixels, when they are overlaid?

Method:
- Rendered a copy of the article (offline, exit 0) and looked at fig-window, fig-overview, fig-s2 and fig-change.
- Overlaid the cutblock, tree-loss and floodplain outlines on the three committed Wayback window chips.
- Measured mean brightness inside each cutblock in those chips (scratchpad `wb/f3/chk_win.png`, `chk2.R`).
- Read `floodplains/scripts/floodplain_lcc/03_lulc_classify.R`, `fp_disturbance.R`, `config/disturbance.yml`, and drift's `R/dft_rast_transition.R`, `R/dft_rast_break_class.R`, `R/dft_transition_artifact.R`, `R/dft_stac_fetch.R`.

## Enumeration (place — OK / wrong, evidence)

- **Rmd:123, fig-window caption: "In the first two … the valley floor in the south is open ground along the river".** WRONG (see Finding 1).
- **Rmd:135-136: "the valley floor to the south is open ground with scattered trees along the river".** WRONG (see Finding 1).
- **Rmd:123/137-138: "a clearing with a spur road has opened in the forest, between two arms of the floodplain and outside both".** OK. Cutblock 23045 sits between the arms with `fp_ha` 0. Its brightness rises from 63-65 to 89.6, and the spur road is visible in the chip.
- **Rmd:123/138-139: "A road now runs along the edge of the floodplain".** OK. The pale road follows the NW floodplain edge in the 2020-09-18 chip.
- **Rmd:123/139: "the south-west of the valley floor is bare" (third image).** OK. 23043 brightness is 88.9 in 2020, against the forest reference of 68.8.
- **Rmd:283-290, cutblock paragraph.** OK.
  - Counts match `cutblocks.csv` and the render: 9 blocks, 52.9 ha, 14.2 ha in the floodplain, 8 mapped by satellite.
  - "The 2018 panel labels each": 9 labels counted on the 2018 panel.
  - The labels now have halos and sit above the window square.
  - The 2019 label ends at its point, overlapping the edge of block 510624.
- **Rmd:313-316: clearing forest in 2018, bare in 2020, cut between June 2018 and July 2020, layer start year 2020.** OK, by fig-s2 and `start_year`.
- **Rmd:316: "By 2022 it is greening".** OK, in the fig-s2 2022 panel.
- **Rmd:316-318: "A second 2020 cutblock lies on the valley floor to its south-west".** OK. 23043 has `fp_ha` 6.57 of 9.09 and lies SW of 23045. Two further 2020 blocks (23046, 23047) east of the window go unmentioned, which leaves the sentence true.
- **Rmd:318-321: 2023 cutblocks, 26.8 ha, bare in 2023.** OK.
  - The largest, 80122, runs east through forest with `fp_ha` 0.14 of 15.93 ("outside the floodplain" to 1%).
  - Two sit on the valley floor along the river: 80362 (3.6 of 3.6 ha in the floodplain) and 80367 (3.84 of 3.87).
  - 80884 is in the NW forest.
  - All four are pale or orange in the 2023 panel.
- **Rmd:321-322: no sub-metre capture of the 2022/2023 change.** OK. The newest capture is 2020-09-18; `release_to` is 2026-09-24.
- **Rmd:330-334: `dft_stac_fetch` / `dft_rast_classify` / `dft_rast_transition(patch_area_min = 10000)` / `dft_transition_vectors`, 2017→2023, 1 ha sieve.** OK. Matches `03_lulc_classify.R:105-125, 201-206`. The sieve in `dft_rast_transition.R:112-125` acts on changed-pixel patches whatever the class pair, as "1 ha sieve" implies. Per-transition polygons and the sub-basin clip can still be under 1 ha (the CSV has 0.01-0.82 ha rows), but the table filters on ≥ 1 ha in the box and says so.
- **Rmd:335-337: tags are the 2017-2023 fire and harvest a patch touches; `harvest_start_year_calendar` is the start year of the cutblock it overlaps most.** OK. `fp_disturbance.R:236` uses `st_intersects`, the dominant feature is chosen by `slice_max(._ov)`, and the window comes from `disturbance.yml` / `change_interval`.
- **Rmd:337 and limits Rmd:400: "The layer covers only the floodplain".** OK as a statement of the layer's domain. `dft_stac_fetch` masks to the floodplain (`R/dft_stac_fetch.R:255`, `terra::mask`, touches = TRUE), so the 2.5 of 71.3 ha that r2 found beyond the drawn edge are the 10 m cells touching it. The claim is about extent, not "all of it", so the r2 defect does not recur.
- **Rmd:347, fig-change caption.** OK.
  - Seven dashed patches ≥ 1 ha are drawn and all seven are labelled: 6493, 6909, 6964, 7003, 7017, 7028, 7029.
  - The cutblock window 2017–`max(s2_years)` is the same `max(years_key)` the script filters on.
  - The image is the whole box.
- **Rmd:357-369, change table and caption.** OK.
  - `tl_big` is `area_ha >= 1` on the area in the box, as captioned.
  - `cutblock_ha` is taken against the same 2017-2023 set, clipped to the box (`data-raw:328, 344-346`).
- **Rmd:372-374: 71.3 ha / 55.6 ha / 13.9 ha.** OK. `treeloss.csv` sums to 71.28, 55.63 and 13.87. The rendered text matches.
- **Rmd:375-377: 6964 runs along the river, is pale only in 2023, and most of it lies outside the 2023 cutblocks it touches.** OK. 7.1 of 25.15 ha lies inside any 2017-2023 block. Brightness by year was checked in r2 and the 2023 panel agrees.
- **Rmd:377-380: `dft_rast_break_class()` / `dft_transition_artifact()` test whether change is sustained across the series or sits on a class edge.** OK. `break_class` reports per-pixel switch/flicker status, whose cells make up a patch. `transition_artifact`'s `boundary_frac` / `flag_boundary` is the class-edge test.
- **Limits Rmd:400-404.** OK. `in_harvest` is stated as touching, 2017–2023. "Most" cutblocks were satellite-mapped: 8 of 9.
- **`data-raw` comment :71-73 (window choice).** OK. 23045 lies between the arms and 23043 SW of it on the valley floor.
- **`data-raw:283-307, 324-351`, positional joins.** OK.
  - Rows are filtered to area > 0 before the per-row work.
  - `stopifnot` checks the lengths.
  - `cb` is sorted before `cb_in`.
  - `tv` and `tv_in` share an order and are sorted only after the data.frame is built.
- **`data-raw:274-275` cutblock window vs floodplains' tag window.** OK. Both are 2017-2023: `max(years_key)` = 2023 = the `change_interval` end.

## Findings

1. **[claim] vignettes/articles/wayback-change.Rmd:123 (fig-window caption) and :135-136 (prose).** The text says that in the 2014 and 2016 images "the valley floor in the south is open ground along the river" / "open ground with scattered trees along the river". The south-west of the valley floor in the window was forest in both images, and it is exactly the ground that the third image then shows as bare.

   **Evidence, from the committed window chips and cutblock outlines.** Mean brightness inside 2020 cutblock 23043 (6.57 of its 9.09 ha in the floodplain):

   | Area | 2014 | 2016 | 2020 |
   |---|---|---|---|
   | Inside 23043 | 71.8 | 75.7 | 88.9 |
   | Forest reference (NW 300 m of the window) | 67.8 | 63.3 | 68.8 |
   | Floodplain in the window | 88.3 | 81.4 | n/a |
   | Clearing 23045 | n/a | n/a | 89.6 |

   So 23043 read as forest before 2020 and as bare ground in 2020. Overlaid, its interior is closed conifer canopy in both earlier chips.

   The riverside stands are the same: 2023 blocks 80362 and 80367, which the article itself says "sit on the valley floor along the river", read 53.8-62.4 in 2014. That is darker than the forest reference, so they are stands, not "scattered trees". The change layer agrees: patches 7017 (Trees -> Crops), 7003 and 6964 were Trees in 2017.

   **Consequence.** The figure's before/after reads as open ground turning bare, rather than forest on the valley floor being cut. It also contradicts the S2 paragraph (:316-320), which puts a 2020 and two 2023 cutblocks on that valley floor.

   **Fix.** Describe the earlier valley floor as open ground with stands of forest, including the south-west, which is the part bare by the third image.

The other places that the mechanism reaches all check out against the data, the rendered figures and the floodplains and drift code. No code defects were found in this round.

# Progress — dft_stac_composite(aggregation = "count") (#92)

## Session 2026-09-30

- Plan-mode exploration; phases approved by user (count lives in `aggregation = "count"`; count cache keyed under its own tag, `count_<key>.tif`)
- Created branch `92-dft-stac-composite-aggregation-count-si` off main
- Scaffolded PWF baseline from issue #92 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) folded in: `"count"` never reaches cube_view, and the 0/NaN chunk dependence was measured, giving the rule 0 -> NA. Phase 2 was rewritten accordingly.
- Phase 1 committed (727c5d9) after 3 code-check rounds. Round 1 found `last` refused and was fixed by a behaviour round trip. Round 2 was clean. Round 3's message claim was fixed and then enumerated (8 claims).
- Filed #96 (resampling has the same silent fallback)
- Phase 2 implemented. 7 mutations each redden the composite tests.
- Phase 2 committed (ba0b203) after 3 code-check rounds and an enumeration of the count build's wiring
- Phases 3-5 reviewed over 3 rounds:
  - round 1: six prose claims fixed;
  - round 2: the Phase 1 lower-casing had moved mixed-case cache keys, fixed by returning the value as given;
  - round 3: a caller-level key test was added; the enumeration against v0.19.2 keys shows none moved.
- Live checks: counts 4-9 on a 2 km square. BULK: 20 count chips in 9.6 min, 0.46 GiB peak. Full suite: 1431 pass, 0 fail.

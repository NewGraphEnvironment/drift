# Progress — Promote Esri Wayback capture index + chip fetch to dft_wayback_* (#101)

## Session 2026-10-14

- Plan-mode exploration — phases approved by user (zoom range deepest-wins; polygons every capture + cover)
- Created branch `101-promote-esri-wayback-capture-index-chip` off main
- Scaffolded PWF baseline from issue #101 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) folded into Phases 2-4; triage in `review-plan.md`
- Phase 1 `ce2d3c6`, Phase 2 `077d2c3`, Phase 3 `309ab82`, Phase 4 `db285a1`, Phase 5 docs `0c0fc69`
- Full suite after Phase 4: 0 fail, 1699 pass, 22 skip

### /code-check branch (2026-10-14)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 1 | 3 (fragile) | 3 | 0 | — |
| 2 | 1 (bug: default make_valid drops touching parts) | 1 | 0 | n (original Phase 2 code) |
| 3 | 1 (fragile: `geos_method` needs sf >= 1.0-8) | 1 | 0 | y (round 2's fix) |

Ended by enumeration: the 51 distinct `pkg::fn` calls in the diff checked for version-gated arguments
against each package's NEWS; only `st_make_valid(geos_method =)` lacked a floor (now `sf (>= 1.0-8)`).
Round 3 also traced rounds 1-2 to one mechanism (fixtures built to a belief about the service or a library
default, never checked against a real answer) and checked its five remaining reaches live: footprint
geometry types, the repaired parse against union-minus-holes, DrawOrder ties, Esri's own layer-for-zoom
rule (`23 - zoom`, capped at 13), paging. Commits `2d7857e`, `8f1c057`, `779a3aa`.

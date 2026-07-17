# Issue #42 — dft_transition_attribute(): tag transition patches from an overlay layer

## Outcome

Added `dft_transition_attribute()` (v0.8.0), a generic helper that tags change patches from
`dft_transition_vectors()` with columns from any overlay polygon layer (fire perimeters,
cutblocks, roads), with a spatial `predicate`, a `match_mode` of `"all"` (duplicating left
join) or `"largest"` (one row per patch by greatest overlap), and an optional inclusive
`year_col` + `interval` temporal filter. drift stays domain-free; the floodplains driver
supplies the tables and interval. `spacehakr::spk_join()` was evaluated as a dependency and
rejected — its reusable part is a thin veneer over `sf::st_join`, and the load-bearing pieces
(interval semantics, area-majority) didn't exist there. Key learnings: `sf::st_join(largest =
TRUE)` silently ignores the join predicate (matching is pure intersection), so the function
aborts on custom predicate + `"largest"` rather than mis-attributing; and `cols` naming the
overlay's geometry column (e.g. `geom` from a GeoPackage) passes naive name checks but breaks
the join contract — guard with `attr(overlay, "sf_column")`. Patches carry no interval columns,
so the transition interval is an explicit argument by design.

Closed by: branch `42-dft-transition-attribute-tag-transition` (commits 84be3a8, 40553e4,
45fb59b, 7b9a30e) / PR pending

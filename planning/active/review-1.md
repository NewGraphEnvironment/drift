# Plan review 1 (Plan agent, 2026-10-17) — condensed by the parent session

Blockers
1. Opening drafted around "real change vs noise" contradicts the user's machinery framing. Lead with what drift does; one sentence for Sentinel-2 composites / Esri Wayback / accuracy sampling, linking articles.
2. "Ties change to causes such as fire and harvest" overclaims: `dft_transition_attribute()` tags patches with columns from an overlay the user supplies, by overlap (optionally year). Say "tags change areas with overlapping records you supply, such as fire perimeters or cutblocks".
3. gdalcubes note is wrong today: more than fetch/cube need it. Word as "functions that read STAC or Sentinel-2 imagery"; Wayback does not; `dft_rast_break()` needs bfast.

Gaps
4. DESCRIPTION Title missing from Phase 3. Keep Title (it spells drift; renames citation otherwise); make tagline + About match.
5. Ecosystem: use the org Package | Role table; copy roles verbatim (drift: "Track land cover change within floodplains over time").
6. Data and methods: add mapaccuracy, Microsoft Planetary Computer, kNDVI. "Free satellite maps" not true of own COGs.
7. What-it-does stages omit spectral trajectories; consider folding the list into the opening.
8. Caption: say what "Other change" lumps (~1.9 ha w/ four classes) and that change is in the map's classes.
9. Legend labels, CRS transform, name the place for a stranger.
10. Docs URL scope: DESCRIPTION, _pkgdown.yml, README, About homepage (https). Not NEWS/archive. CLAUDE.md:817 links neexdzii-kwa.html (404).
11. NEWS entry.
12. Forecast a word count for "measure the simplification".

Ordering
13. _pkgdown.yml url + DESCRIPTION URL in one commit.
14. `gh repo edit` after merge; read back.
15. Don't hand-edit CITATION.cff.

Assumptions checked: www url safe for pkgdown (no CNAME written for a /drift/ path), inst/CITATION uses first URL (keep order), cffr supports authors_roles. Cross-repo: link/flooded/gq/fresh keep github.io in DESCRIPTION.

Scope
16. Drop or minimise the "what it does" list.
17. drift_readme.csv in inst/ vs data-raw/: judgment call.

Acceptance
18. 33 exports, each in exactly one reference section (proposed table); validate topics vs man/*.Rd.
19. Example runs without network; agrees with figure.
20. PNG no alpha; logo alt text; badges markers; article links 200.

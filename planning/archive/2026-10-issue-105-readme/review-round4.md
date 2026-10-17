# Code-check round 4: branch 105-readme-describe-accuracy-assessment-brea (2026-10-17)

Reviewer: subagent, read-only on the repo apart from this file. Focus: commit 61641c2, which fixed
round 3's two findings. Numbers recomputed with `pkgload::load_all()` on the bundled reach
(`dft_rast_classify()` + `dft_rast_transition(classified, "2017", "2023")`).

## Clean

No bugs, security issues or false claims found.

## Verification

1. **Both fixes are true.**
   - `$summary` has 14 rows, 10 with `from_class != to_class` (34.03 ha). Ungrouped, the map would
     carry 10 fill colours, so the script comment "four colours, not ten" is true.
   - Group totals: Trees to rangeland 21.11, Crops to rangeland 9.98, Became water 1.73
     (Trees to Water 0.98 + Rangeland to Water 0.75), Other 1.21 ha. 34.03 - 32.82 = 1.21, so the
     "Other change" key holds exactly what the three named keys leave of the change. The six lumped
     transitions are Rangeland to Trees 0.85, Built Area to Rangeland 0.28, Water to Trees 0.03,
     Flooded Vegetation to Rangeland 0.02, Snow/Ice to Rangeland 0.02, Built Area to Trees 0.01.
2. **The new wording introduces no false claim.** "34 of the 123 ha mapped changed class;
   'Other change' lumps the remaining 1.2 ha." Read as the remainder of the 34 ha changed after the
   three named legend keys, it is exactly true (1.21 ha). Read as the remainder of the 123 ha, it
   would mean 89 ha. The number itself and the fact that "Other change" is a change key rule that
   reading out, so it cannot mislead toward a false figure. "Smaller" is gone, so round 3's
   transition-grain comparison (0.85 lumped vs 0.75 named) no longer arises.
3. **Round 3's enumeration re-checked against the current tree.** Only README.md line 13 and
   script line 22 changed since round 3; every other row stands. Recomputed values match the
   enumeration: total 123.11 ha, both years 12,311 valid cells, `head(change$summary, 6)` rows
   (4918/49.2/40.0 ... 98/0.98/0.8) match the README's printed output. No number or quantifier now
   sits beside a set at a different grain.

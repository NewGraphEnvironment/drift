# Findings

## Repo state (2026-04-14)
- drift: main at HEAD, no existing `.onAttach` or `.onLoad` in R/ (verified via grep)
- `planning/active/` is empty, `planning/archive/` has one prior issue
- CLAUDE.md has unrelated unstaged changes — leave alone
- DESCRIPTION: "Detecting Riparian and Inland Floodplain Transitions" — no clash with a CSV-backed startup hook

## Skill reference
- `/quotes-enable` lives at `soul/skills/quotes-enable/SKILL.md`
- Calibration source: `~/Projects/repo/fpr/R/intro.R`, `~/Projects/repo/rfp/R/intro.R`
- Per-package cost: 10-line `R/zzz.R` + one CSV, zero `DESCRIPTION` changes

## Design constraints
- No internal deps — base `utils::read.csv` only
- UTF-8 CSV with primary-source URL column required
- Drop unverified quotes rather than pad

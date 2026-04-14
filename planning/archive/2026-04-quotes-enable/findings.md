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

## Lyric decision (2026-04-14)
- Considered adding a handful of song lyrics from the same 15 artists, cited to Genius URLs
- Genius API token obtained and stored in `~/.Renviron` as `GENIUS_API_TOKEN` — usable for future metadata/annotation queries
- Copyright posture: lyrics are songwriter/publisher-copyrighted (not Genius's to license for redistribution). Fair-use defense for one-line-attributed-transformative is plausible but not zero-risk. Lyric reproduction sits at a different legal bar than quoting reported interview speech.
- Subagent tasked with lyric extraction refused on reproduction grounds (reasonable stance). Offered alternatives: (a) pointers-only — songs + Genius links + thematic notes, human picks lines; (b) skip lyrics, stay interview-only; (c) human supplies lines, agent verifies
- **Decision: interview-only.** Interview reporting has clean quote-and-comment fair-use precedent; lyrics add legal ambiguity for marginal tonal benefit. We already have 48 defensible interview KEEPs.
- **Reusable precedent for future `/quotes-enable` runs:** interview quotes are the default; lyric supplementation requires human-in-the-loop selection (not agent-driven extraction).

## Audit trail architecture (2026-04-14)
- `inst/extdata/quotes.csv` — shipped, slim (quote, author, source). Rock-solid rows only.
- `data-raw/quotes_audit.csv` — full provenance record (tier, fetch excerpt, verification date, source_type, drop_reason). Excluded from built package via `.Rbuildignore`.
- `data-raw/quotes_build.R` — filters audit → shipped CSV. Reproducibility entry point.
- `data-raw/README.md` — provenance note for future maintainers.

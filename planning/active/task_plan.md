# Task Plan: Enable Startup Quotes in drift

Applies the `/quotes-enable` soul skill to drift. Adds `R/zzz.R` + `inst/extdata/quotes.csv` with fact-checked quotes from user-directed sources.

## Phase 1: Inputs
- [x] User supplies people list (required)
- [x] User supplies topics list (optional) — "inspirational and philosophical"
- [x] User confirms target count — target 30 verified

People: Young Thug, Travis Scott, Anderson .Paak, Kendrick Lamar, Bad Bunny, Playboi Carti, Ty Dolla $ign, Metro Boomin, Yeat, Future, Takeoff, Offset, Mike WiLL Made-It, Statik Selektah, YoungBoy Never Broke Again

Audit requirement: every quote must carry a primary-source URL (interview transcript, verified publication, official transcript) so it can be re-verified later.

## Phase 2: Calibration
- [ ] Load fpr/rfp intro.R quote lists as tone reference
- [ ] Surface 5–10 examples for user alignment

## Phase 3: Research
- [x] Launch parallel research agents, one per person/cluster (4 agents)
- [x] Each returns candidates with quote, author, source_url, source_type
- [x] Aggregate candidates — 77 candidates across 15 artists

## Phase 4: Fact-check
- [x] Launch parallel fact-check agents — 1 tier-2 chain-check + 1 spot-check on direct-primary
- [x] Each quote independently verified via WebSearch + WebFetch
- [x] Drop every UNVERIFIED — 1 dropped (Kendrick Clique TV), 4 upgraded to primary URLs

## Phase 5: Calibration filter + review
- [x] Filter surviving quotes for tone (inspirational/intelligent, not generic)
- [x] Shortlist written to `final_shortlist.md`: 48 KEEP + 22 BORDERLINE + 6 dropped
- [x] User decided: drop all BORDERLINE, reinforce underrepresented artists

## Phase 5b: Lyric supplement
- [x] Considered Genius-sourced lyrics; obtained API token; evaluated copyright posture
- [x] Agent refused lyric reproduction; decision: interview-only (see findings.md)
- [x] Lesson propagated to soul skill (separate branch)

## Phase 5c: Reinforce underrepresented artists
- [x] Launch research agent for Metro, Carti, Ty Dolla, Yeat, Takeoff
- [x] 13 new candidates returned, all primary-source verified
- [x] Net new additions: 13 (2 Metro quotes overlapped source with borderline, kept cleaner phrasing)

## Phase 6: Wire up drift
- [x] Write `data-raw/quotes_build.R` (source of truth — R tibble with full provenance)
- [x] Write `data-raw/quotes_audit.csv` (generated — full audit trail)
- [x] Write `inst/extdata/quotes.csv` (generated — shipped slim CSV, 61 rows)
- [x] Write `data-raw/README.md` (provenance note)
- [x] Write `R/zzz.R` (skill template, zero deps)
- [x] Confirm no existing .onAttach to collide with (verified: none)

## Phase 7: Verify
- [x] `devtools::load_all()` — quote prints correctly on attach
- [x] `R CMD check .` — no new NOTE/WARN (2 pre-existing NOTEs unrelated to our changes)
- [x] CSV round-trip test — 61 rows written and re-readable

## Phase 8: Commit + archive
- [ ] Commit core changes (zzz.R + data-raw + inst/extdata + PWF updates)
- [ ] Push branch, open PR
- [ ] Archive `planning/active/` → `planning/archive/` with README after merge

# Task Plan: Enable Startup Quotes in drift

Applies the `/quotes-enable` soul skill to drift. Adds `R/zzz.R` + `inst/extdata/quotes.csv` with fact-checked quotes from user-directed sources.

## Phase 1: Inputs
- [ ] User supplies people list (required)
- [ ] User supplies topics list (optional)
- [ ] User confirms target count (default 30)

## Phase 2: Calibration
- [ ] Load fpr/rfp intro.R quote lists as tone reference
- [ ] Surface 5–10 examples for user alignment

## Phase 3: Research
- [ ] Launch parallel research agents, one per person/cluster
- [ ] Each returns candidates with quote, author, source_url, source_type
- [ ] Aggregate candidates

## Phase 4: Fact-check
- [ ] Launch parallel fact-check agents (batched ~10 per agent)
- [ ] Each quote independently verified via WebSearch + WebFetch
- [ ] Drop every UNVERIFIED — no padding

## Phase 5: Calibration filter + review
- [ ] Filter surviving quotes for tone (inspirational/intelligent, not generic)
- [ ] Present final list with sources to user
- [ ] User vetoes any that don't fit

## Phase 6: Wire up drift
- [ ] Write `inst/extdata/quotes.csv` (UTF-8)
- [ ] CSV round-trip test (read back, confirm count + sample)
- [ ] Write `R/zzz.R` (skill template, zero deps)
- [ ] Confirm no existing .onAttach to collide with (verified: none)

## Phase 7: Verify
- [ ] `devtools::load_all()` and `library(drift)` — quote prints
- [ ] Three successive attaches give (usually) different quotes
- [ ] `R CMD check .` — no new NOTE/WARN

## Phase 8: Commit + archive
- [ ] `/code-check` on staged diff
- [ ] Commit `R/zzz.R` + `inst/extdata/quotes.csv` with checkbox update
- [ ] Push branch, open PR
- [ ] Archive `planning/active/` → `planning/archive/` with README after merge

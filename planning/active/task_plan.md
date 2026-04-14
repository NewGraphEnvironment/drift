# Task Plan: Domain-Expert Quotes for drift

Second `/quotes-enable`-style pass on drift. Adds quotes from voices in floodplain/river process, Indigenous stewardship, ecosystem valuation, and legacy conservation thinkers — paired with the existing 61 hip-hop interview quotes in `inst/extdata/quotes.csv`.

## Phase 1: Target list
- [x] User-directed list: Beechie, Montgomery, Wohl, Kimmerer, Whyte, Turner, Armstrong, Kai Chan, Suzuki, Wade Davis, Leopold, Berry
- [x] Tone brief: core concepts, meaningfulness, place, floodplain process, why it matters

## Phase 2: Research (parallel)
- [x] 4 research agents launched (clustered by domain)
- [x] 55 candidates returned; Beechie = 0 (no public interview footprint, confirmed)

## Phase 3: Fact-check
- [x] Tier-2 verification agent on book-chained sources
- [x] Spot-check agent on direct-primary URLs (14 random)
- [x] 3 dropped (Wohl misattribution, Kimmerer thin-chain, Davis fragment-not-sentence); 2 fixed (Kimmerer gift economy restored, Whyte wording corrected)

## Phase 4: Calibration filter + user review
- [x] Tone filter — all 52 remaining pass
- [x] User reviewed `domain_quotes_review.csv`, approved

## Phase 5: Merge into data-raw
- [x] Appended 52 new rows to `data-raw/quotes_build.R` tibble
- [x] Ran build — 113 total quotes in both CSVs
- [x] Verified `devtools::load_all()` picks from the combined pool

## Phase 6: Ship
- [x] Patch-bump DESCRIPTION to 0.2.2
- [x] NEWS entry
- [ ] `R CMD check` clean
- [ ] Commit, push, PR
- [ ] Archive planning after merge

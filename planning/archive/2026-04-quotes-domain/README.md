## Outcome

Second `/quotes-enable`-style pass on drift. Expanded the startup-quote pool from 61 to 113 by adding 52 domain-expert voices across floodplain/river process, Indigenous stewardship, ecosystem valuation, Canadian public voices, and legacy conservation thinkers. Shipped in v0.2.2.

**Process:** 4 parallel research agents returned 55 candidates from a user-directed 12-person list (Beechie, Montgomery, Wohl, Kimmerer, Whyte, Turner, Armstrong, Chan, Suzuki, Wade Davis, Leopold, Berry). 2 parallel fact-check agents flagged 3 drops (Wohl misattribution, Kimmerer thin-chain, Davis grammatical reconstruction) and 2 fixes (Kimmerer gift-economy tail restored; Whyte opening sentence corrected). User reviewed `domain_quotes_review.csv`, approved all 52. Beechie yielded zero — no public interview / podcast / documentary footprint, process-paper voice only.

**Lesson:** Book-source quotes from canonical literature (Leopold *SCA* / *Round River*, Berry, Kimmerer *Braiding Sweetgrass*, Wade Davis TED) come back as `CHAIN_ONLY` when no publisher-hosted full-text scan is retrievable via WebFetch. Broad consensus across multiple independent compilation sites (Wikiquote, LitCharts, Goodreads-with-page-citation, Aldo Leopold Foundation, Sierra Club PDFs) is documented as the audit posture for this literature class.

Closed by: drift PR #24 (`quotes-domain` branch, v0.2.2).

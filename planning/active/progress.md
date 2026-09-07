# Progress — sliver-shaped patches and where flicker concentrates (#73)

## Session 2026-09-07

- Plan-mode exploration; two scale probes on the real BULK floodplain (169M cells) rather than
  the bundled 600x600 tile, per the CLAUDE.md scale rule
- Established that Phase 1 needs no computation and Phase 2's distance transform is 8.3 s, not
  the expensive half the issue body assumes
- Measured the corridor profile under two references; the effect is monotone and holds under the
  non-circular one
- Found the acceptance criterion cites a sentence absent from the article
- Two forks put to the user and answered: raise the body-prose cap to 1200 and keep both sections
  in the article; no new export, the distance pass stays in `data-raw/`
- Created branch `73-article-sliver-shaped-patches-and-where` off main
- Scaffolded the PWF baseline with the approved phases
- Next: Phase 1, the `corridor` stage

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

## Session 2026-09-07 (continued)

- Phase 1: `corridor` stage, all four groups, 424 s / 12.6 GiB peak. Every guard green including
  the core-count identity per group and both comparator controls.
- Plan review returned mid-implementation with 9 verified findings. Two changed the result: the
  stable-water core excises the stable class from the near bands (so the honest read is
  within-Trees), and `break_sustained` does not establish a walk (so `break_year` was added). A
  third asked for a real null rather than a composition control — added, and it came back
  negative, which is the finding.
- Withdrew two claims of my own that the review disproved: "monotone in every column" and "the
  issue body has the cost inverted". The second would have put a wrong correction on the record.
- Phase 2: `summary_patch_widths.csv` from the existing read, with a partition assertion.
  `summarize` regenerated every pre-existing output byte-identical.
- Phase 3: two article sections and a line-profile figure; 1193 words against the 1200 cap;
  rendered and the PNG read. Reading it caught an imprecise claim ("not weaker but steeper" — the
  null line is lower everywhere, not just steeper) which was corrected in the prose.
- Phase 4: note Q6, logs README, CLAUDE.md pointers, issue body reconciled, NEWS 0.17.0.
- Tests 1003 pass / 0 fail; `pkgdown::check_pkgdown()` clean; NAMESPACE unchanged.

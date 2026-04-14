# data-raw/quotes

Source and provenance for the startup quotes shown on `library(drift)`.

## Files

- `quotes_build.R` — **source of truth**. Contains the full quote list inline as an R tibble with full provenance columns. Run to regenerate the two output CSVs.
- `quotes_audit.csv` — generated. Full provenance record: quote, author, source URL, source_type, source_outlet, verification_date. Kept in the repo for audit trail; excluded from the built package via `.Rbuildignore`.
- `../inst/extdata/quotes.csv` — generated. Slim three-column shipped CSV (quote, author, source). Read at package attach by `R/zzz.R`.

## To add, edit, or remove a quote

1. Edit the `quotes` tibble in `quotes_build.R`
2. Every row must have a primary-source URL where the exact text was confirmed via a direct fetch of that URL on the recorded `verification_date`
3. Run `Rscript data-raw/quotes_build.R` from the repo root
4. Both output CSVs regenerate; commit all three files together

## Runtime toggle: show source URL on attach

`R/zzz.R` prints a clickable `source` hyperlink (OSC 8) alongside the quote by default. Works in RStudio (2022.12+) and modern terminals. In environments without OSC 8 support (older terminals, CI logs), the word `source` renders as plain text without URL visible — use the CSV for the trail there. To suppress entirely:

```r
options(drift.quote_show_source = FALSE)
library(drift)
```

Set the option in `~/.Rprofile` if you want the suppression persistent across sessions. Default is `TRUE` (URL visible).

## Standards

- **Primary source required** — published-outlet interviews, speeches, documentary transcripts. No Pinterest / BrainyQuote / azquotes / unsourced social-media screenshots.
- **No padding** — if research can't verify a candidate to primary material, drop it rather than pad to a target count.
- **UTF-8 throughout** — the `.onAttach` hook reads with `encoding = "UTF-8"`.

## Lyric policy

Interview speech only. Song lyrics are songwriter/publisher-copyrighted and outside the fair-use posture this package takes. See `planning/archive/` for the lyric-decision record when the originating issue is archived.

## History

See `planning/archive/` for the full research log, fact-check agent transcripts, and drop decisions from the initial curation round (branch `quotes-enable`, 2026-04-14).

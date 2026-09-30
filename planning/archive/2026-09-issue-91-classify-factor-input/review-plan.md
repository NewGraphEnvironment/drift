# Plan review (#91) — Plan agent, returned as reply text (read-only agent), written here by the session

- **Blocker:** `if (terra::is.factor(x))` errors on a multi-layer stack (per-layer predicate). Fixed: `is.factor(x)[1]`; stack test added.
- **Gap:** no multi-layer test; no active-category != 1 test (a GeoTIFF round-trip resets activeCat, so in memory); RAT ids differing from raw values untested (fix does not depend on the RAT). Added the first two.
- **Ordering:** strip before remap wastes a copy when a remap group matches (`classify()` already reads raw codes). Moved after remap; measured equal to main (5.47 GiB).
- **Assumption:** stale #89 copy-count comment. Rewritten. `strip_copy()` leaves the caller untouched — verified.
- **Scope:** file-backed scale run is metadata-only; the in-memory run is the one that carries a cost. Both recorded.
- **Acceptance:** caller-unmodified test is a guard, not a reproduction (comment added); the no-black colour check depends on the fixture (code 0 is #000000) — replaced with a class_table comparison.

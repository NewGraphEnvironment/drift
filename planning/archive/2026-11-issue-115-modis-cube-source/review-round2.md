# Code-check round 2 (#115): whole branch vs 16f6a22, focus on the round-1 fix 96b19d2

## Checklist read

- **INDEX.md**: all headings and first sentences, all four files.
- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, with tables and evidence blocks skipped. Read in full: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what generators leave in it", "A wrapper's exit is not the work", "Zero-length, empty, and unset are three different things", "The probe is broken before the world is", "Written data outlives the fix", "Serialization loses meaning silently" and "One fact derived twice". Also read "A pluralisation marker takes the quantity of whatever was substituted last". The other non-mechanism headings, about 30, were not read past the index.
- **code-check-r.md**: read "as.POSIXct on character infers ONE format for the whole vector", "`cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation" and "Tests that silently do not run". The other ~117 were not read past the index.
- **code-check-spatial.md**: read "An offset regex must be anchored to a time, or a date looks like a zone", "A reader that accepts a UTC offset may not be applying it" and "Planetary Computer STAC: a floodplain-scale read hits three limits a reach never does". The other ~90 were not read past the index. The gdalcubes headings were judged in round 1, and the fix does not touch them.
- **code-check-shell.md**: none. The diff has no shell; all ~70 were not read past the index.

## Verification (work copy in the scratchpad, repo untouched)

- Test files at HEAD 96b19d2, with `NOT_CRAN=true` and `test_file()`:
  - test-dft_stac_cube.R: 296 pass, 0 fail, 0 error, 4 skip.
  - test-dft_stac_config.R: 50 pass, 0 fail, 0 error, 0 skip.
  - test-dft_index_expr.R: 32 pass, 0 fail, 0 error, 0 skip.
  - test-dft_stac_composite.R: 137 pass, 0 fail, 0 error, 3 skip.
- **Fix 2 (`stac_items_datetime()`)**, probed per input:
  - These read to `2017-06-17T23:59:59Z`: `Z`, fractional `.000Z`/`.999Z`, `+00:00`, and no offset.
  - These are refused as `drift_item_no_datetime`: `-07:00`, lowercase `z`, a date-only value, and a missing end.
  - The regex is anchored at both ends, and the offset must follow `HH:MM:SS`. A date's `-DD` therefore cannot read as a zone, and a two-digit `+00` is refused, not stripped.
  - The result is identical under TZ UTC, America/Vancouver and Asia/Tokyo.
  - Items that have a `datetime` (Sentinel-2) return before the new code, so S2 is unaffected.
- **Fix 1 (`stac_index_roles_check()`)**:
  - Through the real function, n=1 renders `band role "swir16"`, n=2 renders `band roles "green" and "swir16"`, and n=3 lists all three.
  - `qty()` sits immediately before the marker it governs, so `{.val {index}}` no longer sets the quantity.
  - The line-fold before `{.val {absent}}` does not swallow the value.
- **Mutation**: I reverted `t[!utc] <- NA` and the `qty()` in the copy, one at a time against the shipped test file. Each reddened its named test ("a window in UTC reads, and one at another offset is refused (#115)" and "the role refusal counts the missing roles, not the index (#115)"). Both are restored.

## Clean
No issues found.

# Findings — Validate classified input and support arbitrary factor rasters in transitions (#19)

## Issue context

## Problem

`dft_rast_transition()` silently produces wrong results when passed raw integer rasters that weren't classified via `dft_rast_classify()`. The `code_lookup` maps integer codes to class names using the default class table, so:

- If codes happen to match (e.g., IO LULC codes), results look correct but the user never explicitly classified
- If codes don't match (custom rasters, climate data, habitat types), class names are `NA` with no error

As drift generalizes beyond land cover (climate zones, habitat classification, soil types, any categorical raster), this becomes more likely. A user with a pre-classified raster from another source has no reason to run `dft_rast_classify()` first.

## Proposed Solution

Two complementary changes:

1. **Validate input is factor**: If the input SpatRasters are not factor rasters, warn or error with a message pointing to `dft_rast_classify()` or explaining how to set factors manually via `terra::set.cats()`.

2. **Read labels from the raster itself**: Factor rasters already carry their class labels. Instead of requiring a `class_table` to decode integers, read the factor levels directly when available. Fall back to `class_table` only for raw integer rasters. This makes the function work with any pre-classified categorical raster regardless of source.

Option 2 is the bigger unlock — it means `dft_rast_transition()` works out of the box with any factor raster, not just drift-classified ones. A user with climate zone rasters from another package could compute transitions directly.

## What is already true (revised 2026-09-05)

- **The `class_table` path already works for arbitrary codes.** `dft_rast_transition(x, class_table = <tibble with code, class_name, color>)` decodes any integer coding; drift#44's test fixtures run it against a synthetic 4-class table with no IO LULC anywhere. Option 2's *"read labels from the raster itself"* is therefore about convenience for factor inputs, not a capability gap — the remaining gap is that a factor raster's own levels are ignored and a `class_table` must be supplied even when the raster already carries the labels.
- **Downstream functions read the transition raster's levels by contract.** `dft_transition_vectors()` and `dft_transition_artifact()` read `terra::cats()` — the id in the first column (terra's own contract) and the label in a column named `transition` (drift's). Whatever this issue does to how labels get *in* must keep that shape.
- `dft_check_crs()` already refuses lon/lat; the factor check proposed here belongs next to it.

## Scope, revised

1. Validate: non-factor input without a `class_table` is an error naming `dft_rast_classify()` and `terra::set.cats()`.
2. Read labels from factor levels when present and `class_table` is `NULL`; `class_table` still wins when supplied.
3. Unblocks #31.

## Context

Discovered during code review of #14. The current code works because the test data and typical pipeline always use IO LULC codes with the matching default class table. The gap only surfaces with non-standard inputs.

## Probe on main (2026-09-30, bundled tile, read-only)

- `dft_rast_classify(..., remap = list(Vegetation = c("Trees", "Rangeland")))` sets level
  `2 = Vegetation`, yet `dft_rast_transition()` reports `Trees -> Trees` (10,140 cells), because it
  labels from the default IO LULC table and never reads the levels.
- Raw integers `r * 1L + 100L` give `NA -> NA` summary rows (4,918 / 3,026 / 2,111 cells), with no error.
- `dft_rast_break_class()` builds `code_lookup` the same way (`R/dft_rast_break_class.R` L158-161), so it
  has the same mislabel. Its `$raster` is documented as identical to `dft_rast_transition(first, last)`.

## Decisions at the plan gate

- `source = NULL` default. Precedence: `class_table` > explicit `source` > factor levels > error.
- `dft_rast_break_class()` is included and shares one helper, `transition_class_table()`.

## Errors Encountered

| Error | Resolution |
|-------|------------|

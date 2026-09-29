# Code review, round 2 (#81 staged diff: dft_accuracy_estimate / dft_accuracy_labels)

All four round-1 fixes hold up. Staged-only copy: `devtools::test(filter = "accuracy")` gives
55 pass / 0 fail, and `devtools::document()` leaves man/ and NAMESPACE unchanged. I also checked
stratum order against an independent Stehman (2014) computation: 12 strata, names unsorted, the
strata table in reverse order, label rows shuffled. Area proportions, their SEs, OA, UA and the
stratum table's n / n_cells all match. So the s1..sH remap and mapaccuracy's aggregate() and
table() ordering agree with each other.

## Findings

- **[bug]** R/dft_accuracy_labels.R:83-95. A blank `ref_class` gets past the nonresponse
  refusal and is estimated as a class named `""`. The check is `is.na()`, but `read.csv()`
  and `data.table::fread()` both read an empty cell in a character column as `""`, not `NA`.
  Only readr turns it into `NA`. So a reviewer's unlabelled point in a CSV passes the check
  the contract says refuses it, and it goes into mapaccuracy as a real reference class.
  Reproduced with 6 points in 2 strata, one blank:
  - OA comes out 0.667. The blank counts as a disagreement.
  - Class `x`'s area is 0.5 of the total, and the missing 1/6 of area goes nowhere.
  - The `""` row's `area`, `proportion`, `user` and `producer` are all `NA`, because
    `est$area[""]` indexes by name and `x[""]` is always `NA`. So the proportions no longer
    sum to 1, and no error is raised.

  These are silently wrong numbers, on exactly the path the "refused, not dropped" section
  documents. The same gap applies to `point_id`, `stratum` and `map_class`, though a blank
  stratum at least fails loudly as "absent from `strata`". Fix: treat `!nzchar(trimws(x))`
  as missing, alongside `is.na(x)`, in character and factor columns.

- **[fragile]** R/dft_accuracy_estimate.R:159-160 (and :138-139 / dft_accuracy_labels.R:113-114
  for stratum keys). Fix 1 normalises each column with `as.character()`, but `as.character()`
  depends on the type. A double with 5+ trailing zeros prints in scientific notation, an
  integer never does: `as.character(100000)` is `"1e+05"` and `as.character(100000L)` is
  `"100000"`. If `map_class` is double (a raster extract) and `ref_class` is integer (e.g.
  `ref_from * 1000L + ref_to`), class 100000 splits into two classes. Reproduced with 6
  points: every point agrees and OA comes out 0.5, and `$area` has two rows with class
  `100000`, one of them with zero area. Codes like this only occur when `to = 0` and `from`
  is a multiple of 100, so real data should rarely hit it. It is still the round-1 defect
  one axis over: two derivations of one class that disagree. For stratum keys, a CSV
  round trip (double) against an integer `strata$stratum` fails loudly as "absent from
  `strata`", not silently. Fix: for numeric columns, `format(x, scientific = FALSE,
  trim = TRUE, digits = 15)` (or convert both to double) before `as.character()`.

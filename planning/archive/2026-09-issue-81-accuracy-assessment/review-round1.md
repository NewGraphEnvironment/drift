# Code-check review, round 1 (#81, phase 2 staged diff)

Scope: R/dft_accuracy_estimate.R, R/dft_accuracy_labels.R, tests/testthat/test-dft_accuracy_estimate.R,
tests/testthat/helper-accuracy.R, DESCRIPTION, NAMESPACE, man/. Read mapaccuracy::stehman2014() (0.1.2, CRAN)
and its .check_labels / .check_length. The suite passes on a scratch copy: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 50 ]`.
The Olofsson Table 8/9 and section 5.2 transcriptions were checked against the PDF (pp. 13-14) and match.
An independent Olofsson-style computation (12 strata, strata = map classes, so the s1..s12 ids and the
s1-vs-s10 regex are exercised) agrees with the wrapper's area proportions to 1e-17. The SE ratio is
0.997-0.999, which is the FPC.

## Findings

- **[severity: bug]** R/dft_accuracy_estimate.R:156 and :180-181. The class set comes from
  `c(labels$map_class, labels$ref_class)`, but the labels passed to stehman2014() come from
  `as.character()` on each column separately (:157-158). These are two normalisations of the same labels.
  When exactly one column is a factor, `c()` swaps that factor for its integer codes. That happens with
  numeric + factor, and with factor + character, where `c.factor` falls back to `unlist`. The codes then
  become phantom classes. Stehman still gets the right strings, so no error is raised, and the output
  carries extra classes with area 0, zero rows in the matrix, NA accuracies, and extra stratum-table
  targets. Reproduced: `map_class = c(1001, 2002)` numeric with `ref_class` a factor gives an `area` table
  of classes 1, 2, 1001, 2002, and classes 1 and 2 read as "0 ha, SE 0". With IO LULC codes (1, 2, 4, 5,
  7, 8, 11) the phantom codes 3 and 6 look exactly like real classes that have zero area. A factor
  `ref_class` is plausible from a review-tool export. The fix is to build the class set from
  `c(map_chr, ref_chr)`, and to restore numeric type only when both columns are numeric.

- **[severity: fragile]** tests/testthat/test-dft_accuracy_estimate.R:131-132. The assertion
  `expect_false(isTRUE(all.equal(unname(rows[olofsson_classes]), olofsson_pixels / 1e7)))` cannot fail.
  `rows` comes from `tapply()`, so it is a 1-d array, and `unname()` keeps the `dim`. `all.equal()` then
  reports "target is array, current is numeric" whatever the values are. Measured: on
  `tapply(1:4, letters[1:4], sum)` against an identical numeric vector, `isTRUE(all.equal(...))` is FALSE.
  The claim under test does hold (the estimated shares are 0.117 / 0.117 / 0.259 / 0.508 against W_i
  0.020 / 0.015 / 0.320 / 0.645), but the test does not guard it. Wrap `rows[...]` in `as.vector()`.

- **[severity: fragile]** tests/testthat/helper-accuracy.R:104. `expect_within()`'s length guard compares
  `length(d)`, and `d` has already been recycled by the subtraction. So an object shorter than `expected`
  that divides into it passes. Measured: `expect_within(c(1, 2), c(1, 2, 1, 2), 0.1)` passes. Its practical
  reach with the current distinct published values is nil, because a short object cannot match four
  distinct numbers, but the guard does not check what it says it checks. Compare
  `length(act$val) == length(expected)`.

- **[severity: fragile]** R/dft_accuracy_estimate.R:127 with R/dft_accuracy_labels.R:113-120. Labels whose
  stratum has `n_cells == 0` pass `dft_accuracy_labels()`: the stratum is known, and the zero-cell stratum
  is excluded from "uncovered". Line 127 then drops the stratum before the `n_h > n_cells_h` check, so the
  guard written for this case ("More labels than cells") never sees it. `s_lab` becomes NA and the call
  fails inside mapaccuracy with `Arguments should include only: s1, s2, s3, s4`, which names internal ids
  the caller never passed. The failure is loud, not silent, but the message does not locate the fault.
  Count `n_h` against the unfiltered strata, or refuse labels in zero-cell strata in `dft_accuracy_labels()`.

No security issues. DESCRIPTION/NAMESPACE are consistent: mapaccuracy is in Imports, and rlang and tibble,
used by the helper and the tests, are already there.

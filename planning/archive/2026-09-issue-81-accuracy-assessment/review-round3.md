# Code review round 3 (#81): sampler, sizer, and the key mechanism

Reviewer worked in a scratch copy of the repo; the repo tree was not modified. Every
finding below was reproduced with a probe script, and the results are quoted.

## Mechanism

**One identity is derived more than once, each time independently, and the code is
correct only while those derivations happen to agree.** A class, stratum, point or
allocation identity gets re-derived at each use site from whatever representation
reaches it: `as.character()` of a double, the integer codes `c()` returns for a factor,
a factor's levels, `names()` written by `setNames()`, a position in a parallel vector,
or a draw order. Nothing joins on one canonical key. R1 (factor codes vs strings), R2
(`""` vs `NA`) and R2b (`"1e+05"` vs `"100000"`) are all two derivations that disagree
on an input the author did not picture. `accuracy_key()` gives a canonical form for one
representation, numeric. Factor, character and positional identities still go around
it, and so does one new kind of identity: **a point's id is derived from its draw order,
and the census branch derives draw order differently.**

Every place in the four R files where an identity is derived, compared or aligned:

| # | Site | Sound? |
|---|------|--------|
| 1 | labels.R:86 `accuracy_is_missing()` on the required columns | sound |
| 2 | labels.R:99 `point_id` uniqueness through `accuracy_key` | sound |
| 3 | labels.R:107 `use` compared raw against `"accuracy"`/`"training"`; blank `""` is not NA | **fragile** (F4, loud) |
| 4 | labels.R:117-130 label strata vs `strata$stratum`, both keyed; `known[strata$n_cells == 0]` is positional within one frame | sound |
| 5 | labels.R:151-152 `accuracy_check_strata` uniqueness via key | sound |
| 6 | labels.R:167-174 `accuracy_key()` factor branch returns levels verbatim, and `factor(100000)` has level `"1e+05"` | **bug** (F2) |
| 7 | estimate.R:147-149 `n_h` via `factor(lab_key, levels = key)` | sound |
| 8 | estimate.R:152/160 `key[...]` positional in the same filtered frame | sound |
| 9 | estimate.R:169-171 class set from the keys of both columns | sound, except input from #6 |
| 10 | estimate.R:172/195 `classes_numeric` -> `as.numeric(classes)` (keys are full-digit, so the round trip is exact) | sound |
| 11 | estimate.R:178-180 `sid[match(lab_key, key)]`; stehman2014 anchors its stratum regex (`^s1$`, checked in mapaccuracy 0.1.2 source) | sound |
| 12 | estimate.R:197-221 `est$matrix`/`UA`/`PA`/`area` indexed by `classes`; stehman2014 names these by `order` = `classes` | sound |
| 13 | estimate.R:239-243 `accuracy_class_order` (numeric or radix, locale-free) | sound |
| 14 | estimate.R:251-272 stratum table, all keyed; `strata$stratum[h]` positional in the same frame as `key` | sound |
| 15 | sample.R:115-128 pass-1 codes via `setdiff`/`match` on exact whole doubles | sound |
| 16 | sample.R:132-136 codes sorted once and shared by allocation, draw, pass 2 and labels | sound |
| 17 | sample.R:153/162 pass-2 `match(vv, code)`, `match(code, vv[ord])`; `order(method = "radix")` is stable, so the k-th in sorted order is the k-th in cell order. Verified exact against `which(v == h)[rank]` at rows 1/3/600 | sound |
| 18 | sample.R:176 pass-1 vs pass-2 totals guard | sound |
| 19 | sample.R:184 `match(ranks, found$rank)` (integer vs double whole numbers) | sound |
| 20 | sample.R:186 `point_id` = key of code + **draw position** | **bug** (F1) |
| 21 | sample.R:256-284 allocation names normalised through key; `n[key]` | sound |
| 22 | sample.R:311 census returns `seq_len(N)`, which is cell order, not the stream's draw order | **bug** (F1) |
| 23 | sample.R:323-326 stream seed from keys of seed and code | sound |
| 24 | sample.R:331 labels via `match(code, lv[[1]])`; `levels()` returns ID + active category | sound |
| 25 | sample.R:195-198 map values by cell after `compareGeom`; `raw = TRUE` gives codes (factor test passes) | sound |
| 26 | sample.R:220 `design$n_requested` names written by `setNames()` (`"1e+05"`); re-fed as `n`, they are normalised by #21 | sound |
| 27 | size.R:294-307 `weights` vs `s_h`/`ua` aligned **by position**; names on `s_h`/`ua` are ignored, then overwritten at :323 | **fragile** (F3) |
| 28 | size.R:315-322 `names(alloc) <- names(weights)` -> sampler's #21 | sound |
| 29 | estimate.R:245-247 -> size.R:297 census stratum sd is `NA` at n = 1 | **fragile** (F5, loud) |

Also checked and sound:

- **RNG save/restore:**
  - existing seed: kind and seed restored, including `sample.kind = "Rounding"` and L'Ecuyer;
  - absent seed with a non-default kind: kind restored and `.Random.seed` left absent.

  All probed.
- **Chunk-size independence:** the ranks are drawn before either pass, and the resolver is
  deterministic.
- **terra-version stability:** only `readValues` row-major order is relied on.
- **Pilot extension for non-census strata:** `sample.int(useHash = FALSE)` has the partial-
  shuffle prefix property under Rejection sampling.
- **Size allocation arithmetic:** the `proportional_min` loop terminates, including when
  every stratum reaches the floor.

## Findings

- **[severity: bug]** R/dft_accuracy_sample.R:311 (with :184-187). **A census stratum
  breaks the documented pilot-extension and `point_id`-stability contract.** A census
  returns `seq_len(N_h)`, which is cell order. A non-census draw returns the stream's
  order. A stratum with `n_pilot < N_h <= n_full` is drawn from the stream in the pilot
  and taken as a census in the full sample, so its `point_id`s are re-assigned. The
  roxygen promises that "labels from a pilot carry into the full sample (`point_id` is
  stable too)". A caller who joins pilot labels by `point_id` therefore puts reference
  labels on the wrong cells, and the error is silent.

  The case is common: transition strata of 20-50 cells, with a pilot of 20 and a full
  sample of 50 from `dft_accuracy_size()`. Probe: 40-cell stratum, seed 81.
  - n = 30 gives cells `14 2 26 35 16 ...`; n = 50 gives `1 2 3 4 5 ...`.
  - **28 of 30 pilot `point_id`s point at a different cell in the full sample.**

  The test "a larger n extends the pilot" cannot reach this: no stratum on r17 has
  30 < N <= 50. Its counts are 941/7127/2/998/55/2/3186.

  Fix: drop the early return, and draw `sample.int(N_h, min(n, N_h), useHash = FALSE)`
  for every stratum. With size = N it is a full permutation, and it extends any smaller
  draw (verified: `sample.int(40, 40)[1:30] == sample.int(40, 30)` under the same seed).
  The golden test pins stratum 2 and stratum 1's first ids, which are not census strata,
  so it is unaffected. The package is unreleased, so no stored sample moves.

- **[severity: bug]** R/dft_accuracy_labels.R:168. **The factor branch of `accuracy_key()`
  lets the R2b split back in through a factor column.** `factor()` builds its levels with
  `as.character()`, so `factor(100000)` has the level `"1e+05"`, while a numeric
  `ref_class` of 100000 keys to `"100000"`. Probe: `map_class =
  factor(rep(c(100000, 2), each = 4))` with a numeric `ref_class`.
  - The result has classes `2`, `1e+05` and `100000`.
  - User's accuracy for `1e+05` is 0, and for `100000` it is `NA`.
  - **Overall accuracy is 0.375; the truth is 0.75.** There is no error or warning.

  For `stratum` the same split is refused loudly (unknown stratum). For `map_class` /
  `ref_class` it is silent. Round codes of 1e5 and above arise only from custom schemes,
  such as a transition to code 0, so this is a narrow input. It is the same mechanism,
  though, on the branch R2b's fix did not normalise. Fix: key a factor's levels through
  the same numeric normalisation (`accuracy_key` of `as.numeric(levels)` where every level
  parses as a number). The alternative is to normalise any character or factor value that
  parses as a whole number.

- **[severity: fragile]** R/dft_accuracy_size.R:294-307, 323. `s_h` and `ua` are aligned
  to `weights` by position. When the caller passes named `s_h`/`ua` in a different order
  from `weights`, the names are ignored, n from Eq. 13 is silently wrong, and line 323
  then overwrites the names so that the returned `s_h` looks aligned. Where both carry
  names, match them, or refuse a mismatch.

- **[severity: fragile]** R/dft_accuracy_labels.R:107. The contract permits `use` to be
  `NA`, but `read.csv()` of a partly filled `use` column gives `""`. The table is then
  refused with "got: ." (probed). This is R2's blank-vs-NA mechanism reaching the one
  column `accuracy_is_missing()` was not applied to. The failure is loud, not silent,
  but a label table that meets the contract is rejected. Fix: treat
  `accuracy_is_missing(labels$use)` as NA in both the check and estimate.R:128.

- **[severity: fragile]** R/dft_accuracy_estimate.R:245-247 -> R/dft_accuracy_size.R:297.
  A census stratum of one cell is legitimate: the sampler emits it, and the estimator
  accepts it. It gets `sd = NA` in `$stratum`. Fed to `dft_accuracy_size()` as the
  documented pilot path does, it is refused with "label another", which cannot be done
  because the stratum has one cell (probed: 1-cell stratum, `sd` NA, sizer errors). Its
  true S_h contribution is 0. Fix: set `sd` to 0 where `n == n_cells`.

- **[severity: fragile]** tests/testthat/test-dft_accuracy_sample.R:60-66. The block is
  labelled "brute force: the k-th cell of a stratum in cell order is which(v == h)[k]".
  It asserts only `p$cell %in% cells_h`, so a resolver that mapped a rank to the wrong
  cell *within* the right stratum would pass. The resolver is in fact correct: checked
  exactly against `which(v == code)[ranks]` at rows 1/3/600. The test simply cannot fail
  for the defect it names.

## Disposition (parent session, 2026-09-29)

All five non-sound rows are fixed, each with a test, and the mutation check turned every test red with its fix undone (scratch copy):
- #3: a blank `use` is NA. Test: "a blank `use` cell is NA".
- #6: `accuracy_key()` reads numeric-looking strings and factor levels back as numbers. Mutation: 2 failures.
- #20/#22: a census draws from the stream. Test: "a stratum tipped into a census … keeps its pilot ids". Mutation: 1 failure.
- #27: `s_h`/`ua` are matched to `weights` by keyed name. Test: "named s_h is matched to weights by name".
- #29: a census stratum reports sd 0. Mutation: 2 failures.

Two sound rows were also routed through `accuracy_key()`, so every site now uses one key: #26 (`$design$n_requested` names) and the new name match in the sizer.

#2 changed: `point_id` is now compared raw, not keyed, so "01" and "1" stay distinct ids.

**Termination:** the round-3 enumeration covers every identity derivation in the four files (29 sites), and none now sits outside `accuracy_key()` or a same-frame positional index. That ends the loop.

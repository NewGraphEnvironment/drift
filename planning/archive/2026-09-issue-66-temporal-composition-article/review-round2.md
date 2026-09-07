# Review round 2 — article tables block in `data-raw/break_class_groups.R` (#66, phase 2)

Reviewer: code-review subagent. Date: 2026-09-06.
Scope: the staged tree (`data-raw/break_class_groups.R`, `inst/extdata/temporal-composition/README.md`,
**and `data-raw/logs/break_class_groups/README.md`, which is staged but was not in `p2b.diff`**),
the four committed `summary_pixels.csv` / `summary_change.csv` inputs, the three written CSVs, and
round 1's three fixes.

Everything below was measured against the real data.

## Verdict on round 1's three fixes

| fix | verdict |
|---|---|
| 1. README range `-1.2` → `-1.3` | **correct**. Recomputed deltas (excl-Water minus incl-Water, sustained share): bulk +0.5982, necr +0.9023, lnth **−1.2536**, kotl +5.9997. `-1.3 to +6.0` rounds outward on both ends and therefore *contains* the true range; `-1.2` did not. |
| 2. `setequal()` + `anyDuplicated()` structural check in `agrees()` | **closes the hole it was written for**, and the positive control still works — see below. Two residual defects, findings 2 and 3. |
| 3. `article-bulk` trimmed from the shipped README | **regressed in the same commit** — see finding 1. |

## Findings

- **[bug]** `data-raw/logs/break_class_groups/README.md:26-31` — round 1's fix 3 removed the
  `article-bulk` claim from `inst/extdata/temporal-composition/README.md` and **the same commit
  added it to the sibling README**, together with a cross-reference that the trim made false:

  > "…and a third stage, `article-bulk`, writes that article's BULK figure data there. **Both are
  > described in that directory's own README.**"

  Measured: `grep -rn "article-bulk"` over the whole repo outside `planning/` returns **exactly one
  hit — this line**. The stage does not exist; `break_class_groups.R:54` accepts only
  `bulk|necr|lnth|kotl|summarize`, so anyone following the sentence gets the usage `stop()`. And
  `inst/extdata/temporal-composition/README.md` describes **one** thing, not both — the trim is
  what made the word "Both" wrong, so the fix created the contradiction rather than merely failing
  to reach it.

  Same class, still live in the **shipped** artifact: `inst/extdata/temporal-composition/README.md:3`
  says the article `vignettes/articles/temporal-composition.Rmd` "reads only from this directory",
  present tense. `vignettes/articles/` does not exist. `data-raw` and `planning` are in
  `.Rbuildignore`; `inst/extdata` is not — so that sentence installs with the package. Both resolve
  if phase 3 lands in this PR; only the `article-bulk` sentence needs a change if it does not.

- **[fragile]** `data-raw/break_class_groups.R:342-349, 356-360` — the structural arm added by fix 2
  is **a guard nobody has seen fail**, and the comment beside the positive control now overstates
  what that control covers. `agrees()` has two failure modes: `stop()` on a set mismatch and `FALSE`
  on a value mismatch. The positive control perturbs `n_cells[1]`, which leaves both key sets
  identical, so it exercises **only the value arm**:

  ```
  baseline agrees:            TRUE
  value-perturb control:      FALSE          <- proves the value arm
  drop a rollup row:          stop("category sets differ; only in summary_change.csv:
                                    (1 break_endpoint), only in the rollup: ()")
  ```

  The dropped-row case does now stop loudly — the round-1 hole is genuinely closed — but nothing in
  the script demonstrates it, and the comment above the control ("the comparator must be capable of
  returning FALSE… otherwise the check above reads green having compared nothing") reads as though
  the control covers the whole comparator. It does not cover the arm that was just added. The arm is
  reachable for the reason round 1 gave: `terra::crosstab(useNA = TRUE)` can put an NA-`category`
  row into `summary_change.csv`, and `cat_labels[NA + 1L]` makes it `NA_character_`. Measured, that
  case does stop:

  ```
  chg$category_label[2] <- NA
  -> stop("... only in summary_change.csv: (0 NA), only in the rollup: (0 flicker)")
  ```

  One line beside the existing control closes it, and it is measurably red with the round-1 code
  restored:

  ```r
  lab <- roll; lab$category[1] <- paste0(lab$category[1], "_x")
  if (!inherits(tryCatch(agrees(lab, chg), error = function(e) e), "error")) {
    stop("the set check does not fire on a category the other side lacks")
  }
  ```

- **[fragile]** `data-raw/break_class_groups.R:342-346` — the same `if` covers three conditions and
  emits one message written for only one of them. When the trigger is `anyDuplicated()` alone (sets
  equal, a key repeated), both `setdiff()`s are empty and the abort reads:

  ```
  category sets differ; only in summary_change.csv: (), only in the rollup: ()
  ```

  — a guard that fires correctly and then points nowhere, on the branch whose whole purpose is to
  catch the case `setequal()` cannot see. Not reachable from today's producers (`aggregate()` and
  `crosstab(long = TRUE)` both emit unique keys), so this is message quality on an unreachable
  branch, not a wrong result. Splitting the duplication test into its own `stop()` naming
  `key_roll[duplicated(key_roll)]` costs two lines.

## Mechanism behind all three of round 1's findings, and behind finding 1

Round 1's three findings and finding 1 above are one shape, not three: **a fact restated in prose
that no code reads.** The range `-1.2 to +6.0`, the `article-bulk` stage and the
`vignettes/articles/…Rmd` path are each a claim about an artifact, written by hand, in a document
whose only reader is a person. Nothing derives them, so nothing contradicts them when the artifact
moves — and the repair itself is prose, which is why fix 3 could remove the claim from one README
while the same commit added it to another.

The two habits the repo already names apply directly (`code-check.md`, "One fact derived twice" and
"Documents that share an ancestor corroborate nothing"): **derive the number from the artifact at
the moment you write it** — the `-1.3` is one `range(round(delta, 1))` away from being computed
rather than typed — and **when you find one instance stale, grep for the sentence, not the file**.
`grep -rn "article-bulk"` was one command and would have turned fix 3 from a trim into a sweep.

## Checked and clean (measured, not assumed)

Every item the request asked to be pressure-tested, with the measurement:

1. **The positive control still exercises the value path.** `bad$n_cells[1] + 1L` leaves both keys
   sets identical, so the structural check passes and the value compare returns `FALSE`. Measured
   `FALSE`. Confirmed the structural `stop()` does **not** shadow it.

2. **`anyDuplicated()` on a data.frame column.** Both arguments are plain character vectors
   (`paste()` output), not data frames, so the data-frame method (which compares whole rows) is
   never dispatched. Returns `0` for both in all four groups; `0` is `FALSE` in the `||` chain.
   `roll` comes from `aggregate()` and `chg` from `crosstab(long = TRUE)`, so duplicates are
   structurally impossible today.

3. **Separator collision in the keys.** `paste()`'s default `sep = " "` against `changed` ∈ {0,1}
   and `category` ∈ {`stable`, `flicker`, `break_sustained`, `break_endpoint`} — no category
   contains a space, so `"0 flicker"` and `"1 flicker"` cannot collide, and no other spelling of a
   `(changed, category)` pair produces the same string. Enumerated all 5 keys per group in all 4
   groups: 20 keys, 0 collisions. The `\r` separator in `pair` is likewise safe (no class name
   contains `\r`), and it is never written out.

4. **`aggregate()` returns `changed` as `logical`, not `factor`.** Measured `class(roll$changed) ==
   "logical"`, so `as.integer()` gives `0/1` and not a factor's `1/2`. Had it been a factor the
   whole set check would abort on correct data — it does not.

5. **Is the conservation check circular?** No. It compares the **post-aggregation** total against a
   fresh read of the **pre-aggregation** file — two different states of the same data, which is what
   makes a silently-dropped `aggregate()` group visible. It is correctly scoped to that one claim,
   and the script does *not* rely on it for the `summary_change.csv` comparison (that is `agrees()`,
   against a file built by a different computation). Measured delta 0 in all four groups
   (4,108,972 / 4,183,814 / 1,600,176 / 6,937,760).

6. **Other subject-derived comparison sets in the added block.** Swept every comparison:
   `identical(sort(unique(per_class$group)), sort(names(groups)))` — expected side is the literal
   `groups`; `identical(got, chg_cats)` — expected side is the literal `chg_cats`, and it is per
   group, so a category vanishing in one group cannot be masked by another; `nrow(treeloss) == 2L *
   length(groups) * length(chg_cats)` — an arithmetic expectation, measured 24. **No other
   subject-derived set.** The one that was subject-derived is the one fix 2 repaired.

7. **`ave(a$n_cells, pair, FUN = sum)`.** `ave()` coerces the grouping through `interaction()`,
   which factors a character vector; the partition is identical to the `(from_class, to_class)`
   partition and is scoped inside the per-group `lapply`. Measured: `pct_of_pair` sums to exactly
   100 for **all 221** `(group, from, to)` pairs, min = max = 100. No zero denominators.

8. **`ave(a$area_ha, a$group, FUN = sum)` in `pct_of_set`.** Measured: sums to exactly 100 for all
   8 `(group, class_set)` combinations. `a$group` is an exact column name, so no `$` partial match.

9. **Every numeric claim in the shipped README.** `-1.3 to +6.0` recomputed from
   `summary_treeloss_temporal.csv` (finding table above) — correct and containing. "matching the
   definition the published `gross_loss_ha` uses" — **verified against an independent source**:
   `inst/notes/temporal-qa-disturbance.md:43` records that `gross_loss_ha` *includes* `Trees → Water`,
   and `trees_to_non_trees_excl_clouds` excludes only `Clouds`, so Water is counted as loss in both.
   The claim is right. "1 ha sieve and a sub-basin clip (drift#67)" matches the same note. "refuses
   to write any of these files unless…" — verified: all five guards and both `agrees()` loops run
   before the first `write.csv()`. "column subset of the same in-memory object" — verified by
   `all.equal(article, logs[names(article)])` → `TRUE`.

10. **`temporal_category()` reproduces `summary_change.csv`, and that is not circular.** The
    `%in% yr_endpoint` composition and `summary_change.csv`'s `cat_fun()` on
    `pmin(n_before, n_after)` are two different computations; they agree cell-for-cell in all four
    groups (`agrees()` TRUE on integers). No row in any `summary_pixels.csv` has
    `from == to & status == "break"` or `from != to & status == "stable"`, so the `changed` axis
    cannot straddle a category.

11. **Zero-length / empty behaviour.** Measured: on a 0-row `roll`, `bad$n_cells[1] <- … + 1L`
    **errors** (`replacement has 1 row, data has 0`) and `aggregate()` errors first
    (`no rows to aggregate`). The 0-row treeloss subset likewise errors rather than writing a
    header-only CSV that would read back all-`logical`. Every empty path is loud.

12. **Git churn / determinism.** Re-ran the whole block independently and wrote to a temp directory:
    `cmp` reports both `summary_class_temporal.csv` and `summary_treeloss_temporal.csv`
    **byte-identical** to the committed copies. `pct_of_pair` / `pct_of_set` at 15 significant
    digits come from deterministic IEEE arithmetic on integer inputs. All four new files are tracked
    and none is gitignored (`git check-ignore` clean, `git ls-files --error-unmatch` OK on all four).

13. **`aggregate()` NA-group hazard.** Confirmed the behaviour exists (a `by` column with `NA` drops
    the row silently) and confirmed it is unreachable here: 0 `NA` in `from_class` / `to_class`
    across all four files, `group` is a literal, `category` is `stop()`-guarded, and the class
    vocabulary contains no token `read.csv` would coerce to `NA`. The conservation check is the
    tripwire and it passes at delta 0.

14. **Locale.** `order()` and `sort()` on the nine class names and four category labels sort
    identically under `C` and `en_US.UTF-8`, so the committed byte order is locale-invariant for the
    current vocabulary.

/Users/airvine/Projects/repo/drift/planning/active/review-round2.md

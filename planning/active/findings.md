# Findings — Accuracy assessment for change maps (#81)

## Issue context

## Problem

drift produces land-cover change maps (`dft_rast_transition()`, `dft_rast_break_class()`, `dft_transition_vectors()`), but it has no way to say **how right they are**. Every area it reports is the mapped area, and mapped area is a biased estimator whenever the map has errors. For a change map it is usually badly biased, because a single wrong label on either date manufactures a transition.

The standard remedy is a stratified sample of reference labels and estimators that correct area for the measured error. That method is generic to any classified map, so it belongs in drift, not in each driver. floodplains#93 is the first consumer: NECR floodplain change, fire/harvest attribution, and wetland change.

## Scope

Follow Olofsson et al. 2014, *Good practices for estimating area and assessing accuracy of land change* (Remote Sensing of Environment 148:42–57), and Stehman's stratified estimators it builds on.

1. **Stratified sample design.** Given a strata raster or polygons (the map classes, or caller-defined strata such as "change attributed / unattributed / stable"), draw random **points** per stratum. Sample points rather than patches: patch sampling over-weights large patches, and area is the quantity being estimated.
   - Allocation can be equal per stratum or a caller-supplied `n`.
   - The output is a reproducible sample: seeded, with a stable point id, the stratum, and each stratum's mapped area (weights) recorded alongside.
   - A helper to size the sample from a pilot's variance, or from target user's accuracies.
2. **Accuracy and error-adjusted area from labels.** Given the sample with its reference label and the stratum weights, return:
   - an area-weighted error matrix
   - overall, user's and producer's accuracy, with standard errors
   - **error-adjusted area per class, with confidence intervals**
3. **A tidy label contract.** Document the columns a reference-label table must carry (point id, stratum, map class, reference class, and optionally confidence and reviewer), so any review tool can feed (2). drift does not store labels; the caller does.
4. **Train and test separation.** If labels are ever reused to train a classifier, the accuracy sample must be held out. Provide a documented split, or at minimum a flag that makes the estimator refuse training points.

Out of scope: the review UI (drift#79 covers the imagery and the map layers), and choosing strata or storing labels, which are the driver's job.

## Acceptance

- Estimators reproduce the worked example in Olofsson et al. 2014 (the published error matrix and its error-adjusted areas with CIs) to the published precision. That is the external reference; a self-generated fixture would only test the code against itself.
- A must-fail test: dropping the stratum weights (unweighted accuracy) gives a different, wrong answer on the paper's example.
- Sample draws are reproducible from a seed and stable across terra versions for the same inputs.

Relates: floodplains#93, drift#79

## Plan-gate decisions (2026-09-28)

- Reference values come from the PDFs. The user is adding Olofsson 2014 and Stehman 2014 to Zotero; neither was in the library (checked zotero.sqlite read-only). The Zotero MCP fails on missing `ZOTERO_LIBRARY_ID` / `ZOTERO_API_KEY`.
- The estimator takes the general Stehman 2014 form (strata may differ from map classes), because floodplains#93 strata are not map classes.
- No existing implementation in the org: swept the exports of 19 NGE packages plus `gh search code org:NewGraphEnvironment olofsson`. `mapaccuracy`, `survey` and `sampling` are not installed and not needed.

## Existing implementations (reported by a soul session, 2026-09-28)

My org-only sweep missed these. Both are outside NewGraphEnvironment.

- **`mapaccuracy`** (CRAN 0.1.2, 2024-04-03, Hugo Costa, MIT). Imports only `stats`. It implements Olofsson 2014 and Stehman 2014 (`olofsson()`, `stehman2014()`), and its docs check it against published examples from Olofsson 2013 (two), Olofsson 2014 and Stehman 2014. Its docs record a confirmed typo in Olofsson 2013 (a CI lower bound).
- **`mapac`** (Dirk Pflugmacher, HU Berlin GitLab, v0.31, 91 commits 2020–2026). Not on CRAN. It covers stratified and Stehman-2014 estimators, allocation, and report tables. Its tests are thin: one file, which checks only Stehman 2014.

**The Olofsson 2014 PDF is in the NGE Zotero group** as `olofsson_etal2014Goodpractices`; its md5 was verified against the published PDF. Run through `mapac`, Tables 8–9 match on:
- all four areas with their CIs (deforestation 21,158 ± 6,158 ha)
- all four user's accuracies
- OA 0.947 ± 0.018, which the paper prints rounded as 0.95 ± 0.02

**Two producer's-accuracy CIs in the paper look like typos.** Forest gain is printed ±0.23 but Eq. 7 gives ±0.254; stable non-forest is printed ±0.01 but Eq. 7 gives ±0.018. The soul session recomputed both independently of `mapac`, and no erratum is registered. So those two pins take the Eq. 7 value, cite the discrepancy, and do not assert the printed figure.

Stehman 2014 and Olofsson 2013 are paywalled and not yet saved.

## Olofsson 2014 reference values (read from the PDF, 2026-09-29)

The values are transcribed into `tests/testthat/helper-accuracy.R` with page and table. From Tables 8–9 (p. 55) and §5.2 (p. 54), through `mapaccuracy::stehman2014()`:
- Areas match to the hectare (21,157.8 / 11,686.2 / 285,769.9 / 581,386.2 against the printed 21,158 / 11,686 / 285,770 / 581,386).
- The error matrix matches Table 9 to 4 dp. The package returns zero cells as NA.
- UA, the two PA values that agree with the text, and OA (0.9465 ± 0.0185) all match at 2 dp.

**The half-widths depend on two choices.** Stehman's FPC and `qnorm(.975)` versus the paper's no-FPC and 1.96 move the half-widths by up to 1.1 ha: stable non-forest is 16,280.9 against the printed 16,282, while no-FPC with 1.96 gives 16,281.7. So the area half-width pin uses an absolute tolerance of 1.5 ha, and the proportion pins use 0.005 (the half-step at 2 dp).

**Three printed values contradict the paper's own equations:**
- PA half-width, forest gain: printed 0.23, Eq. 7 gives 0.254.
- PA half-width, stable non-forest: printed 0.01, Eq. 7 gives 0.018.
- "S(Â₁) … = 34,097 pixels": 1.96 × 34,097 = 66,830, not the 68,418 printed next to it. 68,418 / 1.96 = 34,907.

**Sample size:** Eq. 13 with Table 5's W and U and a target SE(O) of 0.01 gives (0.25312 / 0.01)² = 640.7, so n = 641. The Equal (160) and Prop (13 / 10 / 205 / 413, by rounding n·W) columns reproduce. **Alloc1–3 do not:** the stated rule (100 per change stratum, remainder proportional to the stable classes) gives 146 / 295, where the table has 149 / 292. They are not asserted.

**`mapaccuracy` internals worth knowing:**
- `stehman2014()` matches stratum names by regex (`grep(paste0("^", nm, "$"), ...)`). drift passes internal ids `s1..sH` to it.
- Its `order =` default is `sort(union(r, m))` on character, so "10" sorts before "2". drift passes the order explicitly.
- It only *warns* on a stratum with one observation.
- It applies the FPC in eq. 25 and eq. 28.

## Errors Encountered

| Error | Resolution |
|-------|------------|

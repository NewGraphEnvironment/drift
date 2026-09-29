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

## Errors Encountered

| Error | Resolution |
|-------|------------|

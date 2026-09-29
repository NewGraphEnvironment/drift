## Outcome

Added the `dft_accuracy_*` family (#81): stratified random point sampling from any strata raster, a reference-label contract, error-adjusted area and accuracy with confidence intervals, and sample sizing from a pilot, following Olofsson et al. 2014 and Stehman 2014.

- **Estimator:** wraps `mapaccuracy::stehman2014()`. A soul session surfaced that CRAN package, and the user chose it over writing a second implementation. drift owns the sampler, the contract and the train guard, CIs in ha, and the per-stratum table the sizer needs.
- **Reference values:** the tests reproduce Olofsson Tables 8–9 through `dft_accuracy_estimate()`. Three printed values in the paper contradict its own equations; the tests pin the equation values and record the printed ones (`tests/testthat/helper-accuracy.R`).
- **Plan review:** it caught that `terra::freq()` reports labels while `readValues()` reports codes on factor strata, so the sampler's first design could not have joined its two passes.
- **Code-check:** three rounds, twice finding a defect inside the previous fix. All shared one mechanism: the same class/stratum/point identity derived separately at each use site. The loop ended by enumerating all 29 identity sites and routing every one through `accuracy_key()`, with each fix mutation-checked.
- **Found on the way:** `dft_rast_classify()` mutates its input raster in place (#89).

## Measurement

- **Olofsson 2014 through the wrapper:** areas match to the ha (21,157.8 / 11,686.2 / 285,769.9 / 581,386.2), and Table 9 matches to 4 dp. Area half-widths are within 1.1 ha; Stehman's FPC and exact z against the paper's 1.96 without FPC account for the difference. With equal stratum weights, deforestation comes out at 200,748 ha instead of 21,158.
- **Census oracle** (bundled tiles, 2017 map vs 2023 reference, 300 draws):
  - Unbiased throughout: |bias z| < 2.
  - Map-class strata at n = 25: Water's 95% CI covered **61%** (SE ratio 0.76), because 98 of the 7,127 map-Trees cells (1.4%) are reference Water and most draws see none. Coverage rose to 83% at n = 75 and 89% at n = 150. This is the Wald interval's small-sample weakness, now documented on the estimator, not an estimator bug.
  - Changed/stable strata at n = 60: coverage 0.91–0.96.
- **`stehman2014()` runtime** at 1,000 points: 0.33 s / 2.0 s / 13.0 s at 20 / 40 / 80 classes, about k^2.5. Not filed upstream; documented.
- **BULK scale** (169,248,352 cells, 4.1M non-NA, 64 GB machine):
  - `dft_accuracy_sample()`: 3.3 s (1.7 s per chunked pass), peak RSS 0.95 GiB.
  - The 63-stratum transition map with n = 30 and 10 censuses: 3.0 s. The pipeline peaks at 4.63 GiB, dominated by the in-memory transition raster.
  - The estimator on those 1,677 points: 10.8 s.
- **Suite:** 1289 pass / 15 skip. R CMD check: 0 errors. It has 1 WARNING, non-ASCII in `R/dft_stac_fetch.R`, which is already on main and untouched here.

## Evidence

Review records: `review-plan.md`, `review-round*.md` in this directory. The BULK run logs were in the session scratchpad (`bulk/bulk_run*.log`, `bulk/rss*.log`) and are not committed; the numbers above are their summary.

Closed by: PR for branch `81-accuracy-assessment-for-change-maps-stra`

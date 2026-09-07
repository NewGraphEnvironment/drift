## Reconciliation: drift's change patches against the published transition layer

|group | drift_patches| drift_ha| pub_patches| pub_ha| repro_patches| repro_ha| sieve_ha| clip_ha| n_classes| n_classes_differ| max_abs_d_ha|reproduced |
|:-----|-------------:|--------:|-----------:|------:|-------------:|--------:|--------:|-------:|---------:|----------------:|------------:|:----------|
|bulk  |         21701|   4625.0|        7161| 3627.2|          7161|   3627.2|    985.3|    12.5|        53|                0|            0|TRUE       |
|necr  |         21990|   5779.4|        5692| 4712.6|          5692|   4712.6|   1049.4|    17.4|        44|                0|            0|TRUE       |
|lnth  |         12434|   1629.7|        2753| 1148.5|          2753|   1148.5|    477.7|     3.5|        41|                0|            0|TRUE       |
|kotl  |         17042|   3537.8|        4929| 2757.8|          4929|   2757.8|    649.5|   130.5|        46|                0|            0|TRUE       |

## Discriminating sample: disturbance years whose reachable break years are sustained

|group | fire_patches_full| fire_patches_partial| fire_ha_disc| fire_events_disc| harv_patches_full| harv_patches_partial| harv_ha_disc|
|:-----|-----------------:|--------------------:|------------:|----------------:|-----------------:|--------------------:|------------:|
|bulk  |                 0|                    0|          0.0|                0|                52|                   36|        303.0|
|necr  |                 0|                   87|        457.4|                2|                79|                   85|        583.6|
|lnth  |                 0|                    0|          0.0|                0|                12|                    1|         26.6|
|kotl  |                11|                   52|         20.0|                3|                32|                   11|        172.5|

## Agreement at lag 0 or +1, discriminating disturbance years only (full + partial)

|group |source  | n_tagged| n_with_break| n_lag01| pct_lag01_of_break| pct_lag01_of_tagged|
|:-----|:-------|--------:|------------:|-------:|------------------:|-------------------:|
|bulk  |fire    |        0|            0|       0|                 NA|                  NA|
|bulk  |harvest |       88|           70|      55|               78.6|                62.5|
|necr  |fire    |       87|           77|      68|               88.3|                78.2|
|necr  |harvest |      164|          129|      91|               70.5|                55.5|
|lnth  |fire    |        0|            0|       0|                 NA|                  NA|
|lnth  |harvest |       13|           12|       8|               66.7|                61.5|
|kotl  |fire    |       63|           46|      38|               82.6|                60.3|
|kotl  |harvest |       43|           39|      26|               66.7|                60.5|

## Flicker: harvest-touching against the untagged residual, by geometric stratum

|stratum   |population        | n_patches| area_ha_unclipped| area_ha_eval| flicker_frac_area_wtd| break_frac_area_wtd|group |
|:---------|:-----------------|---------:|-----------------:|------------:|---------------------:|-------------------:|:-----|
|all       |harvest_touching  |       120|             525.3|        525.3|                 0.207|               0.793|bulk  |
|all       |fire_touching     |        35|              69.9|         69.9|                 0.143|               0.857|bulk  |
|all       |untagged_residual |      7008|            3071.2|       3068.4|                 0.475|               0.525|bulk  |
|sliver    |harvest_touching  |        44|               4.5|          4.5|                 0.362|               0.638|bulk  |
|sliver    |fire_touching     |        19|               1.2|          1.2|                 0.554|               0.446|bulk  |
|sliver    |untagged_residual |      5700|             412.8|        412.6|                 0.634|               0.366|bulk  |
|wider     |harvest_touching  |        76|             520.8|        520.8|                 0.205|               0.795|bulk  |
|wider     |fire_touching     |        16|              68.7|         68.7|                 0.136|               0.864|bulk  |
|wider     |untagged_residual |      1308|            2658.4|       2655.8|                 0.450|               0.550|bulk  |
|ge_0.5_ha |harvest_touching  |        70|             518.8|        518.8|                 0.204|               0.796|bulk  |
|ge_0.5_ha |fire_touching     |        15|              68.2|         68.2|                 0.130|               0.870|bulk  |
|ge_0.5_ha |untagged_residual |      1030|            2625.9|       2623.6|                 0.441|               0.559|bulk  |
|all       |harvest_touching  |       193|             719.9|        719.9|                 0.280|               0.720|necr  |
|all       |fire_touching     |       189|             589.4|        582.5|                 0.201|               0.799|necr  |
|all       |untagged_residual |      5323|            3509.7|       3508.6|                 0.429|               0.571|necr  |
|sliver    |harvest_touching  |        49|               3.2|          3.2|                 0.545|               0.455|necr  |
|sliver    |fire_touching     |        98|               6.1|          6.1|                 0.557|               0.443|necr  |
|sliver    |untagged_residual |      4106|             290.3|        289.2|                 0.615|               0.385|necr  |
|wider     |harvest_touching  |       144|             716.7|        716.7|                 0.279|               0.721|necr  |
|wider     |fire_touching     |        91|             583.3|        576.4|                 0.197|               0.803|necr  |
|wider     |untagged_residual |      1217|            3219.4|       3219.4|                 0.412|               0.588|necr  |
|ge_0.5_ha |harvest_touching  |       135|             713.7|        713.7|                 0.278|               0.722|necr  |
|ge_0.5_ha |fire_touching     |        85|             581.6|        574.6|                 0.196|               0.804|necr  |
|ge_0.5_ha |untagged_residual |      1012|            3188.8|       3187.7|                 0.407|               0.593|necr  |
|all       |harvest_touching  |        15|              30.3|         30.3|                 0.078|               0.922|lnth  |
|all       |fire_touching     |         7|               9.0|          9.0|                 0.404|               0.596|lnth  |
|all       |untagged_residual |      2731|            1112.1|       1109.2|                 0.495|               0.505|lnth  |
|sliver    |harvest_touching  |         3|               0.7|          0.7|                 0.521|               0.479|lnth  |
|sliver    |fire_touching     |         4|               0.1|          0.1|                 1.000|               0.000|lnth  |
|sliver    |untagged_residual |      2186|             146.4|        146.4|                 0.631|               0.369|lnth  |
|wider     |harvest_touching  |        12|              29.6|         29.6|                 0.068|               0.932|lnth  |
|wider     |fire_touching     |         3|               8.9|          8.9|                 0.396|               0.604|lnth  |
|wider     |untagged_residual |       545|             965.7|        962.8|                 0.475|               0.525|lnth  |
|ge_0.5_ha |harvest_touching  |        13|              30.1|         30.1|                 0.073|               0.927|lnth  |
|ge_0.5_ha |fire_touching     |         3|               8.9|          8.9|                 0.396|               0.604|lnth  |
|ge_0.5_ha |untagged_residual |       411|             935.2|        932.3|                 0.469|               0.531|lnth  |
|all       |harvest_touching  |        44|             172.8|        172.8|                 0.074|               0.926|kotl  |
|all       |fire_touching     |        91|              28.8|         28.8|                 0.336|               0.664|kotl  |
|all       |untagged_residual |      4794|            2567.4|       2556.2|                 0.453|               0.547|kotl  |
|sliver    |harvest_touching  |        15|               1.6|          1.6|                 0.297|               0.703|kotl  |
|sliver    |fire_touching     |        72|               7.1|          7.1|                 0.432|               0.568|kotl  |
|sliver    |untagged_residual |      4006|             336.0|        334.6|                 0.543|               0.457|kotl  |
|wider     |harvest_touching  |        29|             171.2|        171.2|                 0.072|               0.928|kotl  |
|wider     |fire_touching     |        19|              21.7|         21.7|                 0.305|               0.695|kotl  |
|wider     |untagged_residual |       788|            2231.4|       2221.6|                 0.440|               0.560|kotl  |
|ge_0.5_ha |harvest_touching  |        25|             169.8|        169.8|                 0.070|               0.930|kotl  |
|ge_0.5_ha |fire_touching     |        15|              21.4|         21.4|                 0.296|               0.704|kotl  |
|ge_0.5_ha |untagged_residual |       673|            2253.4|       2242.9|                 0.435|               0.565|kotl  |

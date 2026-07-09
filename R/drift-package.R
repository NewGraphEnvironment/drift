#' @keywords internal
"_PACKAGE"

# NSE symbols: `eo:cloud_cover` in rstac::ext_filter() CQL2 (dft_stac_cube);
# `.data` is the rlang pronoun used in dplyr pipelines (dft_rast_classify)
utils::globalVariables(c("eo:cloud_cover", ".data"))

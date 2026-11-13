#' @keywords internal
"_PACKAGE"

# NSE symbols: `eo:cloud_cover` in rstac::ext_filter() CQL2 (stac_cube_items(),
# applied only for a source whose items carry it);
# `.data` is the rlang pronoun used in dplyr pipelines (dft_rast_classify)
utils::globalVariables(c("eo:cloud_cover", ".data"))

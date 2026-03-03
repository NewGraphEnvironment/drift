# Package setup tracking
# Run these interactively — they are NOT idempotent

# 1. Package scaffold
usethis::create_package(".")
usethis::use_mit_license("New Graph Environment Ltd.")

# 2. Testing
usethis::use_testthat(edition = 3)

# 3. Documentation site
usethis::use_pkgdown()
usethis::use_github_action("pkgdown")

# 4. Dev directory (self-referential)
usethis::use_directory("dev")
usethis::use_directory("data-raw")

# 5. Hex sticker (reads package name from DESCRIPTION — zero edits needed)
source("data-raw/make_hexsticker.R")

# 6. Dependencies — Imports
usethis::use_package("rstac")
usethis::use_package("terra")
usethis::use_package("sf")
usethis::use_package("dplyr")
usethis::use_package("tibble")
usethis::use_package("rappdirs")

# 6b. Dependencies — Suggests
usethis::use_package("tmap", type = "Suggests")
usethis::use_package("mapgl", type = "Suggests")
usethis::use_package("gq", type = "Suggests")
usethis::use_package("ggplot2", type = "Suggests")
usethis::use_package("tidyterra", type = "Suggests")
usethis::use_package("gt", type = "Suggests")
usethis::use_package("DT", type = "Suggests")
usethis::use_package("flooded", type = "Suggests")
usethis::use_package("testthat", type = "Suggests", min_version = "3.0.0")
usethis::use_package("knitr", type = "Suggests")
usethis::use_package("rmarkdown", type = "Suggests")

# 7. Build
devtools::document()
devtools::test()
devtools::check()

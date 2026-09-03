test_that("dft_cache_path returns a writable directory", {
  tmp <- tempfile("drift_test_cache")
  path <- dft_cache_path(cache_dir = tmp)
  expect_true(dir.exists(path))
  expect_equal(path, tmp)
  unlink(tmp, recursive = TRUE)
})

test_that("dft_cache_path uses default when NULL", {
  path <- dft_cache_path()
  expect_true(dir.exists(path))
  expect_match(path, "drift")
})

test_that("dft_cache_clear removes files", {
  tmp <- tempfile("drift_test_cache")
  dir.create(tmp, recursive = TRUE)
  writeLines("test", file.path(tmp, "test.txt"))
  expect_equal(length(list.files(tmp)), 1)

  n <- dft_cache_clear(cache_dir = tmp)
  expect_equal(n, 1L)
  expect_false(dir.exists(tmp))
})

test_that("dft_cache_clear returns 0 for empty cache", {
  tmp <- tempfile("drift_test_cache_empty")
  n <- dft_cache_clear(cache_dir = tmp)
  expect_equal(n, 0L)
})

test_that("dft_cache_info returns expected structure", {
  tmp <- tempfile("drift_test_cache")
  dir.create(tmp, recursive = TRUE)
  writeLines(paste(rep("x", 1000), collapse = ""), file.path(tmp, "test.txt"))

  info <- dft_cache_info(cache_dir = tmp)
  expect_type(info, "list")
  # gained n_files_superseded / size_mb_superseded in #48 — a key change orphans
  # entries permanently, and without a count they are invisible disk use
  expect_named(info, c("path", "n_files", "size_mb",
                       "n_files_superseded", "size_mb_superseded"))
  expect_equal(info$n_files, 1)
  expect_true(file.size(file.path(tmp, "test.txt")) > 0)

  unlink(tmp, recursive = TRUE)
})


# --- #48: cache-scheme generations -----------------------------------------

test_that("dft_cache_info reports superseded-scheme entries separately", {
  tmp <- tempfile("drift_scheme_")
  cur <- drift:::cache_scheme_dir(tmp, "io-lulc")
  old <- file.path(tmp, "io-lulc")            # the pre-scheme layout
  dir.create(cur, recursive = TRUE); dir.create(old, recursive = TRUE)
  writeLines("current", file.path(cur, "a.nc"))
  writeLines("orphaned", file.path(old, "b.nc"))

  info <- dft_cache_info(cache_dir = tmp)
  expect_named(info, c("path", "n_files", "size_mb",
                       "n_files_superseded", "size_mb_superseded"))
  expect_equal(info$n_files, 2)              # everything under the base
  expect_equal(info$n_files_superseded, 1)   # only the orphaned generation
  unlink(tmp, recursive = TRUE)
})

test_that("dft_cache_clear(scheme=) targets the right generation", {
  seed <- function() {
    tmp <- tempfile("drift_scheme_clear_")
    cur <- drift:::cache_scheme_dir(tmp, "io-lulc")
    old <- file.path(tmp, "io-lulc")
    dir.create(cur, recursive = TRUE); dir.create(old, recursive = TRUE)
    writeLines("x", file.path(cur, "a.nc"))
    writeLines("y", file.path(old, "b.nc"))
    list(tmp = tmp, cur = cur, old = old)
  }

  # superseded: reclaims the orphans, leaves usable entries alone. This is the
  # path that makes an orphaned generation recoverable disk rather than
  # invisible litter.
  s <- seed()
  expect_equal(dft_cache_clear(cache_dir = s$tmp, scheme = "superseded"), 1L)
  expect_true(file.exists(file.path(s$cur, "a.nc")))
  expect_false(dir.exists(s$old))
  unlink(s$tmp, recursive = TRUE)

  # current: the mirror
  s <- seed()
  expect_equal(dft_cache_clear(cache_dir = s$tmp, scheme = "current"), 1L)
  expect_true(file.exists(file.path(s$old, "b.nc")))
  unlink(s$tmp, recursive = TRUE)

  # all (the default) keeps the pre-scheme behaviour: everything goes
  s <- seed()
  expect_equal(dft_cache_clear(cache_dir = s$tmp), 2L)
  expect_false(dir.exists(s$tmp))
})

test_that("dft_cache_clear(source=) still resolves under the current scheme", {
  # The regression the scheme segment invites: if dft_cache_clear() were left
  # building <base>/<source> it would point at the SUPERSEDED generation and
  # report success having deleted nothing usable — and it is the documented
  # recovery lever.
  tmp <- tempfile("drift_scheme_src_")
  cur <- drift:::cache_scheme_dir(tmp, "io-lulc")
  dir.create(cur, recursive = TRUE)
  writeLines("x", file.path(cur, "a.nc"))
  expect_equal(dft_cache_clear(cache_dir = tmp, source = "io-lulc",
                               scheme = "current"), 1L)
  expect_false(file.exists(file.path(cur, "a.nc")))
  unlink(tmp, recursive = TRUE)
})

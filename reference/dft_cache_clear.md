# Clear the drift tile cache

Removes all cached files from the drift cache directory.

## Usage

``` r
dft_cache_clear(
  cache_dir = NULL,
  source = NULL,
  scheme = c("all", "current", "superseded")
)
```

## Arguments

- cache_dir:

  Character. Override the default cache location.

- source:

  Character. If provided, only clear files for this source. Otherwise
  clears everything.

- scheme:

  Character. Which cache-scheme generations to clear (#48). `"all"`
  (default) clears everything, matching the behaviour before schemes
  existed. `"current"` clears only entries the running version can
  actually use. `"superseded"` clears only entries left behind by an
  older scheme — the reclaim path for caches orphaned by a key change.

## Value

Invisibly returns the number of files removed.

## Details

This includes any `*.tmp*` orphans. Cache entries are published
atomically — written to a temp file beside the target and renamed into
place only on a complete, validated write — so a process killed by
`SIGKILL`, an OOM-kill or power loss can strand a temp file that R's own
cleanup never ran for. Such a file is disk garbage but never a
correctness problem: the cache gate matches only the canonical name, so
an orphan can never be served as a hit.

Nothing sweeps them automatically during a fetch, deliberately: a
multi-hour cube write is precisely the in-flight temp such a sweep would
delete.

## Examples

``` r
if (FALSE) { # \dontrun{
dft_cache_clear()
dft_cache_clear(scheme = "superseded") # reclaim orphaned generations only
} # }
```

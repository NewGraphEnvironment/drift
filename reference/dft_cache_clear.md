# Clear the drift tile cache

Removes all cached files from the drift cache directory.

## Usage

``` r
dft_cache_clear(cache_dir = NULL, source = NULL)
```

## Arguments

- cache_dir:

  Character. Override the default cache location.

- source:

  Character. If provided, only clear files for this source. Otherwise
  clears everything.

## Value

Invisibly returns the number of files removed.

## Examples

``` r
if (FALSE) { # \dontrun{
dft_cache_clear()
} # }
```

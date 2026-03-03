# Get drift cache directory path

Returns the path to the drift tile cache directory. Creates it if it
doesn't exist.

## Usage

``` r
dft_cache_path(cache_dir = NULL)
```

## Arguments

- cache_dir:

  Character. Override the default cache location. If NULL, uses
  `rappdirs::user_cache_dir("drift")`.

## Value

Character path to the cache directory.

## Examples

``` r
dft_cache_path()
#> [1] "~/.cache/drift"
```

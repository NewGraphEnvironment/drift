# Show drift cache info

Reports the cache location and size.

## Usage

``` r
dft_cache_info(cache_dir = NULL)
```

## Arguments

- cache_dir:

  Character. Override the default cache location.

## Value

A list with `path` (the base), `n_files` and `size_mb` (everything under
it), and `n_files_superseded` / `size_mb_superseded` (the subset
belonging to superseded schemes, which can never be served).

## Details

Entries left behind by an older cache scheme are reported separately
(#48). A key change orphans them — they can never be served again — but
nothing deletes them automatically, so without a count they are simply
invisible disk use that no one can attribute. Reclaim with
`dft_cache_clear(scheme = "superseded")`.

## Examples

``` r
dft_cache_info()
#> $path
#> [1] "~/.cache/drift"
#> 
#> $n_files
#> [1] 0
#> 
#> $size_mb
#> [1] 0
#> 
#> $n_files_superseded
#> [1] 0
#> 
#> $size_mb_superseded
#> [1] 0
#> 
```

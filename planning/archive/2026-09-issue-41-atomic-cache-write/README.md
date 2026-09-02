# #41 — interrupted fetch left a corrupt cache that was trusted as a hit

**Outcome:** cache entries in both `dft_stac_fetch()` and `dft_stac_cube()` are now published
atomically (temp in the same directory, renamed into place only after a complete, validated write)
and validated before they are served. Closed by PR for issue #41; released as v0.11.0.

The issue named `dft_stac_fetch()`. Two further instances of the same defect were found and fixed
in the same PR: `dft_stac_cube()` had the identical presence-only gate and direct write (and is the
more expensive cache to lose — a multi-hour Sentinel-2 stream), and `force = TRUE` truncated the
canonical file *before* writing, so an interrupted forced re-fetch destroyed a cache that had been
perfectly valid — the exact situation in which someone reaches for `force`.

## Measurement

The design turned on a taxonomy that had to be measured rather than reasoned from the traceback.
**Three** distinct damage shapes, not one, and no single cheap check sees all of them:

| shape | `terra::rast()` | geometry | pixel read |
|---|---|---|---|
| tail-truncated / zero-byte | errors | — | — |
| broken geotransform (the reported shape) | succeeds + warns | degenerate | `mask()` fails |
| content-damaged, size preserved | succeeds silently | valid | warns |

`tryCatch(rast())` alone passes rows 2 and 3; a geometry check alone passes row 3 — that file opens
clean, has correct dim/res/CRS and even masks successfully, and its values come back looking
plausible (`nNA = 0`). Damage there is visible *only* in the warning raised during the read.

Probe cost on a 13 MB entry: **0.08 s** for one row against **2.4 s** for `minmax(compute = TRUE)`,
which is what made a read probe affordable at all. On the cube path it is free and strictly
stronger — `cube_check_nonempty()` already scans every pixel, so a warning handler around the
existing call buys a whole-file check at no added cost.

Scan of the live cache: **168 entries, 0 corrupt** — so no cache-key break was needed, unlike #51.
The same 168 (123 `.nc`, 45 `.tif`) served as the false-refusal control: the new validator rejects
none of them, at 41 ms each.

## Wrong turns, kept because they are the evidence

- **A Plan review's three empirical premises were probed rather than adopted; two were refuted.**
  Truncated `.tif` does *not* open with row 1 readable (terra writes the IFD at the end, so
  truncation always kills the open) — which removed the whole argument for restructuring the probe.
  Its NC3 claim was also wrong: terra writes NC4/HDF5. Its two *structural* points were right and
  were adopted: validate the temp before renaming (the only validation `force = TRUE` reaches, and
  it covers the miss branch where the reported traceback actually died), and fold the cube's probe
  into the scan already being paid for.
- **My own refutation of the PAM sidecar was over-scoped** — I tested `.tif`, found no sidecar, and
  generalised. Writing `.nc` through terra *does* emit one, and my own test caught the stranded
  sidecar an hour later. The same mistake the review had made, in the other direction.
- **The frozen cube-key guardian (`test-dft_stac_cube.R:62`) is red on `main`** and was confirmed
  pre-existing via `git stash` before any of this work. Left untouched; needs its own issue. Worth
  checking before attributing it to this PR.

## Evidence

`planning/archive/2026-09-issue-41-atomic-cache-write/findings.md` — the damage taxonomy, the
review adjudication, and the design notes. Probe scripts were scratch and not committed; every
number above is reproducible from the taxonomy table's method (truncate or zero a real cache entry,
then open/inspect/read it).

Commits: `c3c46a4` (fetch), `30442ed` (cube), `bd70f36` (docs, NEWS, v0.11.0).

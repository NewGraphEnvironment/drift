## Outcome

The silent gdalcubes failures left over from #87 were fixed at their source, on our fork, for upstream. The cause was small: `gdalwarp_client::warp_simple()` ignored the return of `ChunkAndWarpImage()`, so a read that failed after a successful open came back as an all-NaN "image". A mask that failed to read therefore left its scene unmasked, and cloud reached the median with status OK.

The fork branch (NewGraphEnvironment/gdalcubes#2, off `ed68331`) does five things:
- makes a failed warp return nullptr, which reaches `read_chunk()`'s existing INCOMPLETE branches;
- records a failed mask open;
- sets ERROR when the main process cannot read back a worker's chunk file;
- opens an overview before closing the source;
- fixes the "worker killed by a signal hangs `write_ncdf()`" case.

That hang turned out to be the log printer: `while (!eof())` on a log a worker killed at startup never wrote. It was not the supervision loop. The upstream PR is drafted in `upstream-pr-draft.md` and **not posted**.

drift keeps `Remotes: appelmar/gdalcubes`, as decided at the plan gate. Its changes:
- drops STAC items that have no mask asset (gdalcubes would read them unmasked), with its own error subclass;
- adds fixtures that corrupt a COG tile with the IFD intact;
- adds tests gated on a capability probe, which skip with a drift#99 reason on 0.7.5;
- updates the docs.

One correction to the issue's own table: in drift's read shape (`apply_pixel()` with no `select_bands()`), gdalcubes also reads SCL as a band. So a *deleted* SCL is already recorded on 0.7.5. The case drift really missed is a *corrupted* SCL.

## Measurement

| check | 0.7.5 | fork branch |
|---|---|---|
| `test_chunk_status.R` (32 assertions) | 10 fail: band read, mask open, mask read and strict mask open, each at parallel 1 and 2; the cloud value 900 reached the output | 32 pass |
| `test_worker_failure.R` | both fail at the 120 s timeout | pass in 0.9 s |
| full gdalcubes tinytest | — | 159 / 159 |
| corrupted SCL in drift's shape, failed chunks | 0 | 9 |
| deleted SCL in drift's shape, failed chunks | 9 | 9 |
| deleted SCL with `select_bands()` | 0 | 9 |

- **drift tests:** gated tests SKIP on 0.7.5. With `DRIFT_TEST_ASSUME_READ_STATUS=true` exactly those tests fail; on the fork build all pass. The full drift suite is green on 0.7.5.
- **Mutations that turned tests red:**
  - unwiring the mask-asset drop (5 failures);
  - a probe forced to answer FALSE;
  - `select_bands()` inserted in `stac_cube_assemble()` (M9);
  - the composite handler order swapped.
- **Wrong turns, kept:**
  - The first fixture corrupted the end of a GTiff. A GTiff keeps its IFD there, so that tested an open failure, which read as "0.7.5 already records band read failures". Overwriting the tail of a COG still decoded. The tile has to be broken at its `TileOffsets` entry.
  - A mid-write SIGKILL never hung. Only a kill at startup does.
  - A multi-band "overview" segfault from review round 1 also happens at full resolution on 0.7.5. It is the #92 two-band defect and out of scope.
- **Code-check:**
  - Fork: 3 rounds. Round 1 found a NULL dereference inside the plan-review fix. Round 3 ended the loop with a 39-row ownership and state enumeration.
  - drift: 3 rounds. Round 3 walked every new assertion and guard with mutations.
  - Seven reviewer agents in all, plus one plan reviewer.

## Evidence

- Fork branch `NewGraphEnvironment/gdalcubes:99-chunk-status-read-failures`: `inst/tinytest/test_chunk_status.R`, `inst/tinytest/test_worker_failure.R`.
- Review rounds: `review-plan.md`, `review-fork-round[123].md`, `review-drift-round[123].md` in this directory.
- Durable notes: `inst/notes/gdalcubes-pc-gotchas.md`, "Failed reads after open, mask failures, worker deaths (#99)".
- The hang and segfault repros were scratch-only; the hang is now `test_worker_failure.R`.

Closed by: drift PR for branch `99-gdalcubes-read-failures-after-open-mask` (see `gh pr list --search 99`); fork PR NewGraphEnvironment/gdalcubes#2

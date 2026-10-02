# Progress — Failed gdalcubes chunk reads are silent: a partial cube passes the empty check and is cached (#87)

## Session 2026-10-02

- Plan-mode exploration — phases approved by user
- Created branch `87-failed-gdalcubes-chunk-reads-are-silent` off main
- Scaffolded PWF baseline from issue #87 with approved phases
- Next: start Phase 1
- Phase 1: `cube_check_chunks()` + offline fixture; red-then-green; no-op mutation red
- Plan review: chunk_status records band OPEN failures only (probed: read-after-open
  and SCL-open failures stay OK; log_file no help). Scope narrowed; drift#99 filed
- Phase 2: `cube_write_ncdf()` wired into both write sites; integration tests red
  before wiring and after un-wiring; offset-split S4 class loss found and fixed;
  cache-gate arm; retries; tile cleanup
- code-check round 1 (fill = unmerged chunk), round 2 (abort inside Rcpp warning
  handler — a defect inside round 1's fix; unreadable worker chunk file; untiled
  retries) fixed; round 3 asked for an enumeration of gdalcubes failure paths
- Live probe 8 of 8 (`data-raw/logs/probe_chunk_status_live/20261002T140832Z.txt`)
- Full suite: FAIL 0 | PASS 1548

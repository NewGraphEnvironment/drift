#!/usr/bin/env bash
# Run data-raw/benchmark_composite_bulk.R for one stage, sampling the Rscript
# process's RSS every 2 s and recording the wall clock (drift#79).
#
#   bash data-raw/benchmark_composite_bulk-run.sh chips
#   bash data-raw/benchmark_composite_bulk-run.sh floodplain
#
# Rscript is started alone with `&` so $! is its PID. Gated on the script's
# `ALL STAGES DONE` marker, not on the exit status.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[ $# -eq 1 ] || { echo "usage: $0 <chips|floodplain>" >&2; exit 2; }
s="$1"
d="data-raw/logs/benchmark_composite_bulk"
mkdir -p "$d"
: > "$d/rss_$s.txt"
date -u +"%Y-%m-%dT%H:%M:%SZ start $s" > "$d/wallclock_$s.txt"
Rscript data-raw/benchmark_composite_bulk.R "$s" > "$d/run_$s.log" 2>&1 &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  ps -o rss= -p "$pid" >> "$d/rss_$s.txt"
  sleep 2
done
wait "$pid"; rc=$?
date -u +"%Y-%m-%dT%H:%M:%SZ end $s (exit $rc)" >> "$d/wallclock_$s.txt"
peak=$(sort -n "$d/rss_$s.txt" | tail -1 | awk '{printf "%.2f", $1/1024/1024}')
if grep -q "ALL STAGES DONE" "$d/run_$s.log"; then
  echo "OK   $s  peak RSS ${peak} GiB  $(grep -E '^(chips|floodplain):' "$d/run_$s.log" | tail -1)"
else
  echo "FAIL $s  (exit $rc)  $(grep -iE 'error|halted' "$d/run_$s.log" | head -3)"
  exit 1
fi

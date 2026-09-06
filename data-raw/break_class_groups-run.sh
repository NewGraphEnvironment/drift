#!/usr/bin/env bash
# Run data-raw/break_class_groups.R for one or more groups, sampling the Rscript
# process's RSS every 2 s and recording the wall clock (drift#62).
#
#   bash data-raw/break_class_groups-run.sh necr lnth bulk kotl
#
# Rscript is started alone with `&` so $! is its PID — `cmd1 && cmd2 &` would
# background the whole list and sample the wrapper shell instead. Each group is
# gated on its own `ALL STAGES DONE` marker, not on the exit status.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[ $# -gt 0 ] || { echo "usage: $0 <group> [<group> ...]" >&2; exit 2; }

fails=0
for g in "$@"; do
  d="data-raw/logs/break_class_groups/$g"
  mkdir -p "$d"
  : > "$d/rss.txt"
  date -u +"%Y-%m-%dT%H:%M:%SZ start $g" > "$d/run_wallclock.txt"
  Rscript data-raw/break_class_groups.R "$g" > "$d/run.log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    ps -o rss= -p "$pid" >> "$d/rss.txt"
    sleep 2
  done
  wait "$pid"; rc=$?
  date -u +"%Y-%m-%dT%H:%M:%SZ end $g (exit $rc)" >> "$d/run_wallclock.txt"
  peak=$(sort -n "$d/rss.txt" | tail -1 | awk '{printf "%.1f", $1/1024/1024}')
  if grep -q "ALL STAGES DONE" "$d/run.log"; then
    echo "OK   $g  peak RSS ${peak} GiB  $(grep 'wall' "$d/timings.csv" | tr -d '"')"
  else
    echo "FAIL $g  (exit $rc)  $(grep -iE 'error|halted' "$d/run.log" | head -3)"
    fails=$((fails + 1))
  fi
done
exit "$fails"

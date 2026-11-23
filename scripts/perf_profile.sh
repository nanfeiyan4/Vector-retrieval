#!/usr/bin/env bash
# Software-event profiling of the running service (no PMU on this cloud VM).
# Captures: perf stat (software events) + sampled call stacks (cpu-clock) + hot symbols.
set -euo pipefail
ROOT=${ROOT:-/root/proj1}
OUT="${ROOT}/results/perf"
mkdir -p "$OUT"
PORT=${PORT:-9200}
DUR=${DUR:-12}

pkill -f 'vecserver' 2>/dev/null || true
sleep 0.5
READY=/tmp/ready_perf_$$
"${ROOT}/build/vecserver_native" --data "${ROOT}/data/base.f32" --index "${ROOT}/data/index.bin" \
  --ef 64 --threads 8 --port "$PORT" --nodelay --ready "$READY" > "${OUT}/server.log" 2>&1 &
SRV=$!
for _ in $(seq 1 1800); do [ -f "$READY" ] && break; sleep 0.2; done

# background load so samples land in the search path
"${ROOT}/build/vecclient" --host 127.0.0.1 --port "$PORT" --threads 8 --nq 1 --k 10 \
  --queries "${ROOT}/data/query.f32" --nqtotal 100000000 --gt "" > "${OUT}/client.log" 2>&1 &
CLI=$!
sleep 2

echo "== perf stat (software events) ==" | tee "${OUT}/perf-stat.txt"
perf stat -p "$SRV" -e task-clock,context-switches,cpu-migrations,page-faults,cycles,instructions \
  -- sleep "$DUR" 2>&1 | tee -a "${OUT}/perf-stat.txt"

echo "== perf record (cpu-clock, call stacks) ==" | tee "${OUT}/perf-report.txt"
perf record -F 999 -g -e cpu-clock -p "$SRV" -o "${OUT}/perf.data" -- sleep "$DUR" 2>&1 | tail -2
perf report -i "${OUT}/perf.data" --stdio --sort comm,dso,symbol --percent-limit 0.5 2>&1 | tee -a "${OUT}/perf-report.txt"
perf script -i "${OUT}/perf.data" > "${OUT}/perf-script.txt" 2>/dev/null || true

kill "$CLI" 2>/dev/null || true
kill "$SRV" 2>/dev/null || true
rm -f "$READY"
echo "wrote ${OUT}/{perf-stat.txt,perf-report.txt,perf-script.txt}"

#!/usr/bin/env bash
# Static micro-architectural analysis of the hot distance kernel using llvm-mca,
# substituting for unavailable hardware PMU counters on this cloud VM.
set -euo pipefail
ROOT=${ROOT:-/root/proj1}
OUT="${ROOT}/results/mca"
mkdir -p "$OUT"

for flags in "-O2" "-O3" "-O3 -march=native"; do
  tag=$(echo "$flags" | tr ' -' '__')
  clang -S $flags -fno-asynchronous-unwind-tables "${ROOT}/src/l2kernel.c" -o "${OUT}/l2kernel${tag}.s"
  llvm-mca -mcpu=native -iterations=200 "${OUT}/l2kernel${tag}.s" > "${OUT}/mca${tag}.txt" 2>&1 || true
  echo "== $flags =="
  grep -E "Iterations|Instructions:|Total Cycles|IPC|Block RThroughput" "${OUT}/mca${tag}.txt" | head -6
done
echo "wrote ${OUT}"

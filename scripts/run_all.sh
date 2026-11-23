#!/usr/bin/env bash
# Experiment matrix driver. Usage: ./run_all.sh <stage>
# stages: smoke baseline ef threads batch os flags all
set -euo pipefail
ROOT=${ROOT:-/root/proj1}
B="${ROOT}/scripts/bench.sh"
NQ=${NQ:-200000}
REPS=${REPS:-3}

stage=${1:-all}

smoke() {
  bash "$B" --label smoke --nqtotal 2000 --reps 1
}

baseline() {
  bash "$B" --label baseline --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
}

ef() {
  for e in 16 32 64 128 256; do
    bash "$B" --label "ef$e" --ef "$e" --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  done
}

threads() {
  for t in 1 2 4 8 12 16; do
    bash "$B" --label "sthreads$t" --ef 64 --sthreads "$t" --cthreads 16 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  done
}

batch() {
  for n in 1 4 16; do
    bash "$B" --label "batch$n" --ef 64 --sthreads 8 --cthreads 8 --nq "$n" --nqtotal "$NQ" --reps "$REPS"
  done
}

os() {
  # transparent huge pages
  bash "$B" --label "thp-always" --thp always --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  bash "$B" --label "thp-never"  --thp never  --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  bash "$B" --label "thp-madvise" --thp madvise --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  # TCP_NODELAY off
  bash "$B" --label "nodelay-off" --nodelay 0 --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  # busy polling on sockets
  bash "$B" --label "busypoll-50" --busypoll 50 --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  # CPU isolation: server 6 physical cores, client 2 physical cores
  bash "$B" --label "cpuset-isolated" --server-cpus 0-11 --client-cpus 12-15 \
             --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
}

flags() {
  bash "$B" --label "build-O3" --bin "${ROOT}/build/vecserver_O3" --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
  bash "$B" --label "build-native" --bin "${ROOT}/build/vecserver_native" --ef 64 --sthreads 8 --cthreads 8 --nq 1 --nqtotal "$NQ" --reps "$REPS"
}

case "$stage" in
  smoke) smoke ;;
  baseline) baseline ;;
  ef) ef ;;
  threads) threads ;;
  batch) batch ;;
  os) os ;;
  flags) flags ;;
  all) smoke; baseline; ef; threads; batch; os; flags ;;
  *) echo "unknown stage $stage" >&2; exit 2 ;;
esac
echo "[run_all] stage '$stage' done -> ${ROOT}/results/raw.csv"

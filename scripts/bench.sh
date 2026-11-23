#!/usr/bin/env bash
# One benchmark point: start server, run closed-loop client REPS times, append CSV.
set -euo pipefail

ROOT=${ROOT:-/root/proj1}
LABEL="baseline"
EF=64
STHREADS=8
CTHREADS=8
NQ=1
NQTOTAL=20000
REPS=3
K=10
SERVER_CPUS=""
CLIENT_CPUS=""
THP=""
NODELAY=1
BUSYPOLL=0
BIN="${ROOT}/build/vecserver"
OUT="${ROOT}/results/raw.csv"
PORT=9000

while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --ef) EF="$2"; shift 2 ;;
    --sthreads) STHREADS="$2"; shift 2 ;;
    --cthreads) CTHREADS="$2"; shift 2 ;;
    --nq) NQ="$2"; shift 2 ;;
    --nqtotal) NQTOTAL="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    --k) K="$2"; shift 2 ;;
    --server-cpus) SERVER_CPUS="$2"; shift 2 ;;
    --client-cpus) CLIENT_CPUS="$2"; shift 2 ;;
    --thp) THP="$2"; shift 2 ;;
    --nodelay) NODELAY="$2"; shift 2 ;;
    --busypoll) BUSYPOLL="$2"; shift 2 ;;
    --bin) BIN="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "${ROOT}/results"
if [ ! -f "$OUT" ]; then
  echo "label,ef,sthreads,cthreads,nq_per_req,rep,qps,p50_us,p90_us,p95_us,p99_us,max_us,requests,recall,errors" > "$OUT"
fi

if [ -n "$THP" ]; then
  echo "$THP" > /sys/kernel/mm/transparent_hugepage/enabled
fi
echo "thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled | tr -d '\n')"

# kill previous servers by exact process name (pkill -f would also match this
# script's own command line when --bin contains "vecserver")
pkill -x vecserver 2>/dev/null || true
sleep 0.5
READY="/tmp/ready_$$_${RANDOM}"
rm -f "$READY"

SRV_ARGS=(--data "${ROOT}/data/base.f32" --index "${ROOT}/data/index.bin"
          --ef "$EF" --threads "$STHREADS" --port "$PORT" --ready "$READY")
[ "$NODELAY" = "1" ] && SRV_ARGS+=(--nodelay)
[ "$BUSYPOLL" != "0" ] && SRV_ARGS+=(--busypoll "$BUSYPOLL")

if [ -n "$SERVER_CPUS" ]; then
  taskset -c "$SERVER_CPUS" "$BIN" "${SRV_ARGS[@]}" > "/tmp/srv_$$.log" 2>&1 &
else
  "$BIN" "${SRV_ARGS[@]}" > "/tmp/srv_$$.log" 2>&1 &
fi
SRV_PID=$!

for _ in $(seq 1 1800); do
  [ -f "$READY" ] && break
  if ! kill -0 "$SRV_PID" 2>/dev/null; then echo "server died:"; cat "/tmp/srv_$$.log"; exit 1; fi
  sleep 0.2
done
[ -f "$READY" ] || { echo "server not ready"; cat "/tmp/srv_$$.log"; exit 1; }

for rep in $(seq 1 "$REPS"); do
  CLI=(--host 127.0.0.1 --port "$PORT" --threads "$CTHREADS" --nq "$NQ" --k "$K"
       --queries "${ROOT}/data/query.f32" --nqtotal "$NQTOTAL" --gt "${ROOT}/data/gt.i32" --warmup 100)
  if [ -n "$CLIENT_CPUS" ]; then
    ROW=$(taskset -c "$CLIENT_CPUS" "${ROOT}/build/vecclient" "${CLI[@]}")
  else
    ROW=$("${ROOT}/build/vecclient" "${CLI[@]}")
  fi
  echo "${LABEL},${EF},${STHREADS},${CTHREADS},${NQ},${rep},${ROW}" >> "$OUT"
  echo "  [${LABEL}] rep${rep}: ${ROW}"
done

kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
rm -f "$READY"

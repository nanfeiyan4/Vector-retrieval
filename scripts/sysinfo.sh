#!/usr/bin/env bash
# Record the measurement environment into results/env.txt (required for reproducibility).
set -euo pipefail
ROOT=${ROOT:-/root/proj1}
OUT="${ROOT}/results/env.txt"
mkdir -p "${ROOT}/results"
{
  echo "== date =="; date -Is
  echo; echo "== os =="; cat /etc/os-release | head -3; uname -a
  echo; echo "== cpu =="; lscpu | grep -E "Model name|^CPU\(s\)|Thread|Core|Socket|NUMA node\(s\)|L1d|L2|L3"
  echo; echo "== mem =="; free -g; grep -E "HugePages_Total|Hugepagesize" /proc/meminfo
  echo; echo "== thp =="; cat /sys/kernel/mm/transparent_hugepage/enabled
  echo; echo "== kernel cmdline =="; cat /proc/cmdline
  echo; echo "== net sysctl =="; sysctl net.core.somaxconn net.ipv4.tcp_rmem net.ipv4.tcp_wmem \
       net.core.rmem_max net.core.wmem_max net.ipv4.tcp_tw_reuse net.core.busy_poll net.core.busy_read 2>/dev/null || true
  echo; echo "== toolchain =="; g++ --version | head -1; perf --version
  echo; echo "== data =="; ls -l "${ROOT}/data"/*.f32 "${ROOT}/data"/*.i32 2>/dev/null || true
  cat "${ROOT}/data/meta.txt" 2>/dev/null || true
  echo; echo "== git =="; git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo "no git"
} > "$OUT" 2>&1
echo "wrote $OUT"

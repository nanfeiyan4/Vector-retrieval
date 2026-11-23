#!/usr/bin/env bash
# Build the vector-search service. Baseline binary: -O2, no ISA flags.
set -euo pipefail
ROOT=${ROOT:-/root/proj1}
CXX=${CXX:-g++}
INC="-I${ROOT}/hnswlib"   # headers live at ${ROOT}/hnswlib/hnswlib/*.h
mkdir -p "${ROOT}/build"

echo "[build] baseline (-O2) server ..."
${CXX} -O2 -std=c++17 -pthread ${INC} "${ROOT}/src/server.cpp" -o "${ROOT}/build/vecserver"

echo "[build] optimized (-O3) server ..."
${CXX} -O3 -std=c++17 -pthread ${INC} "${ROOT}/src/server.cpp" -o "${ROOT}/build/vecserver_O3"

echo "[build] optimized (-O3 -march=native) server ..."
${CXX} -O3 -march=native -std=c++17 -pthread ${INC} "${ROOT}/src/server.cpp" -o "${ROOT}/build/vecserver_native"

echo "[build] client (-O3 -march=native) ..."
${CXX} -O3 -march=native -std=c++17 -pthread ${INC} "${ROOT}/src/client.cpp" -o "${ROOT}/build/vecclient"

ls -l "${ROOT}/build"

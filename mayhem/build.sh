#!/usr/bin/env bash
#
# mayhem/build.sh — build parasail's fuzz harness (parasail_aligner) + the upstream test suite.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. Two independent trees:
#   build-fuzz  — libparasail + parasail_aligner, instrumented (ASan+UBSan) with DWARF<4, for the
#                 Mayhem target (parasail-aligner CLI).
#   build-tests — the upstream CTest suite (test_isa/test_basic/test_verify), NORMAL flags, so
#                 mayhem/test.sh is an honest functional oracle.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 0) stdin guard for the parasail-aligner FILE-INPUT target: a constructor that closes fd 0 so the
#     aligner's poll(POLLIN)-based stdin auto-detection (stdin_has_data()) can't false-positive on
#     Mayhem's /dev/null stdin and mis-treat stdin as an (empty) query file — which made it exit
#     EXIT_FAILURE ("no alignment work") before reading any input => 0-edge "Run Failed". Linked into
#     parasail_aligner ONLY (see CMAKE_EXE_LINKER_FLAGS below); matrix-create is not affected.
ALIGNER_GUARD_OBJ=/tmp/aligner_stdin_guard.o
$CC $DEBUG_FLAGS -c "$SRC/mayhem/aligner_stdin_guard.c" -o "$ALIGNER_GUARD_OBJ"

# 1) Sanitized build: libparasail (static) + parasail_aligner. OpenMP off (no libomp in base;
#    parasail guards on _OPENMP so this is a supported, additive build choice). SanitizerCoverage
#    (-fsanitize=fuzzer-no-link) instruments the library + the parasail-aligner CLI so Mayhem gets
#    edge feedback on the file-input target (no libFuzzer main is linked — it stays a normal CLI).
#    CMAKE_EXE_LINKER_FLAGS threads the stdin-guard object into the parasail_aligner link.
: "${COV_FLAGS=-fsanitize=fuzzer-no-link}"
cmake -S . -B build-fuzz \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DWITH_OPENMP=OFF -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $COV_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $COV_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$ALIGNER_GUARD_OBJ"
cmake --build build-fuzz -j"$MAYHEM_JOBS" --target parasail parasail_aligner
cp build-fuzz/parasail_aligner /mayhem/parasail_aligner

# 2) Upstream test suite with NORMAL (non-sanitized) flags — an independent tree so the oracle
#    won't false-fail on benign UB. $COVERAGE_FLAGS is empty by default (no effect).
cmake -S . -B build-tests \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DWITH_OPENMP=OFF -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
cmake --build build-tests -j"$MAYHEM_JOBS" --target test_isa test_basic test_verify

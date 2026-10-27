#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/primitives
for compiler in dmd ldc2; do
    command -v "$compiler" >/dev/null
    "$compiler" -dip1000 -w -unittest -Isource \
        source/compression/core.d source/compression/bitstream.d \
        source/compression/huffman.d tests/huffman_tests.d tests/primitives_probe.d \
        -of=".build/primitives/$compiler-probe"
    ".build/primitives/$compiler-probe"
done

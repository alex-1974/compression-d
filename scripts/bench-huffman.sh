#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/benchmarks
for compiler in dmd ldc2; do
    command -v "$compiler" >/dev/null
    flags=(-O -inline)
    if [[ "$compiler" == ldc2 ]]; then
        flags=(-O3)
    fi
    printf '%s\n' "$compiler"
    "$compiler" "${flags[@]}" -Isource \
        source/compression/core.d source/compression/bitstream.d \
        source/compression/huffman.d benchmarks/huffman.d \
        -of=".build/benchmarks/$compiler-huffman"
    ".build/benchmarks/$compiler-huffman" "${1:-20}" "${2:-12345}"
done

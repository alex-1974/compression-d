#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/inflate
for compiler in dmd ldc2; do
    command -v "$compiler" >/dev/null
    "$compiler" -dip1000 -w -unittest -Isource -Itests \
        source/compression/core.d source/compression/bitstream.d \
        source/compression/huffman.d source/compression/deflate.d \
        tests/inflate_fixtures.d tests/inflate_tests.d tests/inflate_probe.d \
        -of=".build/inflate/$compiler-probe"
    ".build/inflate/$compiler-probe"
    "$compiler" -O -Isource \
        source/compression/core.d source/compression/bitstream.d \
        source/compression/huffman.d source/compression/deflate.d \
        scripts/inflate-oracle.d -of=".build/inflate/$compiler-oracle"
    python3 scripts/check-inflate-differential.py ".build/inflate/$compiler-oracle"
done

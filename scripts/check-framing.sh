#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/framing
sources=(source/compression/core.d source/compression/bitstream.d
    source/compression/huffman.d source/compression/deflate.d
    source/compression/checksum.d source/compression/framing.d
    source/compression/zlib.d source/compression/gzip.d)
compilers=(dmd ldc2)
if (( $# != 0 )); then compilers=("$@"); fi
for compiler in "${compilers[@]}"; do
    command -v "$compiler" >/dev/null
    compiler_name=${compiler##*/}
    "$compiler" -dip1000 -w -unittest -Isource -Itests "${sources[@]}" \
        tests/framing_fixtures.d tests/framing_tests.d tests/framing_probe.d \
        -of=".build/framing/$compiler_name-probe"
    ".build/framing/$compiler_name-probe"
    "$compiler" -O -Isource "${sources[@]}" scripts/framing-oracle.d \
        -of=".build/framing/$compiler_name-oracle"
    python3 scripts/check-framing-differential.py ".build/framing/$compiler_name-oracle"
done

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/core-contract
for compiler in dmd ldc2; do
    command -v "$compiler" >/dev/null
    "$compiler" -dip1000 -w -unittest -Isource \
        source/compression/core.d tests/core_probe.d \
        -of=".build/core-contract/$compiler-probe"
    ".build/core-contract/$compiler-probe"
done

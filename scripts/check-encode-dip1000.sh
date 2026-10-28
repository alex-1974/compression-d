#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/.build/encoder-dip1000"
mkdir -p "$root/.build"
sources=(
  "$root/source/compression/bitstream.d"
  "$root/source/compression/checksum.d"
  "$root/source/compression/core.d"
  "$root/source/compression/deflate.d"
  "$root/source/compression/encode.d"
  "$root/source/compression/framing.d"
  "$root/source/compression/huffman.d"
  "$root/source/compression/zlib.d"
  "$root/tests/encoder_dip1000_probe.d"
)
dmd -w -dip1000 -I"$root/source" -of="$build-dmd" "${sources[@]}"
"$build-dmd"
if command -v ldc2 >/dev/null 2>&1; then
    ldc2 -w -dip1000 -I"$root/source" -of="$build-ldc" "${sources[@]}"
    "$build-ldc"
else
    echo "ldc2 not found; skipped LDC encoder DIP1000 probe" >&2
fi
echo "fully linked encoder DIP1000 probes passed"

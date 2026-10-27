#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/.build/encoder-property"
mkdir -p "$root/.build"
dmd -w -O -I"$root/source" -of="$build" \
    "$root/source/compression/bitstream.d" \
    "$root/source/compression/checksum.d" \
    "$root/source/compression/core.d" \
    "$root/source/compression/deflate.d" \
    "$root/source/compression/encode.d" \
    "$root/source/compression/framing.d" \
    "$root/source/compression/huffman.d" \
    "$root/source/compression/zlib.d" \
    "$root/tests/encoder_property.d"
"$build"

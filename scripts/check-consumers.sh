#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
compression_root=$PWD
imageio_root=${IMAGEIO_D_ROOT:-"$compression_root/../d-geospatial-workspace/libs/imageio-d"}
consumer="$imageio_root/experiments/compression_consumer/source"
legacy="$imageio_root/experiments/tiff_core/source"
build="$compression_root/.build/consumers"
mkdir -p "$build"
python_runtime=${CONSUMER_PYTHON:-/usr/bin/python3}
"$python_runtime" scripts/generate-consumer-fixtures.py "$build/fixtures"
for compiler in dmd ldc2; do
    flags=(-O -inline)
    if [[ "$compiler" == ldc2 ]]; then flags=(-O3); fi
    "$compiler" "${flags[@]}" -dip1000 -w -boundscheck=on -i -Isource -I"$consumer" -I"$legacy" \
        "$consumer/consumer_main.d" -of="$build/$compiler-tiff"
    "$compiler" "${flags[@]}" -dip1000 -w -boundscheck=on -i -Isource -Iexperiments/consumers \
        experiments/consumers/png_main.d -of="$build/$compiler-png"
    "$compiler" -dip1000 -w -unittest -i -Isource -Iexperiments/consumers -I"$consumer" -I"$legacy" \
        experiments/consumers/consumer_tests.d -of="$build/$compiler-tests"
    "$build/$compiler-tests" --DRT-testmode=run-main "$build/fixtures"
    while IFS=$'\t' read -r kind encoded expected width height channels depth; do
        if [[ "$kind" == tiff ]]; then
            "$build/$compiler-tiff" "$encoded" "$expected"
        else
            "$build/$compiler-png" "$encoded" "$expected" "$width" "$height" "$channels" "$depth"
        fi
    done < "$build/fixtures/manifest.tsv"
done
tar -czf "$build/imageio-consumer-context.tar.gz" -C "$imageio_root" \
    experiments/compression_consumer/source experiments/compression_consumer/dub.sdl \
    experiments/tiff_core/source/ifd_result.d experiments/tiff_core/source/payload_decode.d \
    experiments/tiff_core/source/block_bridge.d

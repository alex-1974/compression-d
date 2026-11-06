#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

python3 - "$tmp_dir" <<'PY'
import pathlib, subprocess, sys
out = pathlib.Path(sys.argv[1])
w, h = 97, 71
pgm = out / "source.pgm"
pgm.write_bytes(f"P5\n{w} {h}\n255\n".encode() + bytes((x*17+y*31)&255 for y in range(h) for x in range(w)))
for restart in (1, 4, 16):
    jpg = out / f"valid-r{restart}.jpg"
    with jpg.open("wb") as stream:
        subprocess.run(["cjpeg", "-grayscale", "-restart", str(restart), "-quality", "82", str(pgm)], stdout=stream, check=True)
    data = jpg.read_bytes()
    (out / f"truncated-r{restart}.jpg").write_bytes(data[:-7])
    bad = bytearray(data)
    for i, b in enumerate(bad):
        if b == 0xd0:
            bad[i] = 0xd7
            break
    (out / f"marker-r{restart}.jpg").write_bytes(bad)
    (out / f"prefix-r{restart}.jpg").write_bytes(data[: max(2, len(data)//3)])
    for mutation in range(32):
        mutated = bytearray(data)
        pos = (mutation * 7919) % len(mutated)
        mutated[pos] ^= (mutation * 37 + 1) & 255
        (out / f"mutated-r{restart}-{mutation}.jpg").write_bytes(mutated)
PY

dmd -Isource -of="$tmp_dir/jpeg_fuzz_d" tools/jpeg_fuzz.d source/compression/jpeg.d
"$tmp_dir/jpeg_fuzz_d" "$tmp_dir"
ldc2 -Isource -of="$tmp_dir/jpeg_fuzz_ldc" tools/jpeg_fuzz.d source/compression/jpeg.d
"$tmp_dir/jpeg_fuzz_ldc" "$tmp_dir"

ldc2 -Isource -fsanitize=address -g -of="$tmp_dir/jpeg_fuzz_san" \
    tools/jpeg_fuzz.d source/compression/jpeg.d
ASAN_OPTIONS=detect_leaks=0 \
    "$tmp_dir/jpeg_fuzz_san" "$tmp_dir"

echo "JPEG malformed corpus and bounded fuzz harness passed"

#!/usr/bin/env bash
set -euo pipefail

# JPEG ROI admission smoke gate. Requires independent libjpeg tools.
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

command -v cjpeg >/dev/null
command -v djpeg >/dev/null

python3 - "$tmp_dir/input.pgm" <<'PY'
import sys
path = sys.argv[1]
w, h = 97, 71
with open(path, "wb") as f:
    f.write(f"P5\n{w} {h}\n255\n".encode())
    f.write(bytes((x * 17 + y * 31) & 255 for y in range(h) for x in range(w)))
PY

cjpeg -grayscale -restart 1 -quality 82 "$tmp_dir/input.pgm" > "$tmp_dir/input.jpg"
djpeg -grayscale "$tmp_dir/input.jpg" > "$tmp_dir/oracle.pgm"
test -s "$tmp_dir/oracle.pgm"

(cd "$repo_dir" && dub test --compiler=dmd --force)
(cd "$repo_dir" && dub test --compiler=ldc2 --force)

echo "JPEG ROI smoke gate passed; independent oracle generated"

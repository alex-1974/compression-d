#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
dub test
git diff --check
echo "encoder contract, LZ77 roundtrips and streaming checks passed"

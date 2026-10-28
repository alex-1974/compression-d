# compression-d: cross-chunk fixed-LZ encoder verification

## Summary

- persists DEFLATE bit-writer state and the 32 KiB LZ77 history across chunks;
- adds an optional bounded hash-chain matcher with caller-owned fixed tables;
- verifies deterministic encoder roundtrips over repetitive, low-entropy and random inputs;
- documents a reproducible zlib reference benchmark and the compiler/consumer gates.

## Verification

```text
bash scripts/check-encoder-property.sh
python3 scripts/bench-encoder.py
bash scripts/check-encode.sh
bash scripts/check-core.sh
bash scripts/check-inflate.sh
bash scripts/check-framing.sh
bash scripts/check-consumers.sh
```

This file is local PR preparation only; no remote branch or pull request is created by the verification run.

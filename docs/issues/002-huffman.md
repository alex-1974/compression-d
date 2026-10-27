# Issue 002 — Canonical Huffman core

Milestone: M1

- [x] Build canonical tables without allocation.
- [x] Validate oversubscribed and incomplete trees.
- [x] Test Deflate bit ordering and truncation.
- [x] Benchmark lookup strategies.

Implemented in `compression.bitstream` and `compression.huffman`, with typed
compact/9-bit-root workspaces. See [the primitive contract](../PRIMITIVES.md)
and [lookup measurements](../HUFFMAN_BENCHMARKS.md). Verify with
`bash scripts/check-primitives.sh` or `dub test` under DMD and LDC.

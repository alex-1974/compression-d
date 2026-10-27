# Issue 003 — Complete Pure-D Inflate

Milestone: M2

- [x] Stored blocks.
- [x] Fixed Huffman blocks.
- [x] Dynamic Huffman headers and code-length alphabet.
- [x] Length/distance extra bits.
- [x] Bounds-safe overlapping LZ77 copies.
- [x] Expansion-bomb limits.

Implemented in `compression.deflate` with caller-owned state/workspace and
one-shot/streaming APIs. See [the Inflate contract and evidence](../INFLATE.md).
Verify with `bash scripts/check-inflate.sh` (DMD/LDC, probes, zlib differential
cases) or `dub test` (saved corpus and unit tests, no Python dependency).

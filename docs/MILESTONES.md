# Milestones

## M0 — Contract and repository

Exit: documented ownership, limits, errors and module boundaries.

Status: implemented in `compression.core` and [CORE_CONTRACT.md](CORE_CONTRACT.md),
with DMD/LDC unit tests and compile probes. Codec workspace layouts remain part
of their respective implementation milestones.

## M1 — Bitstream and Huffman

Exit: allocation-free validated tables and bitreader under DMD/LDC.

Status: implemented and verified under DMD 2.111.0 and LDC 1.42.0.
See [primitive contracts/tests](PRIMITIVES.md) and
[lookup experiments](HUFFMAN_BENCHMARKS.md). Codec implementation continues in M2.

## M2 — Inflate correctness

Exit: stored/fixed/dynamic differential corpus, malformed corpus and bounded
output behavior.

Status: implemented in `compression.deflate` and verified under DMD/LDC with
saved/generated zlib corpora, malformed cases, streaming and budget tests.
See [the Inflate contract](INFLATE.md). Framing remains M3.

## M3 — zlib/GZIP framing

Exit: checksum and framing corpus with streaming state tests.

## M4 — Consumer/performance validation

Exit: imageio-d and PNG experiments, reproducible benchmarks and memory data.

## M5 — Public package decision

Exit: two independent consumers, license review and accepted public API.

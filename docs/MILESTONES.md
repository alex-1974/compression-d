# Milestones

## M0 — Contract and repository

Exit: documented ownership, limits, errors and module boundaries.

Status: implemented in `compression.core` and [CORE_CONTRACT.md](CORE_CONTRACT.md),
with DMD/LDC unit tests and compile probes. Codec workspace layouts remain part
of their respective implementation milestones.

## M1 — Bitstream and Huffman

Exit: allocation-free validated tables and bitreader under DMD/LDC.

## M2 — Inflate correctness

Exit: stored/fixed/dynamic differential corpus, malformed corpus and bounded
output behavior.

## M3 — zlib/GZIP framing

Exit: checksum and framing corpus with streaming state tests.

## M4 — Consumer/performance validation

Exit: imageio-d and PNG experiments, reproducible benchmarks and memory data.

## M5 — Public package decision

Exit: two independent consumers, license review and accepted public API.

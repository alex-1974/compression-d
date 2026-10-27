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

Status: implemented in `compression.checksum`, `compression.zlib` and
`compression.gzip`, verified under DMD/LDC with saved/generated reference
frames, negative checksums, optional headers, streaming/reset and cumulative
member budgets. See [the framing contract](FRAMING.md). Consumer work remains M4.

## M4 — Consumer/performance validation

Exit: imageio-d and PNG experiments, reproducible benchmarks and memory data.

Status: local research gate completed under DMD/LDC. A real imageio-d Deflate
path dependency and PNG scanline consumer pass GDAL byte oracles, negative
cases, workspace/parallel isolation and zero hot-path GC probes. Repeated
throughput/RSS data and the uncommitted imageio-d research-context dependency
are documented in [CONSUMERS.md](CONSUMERS.md). Public admission remains M5.

## M5 — Public package decision

Exit: two independent consumers, license review and accepted public API.

# Changelog

## v0.3.0 — 2026-11-08

Admitted the caller-owned streaming GZIP decoder (`GzipState`, `decodeGzip`,
`InflateWorkspace`, `DecodeLimits` and `Result`) as a stable consumer contract.
This includes chunked input/output, concatenated-member validation, cumulative
limits, structured errors and explicit EOF semantics. Other codec APIs remain
experimental.

## v0.2.0 — 2026-11-04

Added bounded, allocation-free decoders for:

- TIFF-compatible LZW (`compression.lzw`), including Clear/EOI, 9–12-bit
  MSB-first codes, Early-Change and streaming state;
- PackBits (`compression.packbits`), including literal, run and no-op blocks.

Both codecs use caller-owned state/workspace, structured errors and the shared
output/expansion limit contract. TIFF strip/tile orchestration, predictors and
pixel layout remain consumer responsibilities.

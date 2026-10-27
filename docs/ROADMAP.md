# Roadmap

## M0 — Repository and contract

- establish module vocabulary, ownership model and error taxonomy;
- define raw decoder versus framed container boundaries.

## M1 — Core primitives

- bit reader/writer;
- checked arithmetic and limits;
- canonical Huffman tables;
- Adler-32 and CRC-32.

## M2 — Inflate

- stored blocks;
- fixed Huffman blocks;
- dynamic Huffman blocks;
- LZ77 copy window;
- malformed and expansion-limit corpus.

## M3 — Framing

- zlib header/trailer;
- GZIP header/trailer;
- streaming state and restart behavior.

## M4 — Consumers and performance

- imageio-d TIFF Deflate;
- PNG scanline integration;
- DMD/LDC benchmarks;
- memory and workspace measurements.

## M5 — Compression and release decision

- encoder only after decoder evidence;
- independent consumer validation;
- API/ABI and license review;
- decide whether a public package is justified.

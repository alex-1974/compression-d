# compression-d

`compression-d` is a planned D-native compression library for codecs and
containers that need predictable ownership, bounded expansion and efficient
operation under DMD and LDC.

The project starts with a Pure-D DEFLATE/Inflate core. It must not depend on
C libraries, system compression backends or wrapper APIs.

## Design goals

- `@safe`, `@nogc`, `nothrow` core paths where practical;
- caller-owned input, output and temporary workspace;
- one-shot and streaming APIs with explicit state ownership;
- deterministic structured errors;
- expansion limits and malformed-input protection;
- independently generated differential fixtures against zlib;
- idiomatic D naming and module structure.

## Initial scope

1. bitstream primitives;
2. canonical Huffman tables;
3. raw DEFLATE/Inflate: stored, fixed and dynamic blocks;
4. zlib framing with Adler-32;
5. GZIP framing with CRC-32;
6. TIFF/PNG consumer integration experiments.

Compression is intentionally deferred until the decoder contract and safety
properties are stable.

## Status

Research repository with an implemented experimental M0 core contract
(`compression.core`): streaming result types, structured errors and checked
output/expansion limits. No stable public API or release promise exists yet.

M1 adds `compression.bitstream` and `compression.huffman`: an LSB-first reader,
validated canonical Huffman tables, and compact/prefix lookup strategies. See
[primitive contracts](docs/PRIMITIVES.md) and
[lookup experiments](docs/HUFFMAN_BENCHMARKS.md).

M2 adds `compression.deflate`: complete raw Inflate for stored/fixed/dynamic
blocks, caller-owned streaming state and a 32-KiB workspace history, with output
and expansion budgets. See [the Inflate contract and test evidence](docs/INFLATE.md).
zlib/GZIP framing and encoding remain pending.

See [the core contract](docs/CORE_CONTRACT.md) for ownership, typed workspace
decisions and streaming semantics. Run `bash scripts/check-core.sh` to test it
with DMD and LDC, including `@safe @nogc nothrow` compile probes.
Run `bash scripts/check-primitives.sh` for M1 tests/probes, or `dub test` with
either compiler for the combined unit tests and primitive consumer probe.
Run `bash scripts/check-inflate.sh` for raw Inflate probes and generated zlib
differential checks under both compilers. Saved Inflate tests also run via
`dub test` without Python/zlib.

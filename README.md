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

Research and architecture repository. No stable public API or release promise
exists yet.

# Architecture direction

## Layers

```text
compression.core       result types, limits, workspace contracts
compression.bitstream   LSB-first readers/writers
compression.huffman     canonical code construction and lookup
compression.deflate     raw RFC 1951 blocks and LZ77 window
compression.zlib        RFC 1950 framing and Adler-32
compression.gzip        RFC 1952 framing and CRC-32
compression.checksum    reusable checksums
```

Codec layers must not allocate implicitly on decode. A caller may provide a
codec-specific typed workspace by `ref`. Input/output slices are borrowed with
`scope`; persistent history lives in the workspace. The experimental M0
[core contract](CORE_CONTRACT.md) defines results, errors, limits and ownership.
Concrete codec workspace layouts follow in M1/M2 and will be validated by the
consumer experiments.

M2 implements `compression.deflate` with pointer-free `InflateState` and
`InflateWorkspace`: tables, temporary code-length storage and a 32-KiB ring
history. See [the raw Inflate contract](INFLATE.md) for API and streaming rules.

M3 adds incremental checksums and separate zlib/GZIP parser states over the
same workspace. Package-internal `compression.framing` handles shared checked
accounting; raw limits receive consumed framing/previous-member budget bases.
See [the framing contract](FRAMING.md) for member boundaries and reset semantics.

## Non-goals

- C bindings or runtime backend selection;
- hidden global scratch buffers;
- an abstraction that forces all codecs into one streaming interface;
- compression before decompression correctness is established.

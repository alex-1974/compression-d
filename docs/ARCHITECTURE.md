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
workspace object or raw `scope ubyte[]`; the final API decision follows the
first consumer experiments.

## Non-goals

- C bindings or runtime backend selection;
- hidden global scratch buffers;
- an abstraction that forces all codecs into one streaming interface;
- compression before decompression correctness is established.

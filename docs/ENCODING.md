# Encoding contract

`compression.encode` provides allocation-free one-shot encoders. The initial
encoder emits RFC 1951 Fixed-Huffman blocks with bounded greedy LZ77 matching.
The streaming state carries both the 32-KiB history window and residual writer
bits across chunks.

`rawStoredSize`, `zlibStoredSize` and `gzipStoredSize` return the exact output
capacity required. The encoders return `needOutput` without writing partial
output when the supplied buffer is too small. A successful call returns `done`
and consumes the complete input slice.

The zlib encoder uses a valid no-dictionary header and Adler-32. The GZIP
encoder emits one minimal member with CRC-32 and RFC 1952 ISIZE. All functions
are `@safe`, `pure`, `nothrow` and `@nogc`; input and output remain caller-owned
and must not overlap.

`RawStoredEncoderState` provides a streaming variant. Each call encodes one
chunk, and `finalChunk` must be set only on the final call. The state retains
only counters, a caller-owned fixed history array and writer bits; input and
output are never retained.
`ZlibStoredEncoderState` and `GzipStoredEncoderState` provide equivalent
streaming wrappers with incremental Adler-32/CRC-32 accounting and trailers
only on the final call. Cross-chunk roundtrip coverage is part of the module
unittests.

# Encoding contract

`compression.encode` provides allocation-free one-shot encoders. The initial
encoder is deliberately conservative: it emits RFC 1951 stored blocks. This is
valid Raw DEFLATE and gives callers deterministic output and an exact capacity
formula while a match-finding encoder is evaluated separately.

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
only counters and completion status; input and output are never retained.
`ZlibStoredEncoderState` and `GzipStoredEncoderState` provide equivalent
streaming wrappers with incremental Adler-32/CRC-32 accounting and trailers
only on the final call. Bounded LZ77 matching remains additive work.

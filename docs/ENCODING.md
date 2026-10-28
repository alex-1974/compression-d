# Encoding contract

`compression.encode` provides allocation-free one-shot encoders. The initial
encoder emits RFC 1951 Fixed-Huffman blocks with bounded greedy LZ77 matching.
The streaming state carries both the 32-KiB history window and residual writer
bits across chunks.

`rawStoredSize`, `zlibStoredSize` and `gzipStoredSize` describe the exact
capacity for the stored-block compatibility encoders. Fixed-LZ output uses a
caller-provided capacity bound; on insufficient capacity it returns
`needOutput`. A successful call returns `done` and consumes the complete input
slice.

The zlib encoder uses a valid no-dictionary header and Adler-32. The GZIP
encoder emits one minimal member with CRC-32 and RFC 1952 ISIZE. All functions
are `@safe`, `pure`, `nothrow` and `@nogc`; input and output remain caller-owned
and must not overlap.

`RawStoredEncoderState` provides a streaming fixed-LZ variant. Each call encodes one
chunk, and `finalChunk` must be set only on the final call. The state retains
only counters, a caller-owned fixed history array and writer bits; input and
output are never retained.
`ZlibStoredEncoderState` and `GzipStoredEncoderState` provide equivalent
streaming wrappers with incremental Adler-32/CRC-32 accounting and trailers
only on the final call. Cross-chunk roundtrip coverage is part of the module
unittests. The `Stored` suffix is retained for source compatibility with the
initial API; new callers should treat these as experimental fixed-LZ encoders.

`HashChainMatchFinder` and `encodeRawFixedLzHashChain` provide an optional
bounded search strategy. It owns 32,768 bucket heads, a 32,768-entry ring of
predecessors and the 32-KiB byte history, all inline and caller-owned. The
finder examines at most 32 candidates per position, limits matches to 258
bytes and distances to 32 KiB, and preserves residual bit-writer state and
history across calls. Inputs whose cumulative position would exceed `uint`
range return `invalidArgument`; no silent position wrap is allowed. The
linear matcher remains the default so existing output and workspace behavior
are unchanged.

The canonical verification commands are `bash scripts/check-encoder-property.sh`
and `python3 scripts/bench-encoder.py`. The latter reports linear and
hash-chain compression-d throughput, plus zlib throughput and compressed size
on the same deterministic corpus.

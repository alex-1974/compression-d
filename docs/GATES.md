# Verification record

The encoder and decoder gates are reproducible from the repository root:

```sh
bash scripts/check-encode.sh
bash scripts/check-encoder-property.sh
python3 scripts/bench-encoder.py
bash scripts/check-core.sh
bash scripts/check-primitives.sh
bash scripts/check-inflate.sh
bash scripts/check-framing.sh
bash scripts/check-consumers.sh
```

The DMD/LDC gates exercise safety attributes, malformed input, differential
Inflate/framing corpora, consumer isolation and zero hot-path GC growth. The
encoder module tests cover fixed-Huffman literals, LZ77 length/distance tokens,
cross-chunk history, bounded hash-chain matching, zlib/GZIP checksums,
insufficient output and roundtrips.

The API is one-shot or explicitly stateful streaming; all buffers and the
fixed 32-KiB history are caller-owned. No C compression backend is used.
`InflateWorkspace` remains the typed caller-owned decoder workspace; encoder
state owns its fixed history array and residual bit state, so no encoder
workspace allocation or hidden input retention occurs.

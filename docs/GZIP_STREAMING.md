# Stable GZIP streaming consumer contract

The `compression.gzip` streaming surface is admitted as a stable consumer
contract from version 0.3.0. This admission covers the names and semantics
listed here; unrelated codec modules remain experimental.

```d
import compression.core : DecodeLimits, DecodeStatus, Result;
import compression.deflate : InflateWorkspace;
import compression.gzip : GzipState, decodeGzip;

GzipState decoder;
decoder.reset(DecodeLimits(64 * 1024 * 1024, 128), true);
InflateWorkspace workspace;

// `input` is the currently available borrowed chunk and `output` is caller
// owned. Set endOfInput only when the underlying source has reached EOF.
Result step = decodeGzip(decoder, workspace, input, output, endOfInput);
```

Each call reports `consumed` and `produced` relative to that call. The caller
discards exactly the consumed input prefix and may forward the produced output
prefix immediately. `needInput` means that non-final input was exhausted;
`needOutput` means the output buffer filled; `done` is returned only after the
GZIP trailer has passed CRC-32 and ISIZE validation. `error` is terminal until
`reset`.

The decoder accepts arbitrary bounded chunks, retains no input slices, performs
no hidden allocation, and uses the caller-owned `InflateWorkspace`. `reset`
also resets cumulative input/output counters, checksums and member state.

`allMembers = true` validates concatenated members and rejects trailing garbage.
Output and expansion limits are cumulative across all members. With
`allMembers = false`, the first valid member is complete and following bytes
remain unconsumed.

The public contract is `@safe`, `@nogc`, `nothrow` and DIP1000-compatible under
the supported DMD and LDC versions recorded in the verification gate. The
contract does not promise a stable ABI for private state layout; callers use
the DUB package and the documented functions/types only.

Errors include invalid/truncated headers or DEFLATE data, checksum/trailer
mismatches, unsupported features, invalid state and limit violations. Error
offsets are absolute offsets in the framed compressed stream where available.

See [FRAMING.md](FRAMING.md) for the complete state-machine and verification
evidence. The API is intentionally generic: transport, file, HTTP, XML and OSM
semantics remain outside this package.

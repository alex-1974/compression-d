# Experimental checksums and framed decode (M3)

`compression.checksum`, `compression.zlib` and `compression.gzip` implement
Adler-32, IEEE CRC-32 and RFC 1950/1952 framing around the M2 raw Inflate engine.
The public modules remain explicitly imported, experimental APIs. There is no
C/backend dependency, auto-detection, encoder or implicit allocation.

## Checksums

`Adler32` and `Crc32` are default-initialized incremental value types. Both have
`update(scope const(ubyte)[] bytes)`, `updateByte(ubyte)`, `reset()` and a `value`
property. Empty Adler-32 is 1; empty CRC-32 is 0. `adler32(bytes)` and
`crc32(bytes)` are one-shot helpers. CRC lookup storage is immutable; there is
no global mutable scratch. Methods compile as `@safe pure nothrow @nogc`.

Tests include the `123456789` known-answer vectors, every split of that input,
reset, and a 200,000-byte comparison with independent modulo/bitwise oracles.

## APIs and ownership

```d
import compression.core;
import compression.deflate;
import compression.zlib;
import compression.gzip;

InflateWorkspace workspace; // same workspace type as the raw decoder
ZlibState zlibState;
zlibState.reset(DecodeLimits(16 * 1024 * 1024));
auto result = decodeZlib(zlibState, workspace, input, output, endOfInput);
```

Use `decodeGzip(ref GzipState, ref InflateWorkspace, scope input, scope output,
bool endOfInput = false)` for GZIP with the same call shape. Default state
initialization starts a new operation with disabled policy limits. Configure
budgets with `reset(limits)` before starting. States and workspace retain no
pointers or slices. Operations are `@safe pure nothrow @nogc` under DIP1000.
Input/output/state/workspace must not overlap; concurrent operations need
independent pairs. Output buffers may be reused or discarded after each call.

`inflateZlib(input, output, ref workspace, limits)` and
`inflateGzip(input, output, ref workspace, limits, allMembers = false)` are
one-shot conveniences with final input. If output is insufficient, they return
`needOutput` with the produced prefix, but do not expose resumable state. Use
the stateful APIs when the decoded length is unknown.

Results follow [the core contract](CORE_CONTRACT.md). Counts are per-call;
`totalInput` includes frame headers, payload and trailers consumed so far, and
`totalOutput` counts emitted bytes. On `needInput`, retain the unconsumed suffix,
append more bytes and resume. Header/trailer bytes are consumed incrementally;
the raw reader may retain an incomplete field/symbol in the caller's unread
suffix. Preserve finality on a `needOutput` resume. Final missing bytes produce
`truncatedInput`, with an absolute framed input offset at EOF.

`done` is returned only after integrity verification. Produced output may precede
trailer verification; a checksum error does not roll back that output. Errors
are terminal and repeat with zero progress until reset. After `done`, another
decode call returns `invalidArgument`. `reset` clears counts/checksums/parser
state without requiring workspace clearing. Raw payload diagnostics are
translated into offsets in the framed operation.

## zlib

The adapter validates CM=8, CINFO<=7 and FCHECK. It enforces the advertised
window size (256..32768 bytes), then validates the big-endian Adler-32 trailer
against the uncompressed bytes. FLEVEL is informational. One zlib stream is
decoded; whole trailing bytes are left unconsumed.

FDICT causes the four-byte big-endian DICTID to be read, then returns
`dictionaryRequired`. `ZlibState.dictionaryId` exposes the requested ID, until
reset. Preset-dictionary decoding is not implemented; the flag is never ignored.
An incomplete DICTID is truncation rather than a complete dictionary request.

## GZIP

The adapter validates magic bytes, CM=8 and reserved FLG bits. MTIME, XFL, OS and
FTEXT are accepted without affecting decode. It incrementally skips binary
FEXTRA (including XLEN=0 or 65535), NUL-terminated FNAME and FCOMMENT without
allocating or retaining metadata. Optional FHCRC is compared with the low
sixteen bits of CRC-32 over all preceding header bytes, including optional fields
and their terminators. Payload CRC-32 and little-endian ISIZE are verified;
ISIZE tracks each member's decoded length modulo 2^32.

Default mode stops after **one member**, leaving all following whole bytes
unconsumed. To decode a sequence, call `state.reset(limits, true)` or the
one-shot helper with `allMembers=true`. In this mode:

- Each member gets fresh raw history/tables and fresh payload/header checksums.
- `memberCount` increments only when both trailer checks pass.
- Budgets and input/output totals span the entire sequence; members cannot
  replenish them. No previous member's history is available to a new member.
- At a valid member boundary, nonfinal empty input requests more input. Final
  empty input completes the sequence. If bytes remain, they must form another
  complete member. Arbitrary suffixes and zero padding are rejected, rather
  than silently discarded. Empty input without any member is truncation.

## Limits and error categories

The M0 inclusive absolute-output and conservative prefix-ratio policies apply
before each literal/full match, independently of output chunk size. Framed
ratios include only headers and other framing bytes **already consumed** through
that token; available but unconsumed trailers do not increase the budget.
For GZIP sequences this includes earlier members' trailers and headers.
All cumulative additions are checked for overflow. Absolute budgets are still
useful when streams carry large amounts of optional metadata; metadata is
streamed with bounded storage and counts as encoded input under the ratio rule.

Invalid headers use `invalidHeader`; bad header CRC, data CRC/Adler or ISIZE use
`checksumMismatch`. Raw codec errors retain their categories. Budget failures
are terminal, while output starvation alone yields `needOutput`. An exact
budget or empty output buffer can still parse/verify a trailer and finish.

## Verification

Run `bash scripts/check-framing.sh` for both compilers, or pass one compiler
path as an argument (also used by the GitHub Actions matrix). The script runs
checksum/frame tests and independent attribute probes, then compares a compiled
Pure-D oracle with Python zlib. `dub test` runs the saved corpus and unit tests
without Python/zlib as runtime dependencies of the library or tests.

Verified locally under DMD 2.111.0 and LDC 1.42.0:

- 20 saved frames independently compressed/validated using Python zlib 1.3.2:
  empty/stored/fixed/dynamic/overlap/Huffman-only/distance data and optional
  GZIP fields. Output is compared byte for byte in one shot and with input/output
  steps 1/1 and 3/7. Guards and suffix sentinels check exact counts/bounds.
- Every truncation position of small zlib/GZIP/all-optional examples, bad
  headers/trailers/FHCRC, dictionary requests, every legal zlib window and a
  forbidden distance beyond an advertised small window, and both XLEN extremes.
- Empty/exact/exceeded budgets, expansion ratios including framing bytes,
  chunk-independent rejection boundaries, cumulative budgets/member counts,
  reset/isolation, reused output buffers, forbidden cross-member history and
  ISIZE rollover. Counters also have direct overflow probes.
- A reproducible differential run (seed 1952) covers 1,001 inputs: 341 valid
  frames agree on output size, SHA-256 and exact consumed byte count; 660
  malformed/truncated frames are rejected by both implementations. It includes
  all 32 combinations of defined GZIP flags and concatenated-member cases.
  Counts may vary with zlib's encoder version. The oracle caps output at 1 MiB.

Saved fixtures come from `scripts/generate-framing-fixtures.py`. Generated
output can vary across zlib versions; saved tests need no regeneration.
CI adds these checks to the existing M0/M1/M2 gates. Consumer performance and
end-to-end TIFF/PNG validation remain M4.

Format references: [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950.html),
[RFC 1952](https://www.rfc-editor.org/rfc/rfc1952.html).

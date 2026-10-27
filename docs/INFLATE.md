# Experimental raw Inflate (M2)

`compression.deflate` implements one raw RFC 1951 stream: stored, fixed-Huffman
and dynamic-Huffman blocks, length/distance extra bits, and overlapping LZ77
copies through a 32-KiB ring window. Headers, repeat codes, end-of-block symbols,
reserved symbols, tree validity and available history are checked. Dynamic
headers declaring more than 286 literal/length or 30 distance symbols are
rejected, matching zlib's reserved-alphabet checks.

zlib/GZIP framing and checksums are implemented separately in M3; see
[the framing contract](FRAMING.md). Preset dictionaries and an encoder remain
unimplemented. The raw implementation uses no C backend and remains experimental.

## Ownership and calls

The caller supplies a default-initialized `InflateState` and
`InflateWorkspace`. The workspace owns fixed Huffman tables, temporary code
length arrays and the history window. Neither type contains pointers or slices.
Every core operation compiles as `@safe pure nothrow @nogc` with DIP1000 enabled.
Input/output slices are borrowed only for the call and must not overlap each
other, state or workspace. Concurrent operations require separate pairs.

```d
import compression.core;
import compression.deflate;

InflateState state;
InflateWorkspace workspace;
state.reset(DecodeLimits(16 * 1024 * 1024)); // absolute cumulative output budget
auto result = inflate(state, workspace, input, output, endOfInput);
```

`inflate` accepts `(ref state, ref workspace, scope input, scope output,
bool endOfInput = false)` and returns the core `Result` contract. Counts are
per-call; `state.totalInput` and `state.totalOutput` are cumulative `ulong`
counters. `state.reset(limits)` starts a new operation with new budgets. Default
initialization disables policy limits; arithmetic checks remain active.

- On `needInput`, preserve `input[result.consumed .. $]` and append more input.
  The reader rolls back incomplete fields/symbols, so the unread suffix may be
  nonempty even though more input is needed. A single operation needs at most
  two new bytes; the caller must be able to assemble that amount. Resubmit with
  a fresh input slice and use the same state/workspace pair.
- On `needOutput`, consume the reported input prefix and supply another output
  buffer. Output need not be contiguous or remain alive after returning: match
  history lives entirely in the workspace. Pending literals/matches live in state.
- Set `endOfInput` when no more encoded bytes will arrive. A required missing
  field becomes `truncatedInput`. Final input can still return `needOutput`;
  preserve finality when resuming with the remaining suffix.
- `done` ends exactly one raw stream, discards unused bits in its last byte,
  and leaves all subsequent whole bytes unconsumed. Empty output capacity can
  still finish an empty stream or parse an end-of-block marker.
- Reset after `done` or `error`. Calling again after `done` returns
  `invalidArgument`. Calling again after an error repeats the saved error with
  zero progress. Reset needs no workspace clearing: history starts empty and
  tables/length ranges are initialized before use.

`inflateRaw(input, output, ref workspace, limits)` is a one-shot convenience
call with final input and a temporary state. `needOutput` returns a valid output
prefix, but resuming requires the stateful API from the start. Use a sufficiently
large output buffer or the stateful form when the decoded size is unknown.

## Validation and budgets

All blocks contribute to the same history and counters; block boundaries do
not replenish budgets. A literal (including a stored byte) is checked as one
output increment. A complete LZ77 match is checked as one increment before any
of its bytes are emitted, independently of output chunk size. After approval,
that match may be emitted across many calls. A rejected match writes none of
that match; output from earlier tokens is still valid.

Output growth uses the M0 inclusive absolute and conservative prefix-expansion
rules. Expansion uses encoded bytes actually consumed through the current token,
not the available input length or speculative lookup bytes. Empty final blocks
are valid at an exact output budget. Policy errors are terminal; an exhausted
output slice alone yields `needOutput` once a pending output token exists.

Errors return structured categories and absolute byte diagnostics. Truncation
points at the final input length; other diagnostics identify the last accounted
input byte at detection (not a precise bit position). `LEN`/`NLEN`, reserved
length codes and malformed data use `invalidData`; bad tree/repeat descriptions
use `invalidHuffmanTree`; reserved or unavailable distances use `invalidDistance`;
reserved block types/alphabet counts use `invalidHeader`.

## Verification and reproduction

Run `bash scripts/check-inflate.sh` with DMD, LDC and Python 3 available. It runs
unit tests, an independent attribute/ownership consumer probe, and generated
differential cases against Python zlib under each compiler. `dub test` includes
the checked-in Inflate tests without requiring Python or zlib at runtime.

Evidence from DMD 2.111.0, LDC 1.42.0 and Python zlib 1.3.2:

- 15 saved independently compressed/decoded fixtures cover all block types,
  Huffman-only/RLE strategies, sync/full flush block boundaries, random bytes,
  overlapping copies and history wrap beyond 32 KiB. Plaintext is compared byte
  for byte in one shot and with input/output steps 1/1, 3/7 and 127/258.
- All truncation positions of representative stored/fixed/dynamic streams are
  checked, along with repeat 16 without a previous length, repeat overrun,
  missing EOB, oversubscribed trees, reserved symbols/types/counts and bad NLEN.
- Handwritten valid streams exercise repeats 16/17/18, repeats across the
  literal/distance boundary, singleton EOB/empty distance alphabets, maximum
  stored length 65535, every length/distance extra-bit range endpoint, exact
  distance 32768, overlap and cross-block/window-wrap history.
- Limit checks cover zero/exact/exceeded budgets, expansion bombs, rejected-token
  output guards, chunk-independent rejection boundaries and counter overflow.
  Alternating independent decoder pairs and reused/overwritten output buffers
  test workspace isolation and reset.
- The reproducible differential runner uses seed 1951 and 822 inputs: 408 valid
  cases agree on output length, SHA-256 and exact encoded byte consumption;
  414 malformed/truncated cases are rejected by both zlib and Pure-D. Counts can
  vary with zlib's compressor version. Each oracle has a 1-MiB safety cap.

Saved fixtures were generated by `scripts/generate-inflate-fixtures.py`; run
`python3 scripts/generate-inflate-fixtures.py --check tests/inflate_fixtures.d`
to compare them with the local encoder. Different zlib versions can encode the
same data differently, so regeneration equality is not a CI requirement.
The generated corpus and mutation checks are correctness evidence, not exhaustive
fuzzing or a performance claim. Consumer benchmarks remain M4.

Format reference: [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951.html).
Independent oracle: [zlib](https://github.com/madler/zlib).

# Experimental core contract

M0 defines the vocabulary for future decoders in `compression.core`. It does
not yet implement a decoder or promote a stable package API. Import this module
explicitly; `compression` does not re-export it.

## Results and streaming

`Result.consumed` and `Result.produced` count bytes from the input and output
slices of **this call**. They never exceed the corresponding slice lengths.
Only the first `produced` output bytes are valid. Counts remain meaningful on
errors: output from earlier successful operations is not rolled back. Bytes
after `consumed` remain the caller's input, including trailing container data.

| Status | Meaning and caller action |
| --- | --- |
| `done` | The stream, including any required trailer/checksum, is complete. |
| `needInput` | Provide more input; preserve decoder state and workspace. |
| `needOutput` | Provide more output capacity; preserve decoder state and workspace. |
| `error` | Inspect `error.code` and `error.inputOffset`; reset before reuse. |

Non-error results have `ErrorCode.none` and an unknown error offset. The result
factories establish this invariant; the structs remain plain values, so a
consumer can construct an inconsistent aggregate and must not pass it off as
a decoder result. `Result.init` requests input with zero progress.

Future decode entry points must accept an explicit `endOfInput` flag. A decoder
that requires more bytes returns `needInput` while this flag is false and
`truncatedInput` once it is true. Final input may still return `needOutput`;
the caller must resubmit the unconsumed suffix with finality preserved.
An empty slice is not itself an end-of-stream signal. `done` may require no
output capacity (for example for an empty stream). After `done` or `error`, a
new stream requires an explicit reset. A zero-progress resumable result must
identify the resource needed; callers must not retry it without changing that
resource. Completion or a detected error takes precedence over resource requests.

Raw decoders stop at the end of one raw stream; framed decoders validate their
own headers and trailers. Whole bytes beyond that boundary are not consumed by
speculative bitreader lookahead. Any concatenated-member API must explicitly
define its boundary and preserve cumulative limits across members of one decode
operation. These rules do not force codecs into one common streaming interface.

## Structured errors

`DecodeError` contains a category and an absolute, zero-based encoded input byte
offset. Unknown or inapplicable offsets use `DecodeError.unknownOffset`.
An error at end-of-input can use the stream length. Offsets are diagnostic
positions, not per-call consumption counts or bit offsets. Errors hold no
strings, exceptions, borrowed slices or allocations.

| Category | Meaning |
| --- | --- |
| `invalidArgument` | Invalid caller configuration or state usage. |
| `workspaceTooSmall` | Caller-provided variable workspace storage is insufficient. |
| `sizeOverflow` | A cumulative count or required size cannot be represented. |
| `outputLimitExceeded` | Proposed output exceeds the absolute byte budget. |
| `expansionLimitExceeded` | Proposed output exceeds the enabled expansion budget. |
| `truncatedInput` | Final input ended before the stream was complete. |
| `invalidHeader` | Malformed framing/header fields. |
| `invalidData` | Malformed encoded data not covered by a more specific category. |
| `invalidHuffmanTree` | Invalid code tree for the codec's rules. |
| `invalidDistance` | Invalid backward reference or unavailable history. |
| `checksumMismatch` | Computed and encoded integrity checks differ. |
| `dictionaryRequired` | The stream requires a preset dictionary not supplied. |
| `unsupportedFeature` | A recognized feature is outside the decoder's supported subset. |

`none` is never a failure category; `Result.failure` converts it and out-of-range
enum values to `invalidArgument`. Numeric enum values are not a stable ABI.
Codec-specific validation order will be documented with each decoder.

## Limits and checked accounting

`DecodeLimits` applies to the entire decode operation, not each input/output
chunk. Keep limits constant while resuming. Counters are `ulong` on both 32-bit
and 64-bit hosts; per-call slice counts are `size_t`. `advanceInput` checks
cumulative input addition and leaves the counter unchanged on overflow.

Before emitting an increment, call `checkGrowth(totalInput, totalOutput,
additionalOutput)`. It does not mutate counters or buffers. Commit the output
counter only after the corresponding bytes are written. If an increment fails,
none of that increment may be written. Earlier validated increments may already
have produced output, reflected in the result counts.

- `maxOutputBytes` is inclusive. Zero permits only empty output. The default
  `ulong.max` imposes no smaller policy bound; arithmetic is still checked.
- `maxExpansionRatio` is an inclusive integer multiplier. Zero disables the
  ratio check. When enabled, the mathematical rule is
  `prospectiveOutput <= totalInput * maxExpansionRatio`. Zero input permits
  zero output only. Overflow in the mathematical product does not reject an
  otherwise representable output count.
- `totalInput` means encoded bytes actually consumed so far, never the available
  input slice length. Framed decoders include their consumed framing bytes.
  Prefetched bytes beyond the stream boundary must not inflate this budget.
- The ratio is checked at each output increment, not only at stream completion.
  This conservative prefix rule can reject a stream whose final ratio would
  fit. Use an absolute output budget alone when a caller needs final-ratio
  semantics or knows the expected decompressed length. Limit-check increments
  must be defined by each codec independently of the caller's output chunk size.
- Checks report arithmetic overflow first, then the absolute bound, then the
  ratio bound. A policy failure is terminal, not `needOutput`. Exhausting only
  the current output slice yields `needOutput` if more output is required.
  Reaching the exact budget does not itself fail an empty or completed stream.

For example, with `DecodeLimits(12, 2)`, five consumed bytes permit at most ten
output bytes. Seven consumed bytes would permit fourteen by ratio, but the
absolute limit still permits only twelve. Splitting the output into calls does
not replenish either budget.

## Ownership and workspace decision

Use **codec-specific typed workspaces**, supplied by `ref`, rather than a
universal raw scratch slice API. Fixed arrays in these types provide alignment,
known bounds and allocation-free default initialization. A future Inflate
workspace will own its history window and Huffman storage; their exact layout
and sizes are deferred to M1/M2. No guessed Inflate allocation is introduced in
M0. A codec must expose its workspace type/size before its API stabilizes.
If a codec later needs variable storage, a separate documented caller-owned
contract must validate its capacity before decode and use `workspaceTooSmall`.

The caller owns input, output, decoder state and workspace. Decode entry points
borrow input/output using `scope`; no input/output slice may survive the call.
Persistent data (including LZ77 history) must be copied into the workspace.
State holds progress/counters and must not retain references to call buffers or
workspace. The caller passes the same state/workspace pair on every resume.
Initialization/reset must establish valid state without reading uninitialized
workspace contents. Reset starts a new operation and resets its budgets.

Input, output, state and workspace must not overlap. One active decode owns a
pair exclusively; concurrent decodes need separate pairs. Sequential reuse
requires reset. Codec core operations must compile as `@safe @nogc nothrow`;
the current value-only helpers are also `pure`. No hidden global scratch or
implicit allocation is allowed.

## Verification

Run `bash scripts/check-core.sh` with DMD and LDC on PATH. It compiles and runs
core unit tests plus an independent consumer with explicit
`@safe pure nothrow @nogc` annotations and DIP1000 enabled. Tests cover result
invariants, zero/exact/exceeded limits, cumulative streaming budgets, error
precedence, and arithmetic at `ulong.max`. GitHub Actions runs the same probes
and a DUB library build for DMD 2.111.0 and LDC 1.42.0.

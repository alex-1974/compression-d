# Experimental bitstream and Huffman primitives

These M1 modules implement the bitreader/Huffman milestone. They are imported
explicitly, without re-exports from `compression`. There is no Inflate decoder
in this layer; M2 now provides it in `compression.deflate`, including the LZ77
window. Encoding, checksums and framing remain later work.

## Borrowed input and transactional reads

`BitReader` contains only an integer reservoir and a bit count. It retains at
most seven residual bits of the last consumed byte and no input references.
Operations take `scope const(ubyte)[] input` and an explicit byte `cursor`.

- `read(input, cursor, width, endOfInput)` reads an unsigned value LSB first.
  Widths 0..32 are valid; zero bits succeed with value zero.
- `peek` has identical value semantics but never changes reader or cursor.
- `drop` consumes bits like `read`, returning no value.
- `alignToByte` discards residual padding bits, returns their count, and does
  not read the next byte. `reset` clears the reservoir for a new stream.

`BitResult.status == done` means one primitive operation succeeded, not that
the entire stream ended. Failed reads, including truncation, leave reader and
cursor unchanged. Insufficient input returns `needInput`, or `truncatedInput`
when `endOfInput` is true. Widths above 32 and cursors beyond the slice return
`invalidArgument`. Values in non-success results are zero.

When retrying, keep the unread suffix `input[cursor .. $]`, append new bytes,
and pass that new slice with cursor zero. Do not replay already consumed bytes;
their residual bits already live in the reader. A caller may need to assemble
up to four bytes for a single 32-bit read. This policy avoids retaining input
slices and leaves ownership with the caller. A future codec may instead keep
partially parsed fields in its own state.

Neither normal reads nor Huffman lookahead commit whole bytes beyond the
requested operation. Lookahead may inspect bytes within the supplied slice,
but accounting advances only for the actual bits consumed. This matters when
a raw stream is immediately followed by a container trailer.

## Typed canonical Huffman workspace

`HuffmanTable!0` stores canonical counts, first codes, symbol offsets and up to
288 ordered symbols. `HuffmanTable!9` adds a 512-entry prefix lookup table and
falls back to canonical lookup for long codes or insufficient lookahead.
The default is `HuffmanTable!9`. Both are caller-owned fixed-size values,
contain no pointers, and allocate neither during construction nor decoding.
On the tested x86_64 compilers their sizes are 708 and 2,756 bytes respectively.
Use `HuffmanTable!(...).sizeof` on the target platform for allocation decisions.

`build(lengths, kind)` treats indices as symbols and zero lengths as absent
symbols. A successful build copies the information needed for lookup; it does
not borrow `lengths` after returning. Oversubscribed trees are always rejected.
Every build invalidates the previous table before validation, so a failed build
cannot accidentally expose stale codes.

| Tree kind | Validation |
| --- | --- |
| `complete` | 1..288 entries, lengths 0..15, nonempty complete tree. |
| `codeLength` | 1..19 entries, lengths 0..7, nonempty complete tree. |
| `literalLength` | 257..288 entries, lengths 0..15, symbol 256 present; complete or a single one-bit symbol. |
| `distance` | 1..32 entries, lengths 0..15; complete, single one-bit symbol, or empty alphabet. |

Wrong alphabet sizes or unknown kinds return `invalidArgument`; invalid lengths,
missing end-of-block, and forbidden incomplete trees return
`invalidHuffmanTree`. An accepted empty distance alphabet is ready but has no
decodable symbols: every decode attempt returns `invalidData` without reading.
Unused single-symbol branches also return `invalidData`.

`decode(reader, input, cursor, endOfInput)` returns a `SymbolResult` with the
symbol on success. It commits reader/cursor only after a complete code matches.
The same retry/finality rules apply as for bit reads. An unbuilt/invalidated
table returns `invalidArgument`. A short final code does not require nine bits
of padding just because the fast strategy has a nine-bit root table.

Numeric fields in DEFLATE are LSB first, but Huffman code bits are transmitted
MSB first. The canonical path assembles those bits in transmission order; the
prefix table reverses canonical codes for an LSB-indexed lookup. The construction
follows [RFC 1951, sections 3.1.1 and 3.2.2](https://www.rfc-editor.org/rfc/rfc1951.html).
The role-specific empty/single-symbol validation agrees with the reference
[zlib tree builder](https://github.com/madler/zlib/blob/master/inftrees.c).
No C implementation is linked or required by these modules.

Tables validate code structure, not all codec semantics. Fixed trees include
reserved symbols; a future Inflate decoder must reject their use and validate
dynamic header counts/repeats, distances and lengths. Bitwriter work is deferred
with the encoder. The history window and complete Inflate workspace remain M2.

## Verification

Run `bash scripts/check-primitives.sh` for DMD/LDC unit tests and separate
`@safe pure nothrow @nogc` consumer probes with DIP1000 enabled. `dub test
--compiler=dmd` and `dub test --compiler=ldc2` also include the Huffman tests.

Tests cover every read width at every byte alignment, read/peek equivalence,
transactional retry, final truncation, all fixed symbols, codes up to fifteen
bits, table reuse after failed builds, all 15,625 six-symbol length vectors over
0..4 against an independent Kraft-sum oracle, and both lookup strategies.
The RFC's eight-symbol example is a hand-specified code oracle.

An independent raw fixed-block fixture for `hello` is `cb48cdc9c90700`, generated
with Python's zlib, `compressobj(level=6, wbits=-15, strategy=zlib.Z_FIXED)`.
Tests read its block header, literal symbols and end-of-block symbol and check
that following sentinel bytes remain unconsumed. Python/zlib is not required
to run the checked-in tests. This is primitive interoperability evidence, not
a completed differential Inflate corpus.

See [the benchmark report](HUFFMAN_BENCHMARKS.md) for lookup measurements.

module huffman_tests;

import compression.bitstream;
import compression.core;
import compression.huffman;

// Independent test-only bit packer: canonical codes are transmitted MSB first,
// even though the containing bytes fill from least to most significant bit.
private void appendCode(ref ubyte[1024] data, ref uint position,
    uint code, uint width) @safe pure nothrow @nogc
{
    foreach_reverse (uint bit; 0 .. width)
    {
        data[position / 8] |= ((code >> bit) & 1) << (position % 8);
        ++position;
    }
}

@safe pure nothrow @nogc unittest
{
    // RFC 1951 section 3.2.2: A..H have canonical codes
    // 010, 011, 100, 101, 110, 00, 1110, 1111.
    immutable ubyte[8] lengths = [3, 3, 3, 3, 3, 2, 4, 4];
    immutable uint[8] codes = [2, 3, 4, 5, 6, 0, 14, 15];
    foreach (uint alignment; 0 .. 8)
    {
        ubyte[1024] packed;
        uint position = alignment;
        foreach (index, code; codes)
            appendCode(packed, position, code, lengths[index]);
        foreach (rootBits; AliasSeq!(0, 9))
        {
            HuffmanTable!rootBits table;
            assert(table.build(lengths) == ErrorCode.none);
            BitReader reader;
            size_t cursor;
            reader.drop(packed, cursor, alignment);
            foreach (ushort symbol; 0 .. 8)
            {
                auto decoded = table.decode(reader, packed[0 .. (position + 7) / 8], cursor, true);
                assert(decoded.status == DecodeStatus.done && decoded.symbol == symbol);
            }
            assert(cursor == (position + 7) / 8);
        }
    }
}

import std.meta : AliasSeq;

@safe pure nothrow @nogc unittest
{
    // Independent Kraft-sum oracle: all 5^6 length vectors over lengths 0..4.
    HuffmanTable!0 compact;
    HuffmanTable!9 fast;
    foreach (uint vector; 0 .. 15_625)
    {
        ubyte[6] lengths;
        uint remaining = vector;
        uint slots;
        foreach (ref length; lengths)
        {
            length = cast(ubyte)(remaining % 5);
            remaining /= 5;
            if (length != 0)
                slots += 1U << (4 - length);
        }
        const expected = slots == 16 ? ErrorCode.none : ErrorCode.invalidHuffmanTree;
        assert(compact.build(lengths) == expected);
        assert(fast.build(lengths) == expected);
    }
}

@safe pure nothrow @nogc unittest
{
    // Independent fixture: Python zlib Z_FIXED, wbits=-15, input b"hello".
    // Trailing sentinels must remain untouched even by the root-table peek.
    immutable ubyte[9] encoded = [0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00, 0xA5, 0x5A];
    immutable ushort[6] expected = ['h', 'e', 'l', 'l', 'o', 256];
    ubyte[288] lengths;
    foreach (uint symbol; 0 .. 288)
        lengths[symbol] = cast(ubyte)(symbol < 144 ? 8 : symbol < 256 ? 9 : symbol < 280 ? 7 : 8);
    foreach (rootBits; AliasSeq!(0, 9))
    {
        HuffmanTable!rootBits table;
        assert(table.build(lengths, TreeKind.literalLength) == ErrorCode.none);
        BitReader reader;
        size_t cursor;
        assert(reader.read(encoded, cursor, 1, true).value == 1); // BFINAL
        assert(reader.read(encoded, cursor, 2, true).value == 1); // BTYPE=fixed
        foreach (symbol; expected)
        {
            const decoded = table.decode(reader, encoded, cursor, true);
            assert(decoded.status == DecodeStatus.done && decoded.symbol == symbol);
        }
        assert(cursor == 7 && reader.bufferedBits == 6);
        reader.alignToByte();
        assert(reader.read(encoded, cursor, 8, true).value == 0xA5);
    }
}

@safe pure nothrow @nogc unittest
{
    foreach (rootBits; AliasSeq!(0, 9))
    {
        HuffmanTable!rootBits table;
        immutable ubyte[2] complete = [1, 1];
        immutable ubyte[3] oversubscribed = [1, 1, 1];
        immutable ubyte[2] incomplete = [2, 2];
        immutable ubyte[2] tooLong = [16, 1];
        assert(table.build(complete) == ErrorCode.none && table.isReady);
        assert(table.build(oversubscribed) == ErrorCode.invalidHuffmanTree);
        assert(!table.isReady);
        BitReader reader;
        size_t cursor;
        assert(table.decode(reader, null, cursor).error == ErrorCode.invalidArgument);
        assert(table.build(incomplete) == ErrorCode.invalidHuffmanTree);
        assert(table.build(tooLong) == ErrorCode.invalidHuffmanTree);
        assert(table.build(null) == ErrorCode.invalidArgument);
        ubyte[289] oversized;
        assert(table.build(oversized) == ErrorCode.invalidArgument);
        assert(table.build(complete, cast(TreeKind)255) == ErrorCode.invalidArgument);
        assert(table.build(complete, TreeKind.literalLength) == ErrorCode.invalidArgument);
        ubyte[33] distances;
        assert(table.build(distances, TreeKind.distance) == ErrorCode.invalidArgument);
        ubyte[20] codeLengths;
        assert(table.build(codeLengths, TreeKind.codeLength) == ErrorCode.invalidArgument);
        immutable ubyte[2] longCodeLengths = [8, 8];
        assert(table.build(longCodeLengths, TreeKind.codeLength) == ErrorCode.invalidHuffmanTree);
        assert(table.build(incomplete, TreeKind.codeLength) == ErrorCode.invalidHuffmanTree);
        immutable ubyte[2] singleton = [0, 1];
        assert(table.build(singleton) == ErrorCode.invalidHuffmanTree);
        assert(table.build(singleton, TreeKind.distance) == ErrorCode.none);
        immutable ubyte[1] validBit = [0];
        assert(table.decode(reader, validBit, cursor, true).symbol == 1);
        reader.reset(); cursor = 0;
        immutable ubyte[1] invalidBit = [1];
        assert(table.decode(reader, invalidBit, cursor, true).error == ErrorCode.invalidData);
        assert(cursor == 0 && reader.bufferedBits == 0);
        ubyte[1] empty;
        assert(table.build(empty, TreeKind.distance) == ErrorCode.none);
        assert(table.decode(reader, null, cursor).error == ErrorCode.invalidData);
        assert(table.build(empty, TreeKind.codeLength) == ErrorCode.invalidHuffmanTree);
        ubyte[257] literals;
        literals[0] = 1;
        assert(table.build(literals, TreeKind.literalLength) == ErrorCode.invalidHuffmanTree);
        literals[0] = 0; literals[256] = 1;
        assert(table.build(literals, TreeKind.literalLength) == ErrorCode.none);
        assert(table.decode(reader, validBit, cursor, true).symbol == 256);
    }
}

@safe pure nothrow @nogc unittest
{
    // A complete maximally deep tree: lengths 1..14 followed by two 15s.
    // Symbol i<15 has i one bits then a zero; symbol 15 has fifteen ones.
    ubyte[16] lengths;
    foreach (uint symbol; 0 .. 16)
        lengths[symbol] = cast(ubyte)(symbol < 15 ? symbol + 1 : 15);
    foreach (rootBits; AliasSeq!(0, 9))
    {
        HuffmanTable!rootBits table;
        assert(table.build(lengths) == ErrorCode.none);
        foreach (uint alignment; 0 .. 8)
        foreach (uint symbol; 0 .. 16)
        {
            ubyte[1024] packed;
            uint position = alignment;
            const width = lengths[symbol];
            const code = symbol == 15 ? 32767 : (1U << width) - 2;
            appendCode(packed, position, code, width);
            foreach (size_t available; 0 .. (position + 7) / 8 + 1)
            {
                BitReader reader;
                size_t cursor;
                // Alignment is established independently of truncated test input.
                reader.drop(packed, cursor, alignment);
                const before = cursor;
                const buffered = reader.bufferedBits;
                if (available < cursor)
                    continue;
                const result = table.decode(reader, packed[0 .. available], cursor);
                if (available * 8 < position)
                {
                    assert(result.status == DecodeStatus.needInput);
                    assert(cursor == before && reader.bufferedBits == buffered);
                    const finalResult = table.decode(reader, packed[0 .. available], cursor, true);
                    assert(finalResult.error == ErrorCode.truncatedInput);
                    assert(cursor == before && reader.bufferedBits == buffered);
                    // Retry the same unread suffix with additional input.
                    const resumed = table.decode(reader, packed[0 .. (position + 7) / 8], cursor, true);
                    assert(resumed.status == DecodeStatus.done && resumed.symbol == symbol);
                }
                else
                    assert(result.status == DecodeStatus.done && result.symbol == symbol);
                assert(cursor == (position + 7) / 8);
            }
        }
    }
}

@safe pure nothrow @nogc unittest
{
    // RFC fixed literal/length alphabet; all 288 codes, including reserved
    // symbols, are decoded structurally (the future codec validates semantics).
    ubyte[288] lengths;
    foreach (uint symbol; 0 .. 288)
        lengths[symbol] = cast(ubyte)(symbol < 144 ? 8 : symbol < 256 ? 9 : symbol < 280 ? 7 : 8);
    HuffmanTable!0 compact;
    HuffmanTable!9 fast;
    assert(compact.build(lengths, TreeKind.literalLength) == ErrorCode.none);
    assert(fast.build(lengths, TreeKind.literalLength) == ErrorCode.none);
    ubyte[1024] packed;
    uint position;
    foreach (uint symbol; 0 .. 288)
    {
        const code = symbol < 144 ? symbol + 48 : symbol < 256 ? symbol + 256 :
            symbol < 280 ? symbol - 256 : symbol - 88;
        appendCode(packed, position, code, lengths[symbol]);
    }
    BitReader compactReader, fastReader;
    size_t compactCursor, fastCursor;
    foreach (uint symbol; 0 .. 288)
    {
        const a = compact.decode(compactReader, packed, compactCursor, true);
        const b = fast.decode(fastReader, packed, fastCursor, true);
        assert(a.status == DecodeStatus.done && a.symbol == symbol);
        assert(b.status == DecodeStatus.done && b.symbol == symbol);
        assert(compactCursor == fastCursor && compactReader.bufferedBits == fastReader.bufferedBits);
    }
}

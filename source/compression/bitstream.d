/// Allocation-free LSB-first bit operations. Input is borrowed for each call.
module compression.bitstream;

import compression.core : DecodeStatus, ErrorCode;

/// `done` means this operation succeeded, not that an encoded stream ended.
struct BitResult
{
    DecodeStatus status = DecodeStatus.needInput;
    uint value;
    ErrorCode error = ErrorCode.none;
}

/** A reader retains at most seven residual bits, never a slice or whole lookahead
    bytes. cursor indexes the input of this call. Failed operations and peek
    leave both reader and cursor unchanged; resubmit the unconsumed suffix with
    more data. See docs/PRIMITIVES.md for the streaming contract. */
struct BitReader
{
    private uint residual;
    private uint remaining;

    @safe pure nothrow @nogc:

    @property uint bufferedBits() const { return remaining; }

    void reset()
    {
        residual = 0;
        remaining = 0;
    }

    BitResult read(scope const(ubyte)[] input, ref size_t cursor,
        uint width, bool endOfInput = false)
    {
        if (width > 32 || cursor > input.length)
            return BitResult(DecodeStatus.error, 0, ErrorCode.invalidArgument);
        ulong bits = residual;
        uint available = remaining;
        size_t next = cursor;
        while (available < width)
        {
            if (next == input.length)
                return endOfInput ?
                    BitResult(DecodeStatus.error, 0, ErrorCode.truncatedInput) :
                    BitResult.init;
            bits |= cast(ulong) input[next++] << available;
            available += 8;
        }
        const value = cast(uint)(bits & ((1UL << width) - 1));
        residual = cast(uint)(bits >> width);
        remaining = available - width;
        cursor = next;
        return BitResult(DecodeStatus.done, value);
    }

    BitResult peek(scope const(ubyte)[] input, size_t cursor,
        uint width, bool endOfInput = false) const
    {
        BitReader copy;
        copy.residual = residual;
        copy.remaining = remaining;
        return copy.read(input, cursor, width, endOfInput);
    }

    BitResult drop(scope const(ubyte)[] input, ref size_t cursor,
        uint width, bool endOfInput = false)
    {
        auto result = read(input, cursor, width, endOfInput);
        result.value = 0;
        return result;
    }

    /// Discard padding to the next byte boundary without reading another byte.
    uint alignToByte()
    {
        const discarded = remaining;
        reset();
        return discarded;
    }
}

@safe pure nothrow @nogc unittest
{
    immutable ubyte[6] input = [0xD6, 0x39, 0xAB, 0xCD, 0xEF, 0x7A];
    BitReader reader;
    size_t cursor;
    assert(reader.peek(input, cursor, 3).value == 6);
    assert(cursor == 0 && reader.bufferedBits == 0);
    assert(reader.read(input, cursor, 3).value == 6);
    assert(cursor == 1 && reader.bufferedBits == 5);
    assert(reader.read(input, cursor, 7).value == 0x3A);
    assert(cursor == 2 && reader.bufferedBits == 6);
    assert(reader.alignToByte() == 6);
    assert(reader.read(input, cursor, 32).value == 0x7AEFCDAB);
    assert(cursor == 6 && reader.bufferedBits == 0);
    assert(reader.read(input, cursor, 0).status == DecodeStatus.done);
    assert(reader.read(input, cursor, 1).status == DecodeStatus.needInput);
    assert(reader.read(input, cursor, 1, true).error == ErrorCode.truncatedInput);
    assert(reader.read(input, cursor, 33).error == ErrorCode.invalidArgument);
    cursor = input.length + 1;
    assert(reader.read(input, cursor, 0).error == ErrorCode.invalidArgument);
}

@safe pure nothrow @nogc unittest
{
    // Independent per-bit oracle at every alignment and supported read width.
    immutable ubyte[6] input = [0xD6, 0x39, 0xAB, 0xCD, 0xEF, 0x7A];
    foreach (uint offset; 0 .. 8)
    foreach (uint width; 0 .. 33)
    {
        BitReader reader;
        size_t cursor;
        assert(reader.drop(input, cursor, offset).status == DecodeStatus.done);
        uint expected;
        foreach (uint bit; 0 .. width)
            expected |= ((input[(offset + bit) / 8] >> ((offset + bit) % 8)) & 1) << bit;
        auto peeked = reader.peek(input, cursor, width, true);
        assert(peeked.status == DecodeStatus.done && peeked.value == expected);
        auto actual = reader.read(input, cursor, width, true);
        assert(actual.status == DecodeStatus.done && actual.value == expected);
        assert(cursor == (offset + width + 7) / 8);
        assert(reader.bufferedBits < 8);
    }
}

@safe pure nothrow @nogc unittest
{
    immutable ubyte[3] input = [0xD6, 0x39, 0xAB];
    foreach (size_t split; 0 .. input.length)
    {
        BitReader reader;
        size_t cursor;
        assert(reader.read(input, cursor, 3).status == DecodeStatus.done);
        const before = cursor;
        const buffered = reader.bufferedBits;
        assert(reader.read(input[0 .. split + 1], cursor, 21).status ==
            (split == 2 ? DecodeStatus.done : DecodeStatus.needInput));
        if (split != 2)
        {
            assert(cursor == before && reader.bufferedBits == buffered);
            assert(reader.read(input[0 .. split + 1], cursor, 21, true).error ==
                ErrorCode.truncatedInput);
            assert(reader.read(input, cursor, 21, true).value == 0x15673A);
        }
    }
}

/// Package-internal checked byte accounting shared by framing adapters.
module compression.framing;
import compression.core;

package(compression) struct FrameCounters
{
    ulong input, output;
    DecodeError failure;

    @safe pure nothrow @nogc:
    Result fail(ErrorCode code, size_t consumed, size_t produced,
        ulong offset = DecodeError.unknownOffset)
    {
        if (offset == DecodeError.unknownOffset)
            offset = input == 0 ? 0 : input - 1;
        failure = DecodeError(code, offset);
        return Result.failure(code, consumed, produced, offset);
    }
    Result shortage(size_t consumed, size_t produced, bool finalInput)
    {
        return finalInput ? fail(ErrorCode.truncatedInput, consumed, produced, input) :
            Result.needInput(consumed, produced);
    }
    ErrorCode take(scope const(ubyte)[] bytes, ref size_t cursor, out ubyte value)
    {
        assert(cursor < bytes.length);
        if (advanceInput(input, 1) != ErrorCode.none)
            return ErrorCode.sizeOverflow;
        value = bytes[cursor++];
        return ErrorCode.none;
    }
    ErrorCode account(Result result)
    {
        if (advanceInput(input, result.consumed) != ErrorCode.none ||
            advanceInput(output, result.produced) != ErrorCode.none)
            return ErrorCode.sizeOverflow;
        return ErrorCode.none;
    }
    ulong translated(ulong base, ulong offset) const
    {
        if (offset == DecodeError.unknownOffset || advanceInput(base, offset) != ErrorCode.none)
            return DecodeError.unknownOffset;
        return base;
    }
}

@safe pure nothrow @nogc unittest
{
    FrameCounters counts;
    counts.input = ulong.max;
    immutable ubyte[1] input = [1];
    size_t cursor;
    ubyte value;
    assert(counts.take(input, cursor, value) == ErrorCode.sizeOverflow && cursor == 0);
    assert(counts.translated(ulong.max - 1, 2) == DecodeError.unknownOffset);
    counts = FrameCounters.init;
    counts.output = ulong.max;
    assert(counts.account(Result.done(0, 1)) == ErrorCode.sizeOverflow);
}

/// RFC 1952 GZIP members, optional headers and streaming CRC/ISIZE validation.
module compression.gzip;
import compression.core;
import compression.checksum;
import compression.deflate;
import compression.framing;

private enum Phase : ubyte
{
    header, extraSize, extra, name, comment, headerCrc,
    payload, trailerCrc, trailerSize, memberEnd, finished,
}

struct GzipState
{
    private Phase phase;
    private FrameCounters counts;
    private InflateState raw;
    private DecodeLimits limits;
    private Crc32 checksum, headerChecksum;
    private uint flags, index, field, extraRemaining, memberSize;
    private ulong payloadStart, members;
    private bool concatenated;

    @safe pure nothrow @nogc:
    @property ulong totalInput() const { return counts.input; }
    @property ulong totalOutput() const { return counts.output; }
    @property ulong memberCount() const { return members; }
    /// Default: one member, leaving any following bytes unconsumed. Concatenated
    /// mode requires final input to distinguish completion from another member.
    void reset(DecodeLimits newLimits = DecodeLimits.init, bool allMembers = false)
    {
        this = GzipState.init;
        limits = newLimits;
        concatenated = allMembers;
    }

    private void nextOptional()
    {
        index = 0; field = 0;
        if ((flags & 4) != 0) { flags &= ~4U; phase = Phase.extraSize; }
        else if ((flags & 8) != 0) { flags &= ~8U; phase = Phase.name; }
        else if ((flags & 16) != 0) { flags &= ~16U; phase = Phase.comment; }
        else if ((flags & 2) != 0) { flags &= ~2U; phase = Phase.headerCrc; }
        else
        {
            phase = Phase.payload;
            payloadStart = counts.input;
            raw.resetFrame(limits, counts.input, counts.output);
        }
    }

    private void recordOutput(scope const(ubyte)[] bytes)
    {
        checksum.update(bytes);
        memberSize += cast(uint) bytes.length; // RFC ISIZE modulo 2^32.
    }
}

Result decodeGzip(ref GzipState state, ref InflateWorkspace workspace,
    scope const(ubyte)[] input, scope ubyte[] output, bool endOfInput = false)
    @safe pure nothrow @nogc
{
    size_t consumed, produced;
    if (state.counts.failure.code != ErrorCode.none)
        return Result.failure(state.counts.failure.code, 0, 0, state.counts.failure.inputOffset);
    if (state.phase == Phase.finished) return Result.failure(ErrorCode.invalidArgument);
    while (true)
    {
        if (state.phase == Phase.payload)
        {
            auto result = inflate(state.raw, workspace, input[consumed .. $], output[produced .. $], endOfInput);
            state.recordOutput(output[produced .. produced + result.produced]);
            consumed += result.consumed; produced += result.produced;
            const error = state.counts.account(result);
            if (error != ErrorCode.none) return state.counts.fail(error, consumed, produced);
            if (result.status == DecodeStatus.error)
                return state.counts.fail(result.error.code, consumed, produced,
                    state.counts.translated(state.payloadStart, result.error.inputOffset));
            if (result.status == DecodeStatus.needInput) return Result.needInput(consumed, produced);
            if (result.status == DecodeStatus.needOutput) return Result.needOutput(consumed, produced);
            state.phase = Phase.trailerCrc;
            state.index = 0; state.field = 0;
        }
        if (state.phase == Phase.memberEnd)
        {
            if (!state.concatenated || (consumed == input.length && endOfInput))
            {
                state.phase = Phase.finished;
                return Result.done(consumed, produced);
            }
            if (consumed == input.length) return Result.needInput(consumed, produced);
            state.phase = Phase.header;
            state.index = 0; state.field = 0; state.flags = 0;
            state.memberSize = 0;
            state.checksum.reset(); state.headerChecksum.reset();
        }
        if (consumed == input.length)
            return state.counts.shortage(consumed, produced, endOfInput);
        ubyte value;
        const error = state.counts.take(input, consumed, value);
        if (error != ErrorCode.none) return state.counts.fail(error, consumed, produced);
        if (state.phase == Phase.header || state.phase == Phase.extraSize ||
            state.phase == Phase.extra || state.phase == Phase.name || state.phase == Phase.comment)
            state.headerChecksum.updateByte(value);
        final switch (state.phase)
        {
        case Phase.header:
            if ((state.index == 0 && value != 31) || (state.index == 1 && value != 139) ||
                (state.index == 2 && value != 8) || (state.index == 3 && (value & 0xE0) != 0))
                return state.counts.fail(ErrorCode.invalidHeader, consumed, produced);
            if (state.index == 3) state.flags = value;
            if (++state.index == 10) state.nextOptional();
            break;
        case Phase.extraSize:
            state.field |= cast(uint) value << (state.index++ * 8);
            if (state.index == 2)
            {
                state.extraRemaining = state.field;
                if (state.extraRemaining == 0) state.nextOptional();
                else state.phase = Phase.extra;
            }
            break;
        case Phase.extra:
            if (--state.extraRemaining == 0) state.nextOptional();
            break;
        case Phase.name, Phase.comment:
            if (value == 0) state.nextOptional();
            break;
        case Phase.headerCrc:
            state.field |= cast(uint) value << (state.index++ * 8);
            if (state.index == 2)
            {
                if (state.field != (state.headerChecksum.value & 65535))
                    return state.counts.fail(ErrorCode.checksumMismatch, consumed, produced);
                state.nextOptional();
            }
            break;
        case Phase.trailerCrc:
            state.field |= cast(uint) value << (state.index++ * 8);
            if (state.index == 4)
            {
                if (state.field != state.checksum.value)
                    return state.counts.fail(ErrorCode.checksumMismatch, consumed, produced);
                state.phase = Phase.trailerSize;
                state.index = 0; state.field = 0;
            }
            break;
        case Phase.trailerSize:
            state.field |= cast(uint) value << (state.index++ * 8);
            if (state.index == 4)
            {
                if (state.field != state.memberSize)
                    return state.counts.fail(ErrorCode.checksumMismatch, consumed, produced);
                if (advanceInput(state.members, 1) != ErrorCode.none)
                    return state.counts.fail(ErrorCode.sizeOverflow, consumed, produced);
                state.phase = Phase.memberEnd;
            }
            break;
        case Phase.payload, Phase.memberEnd, Phase.finished: assert(0);
        }
    }
}

Result inflateGzip(scope const(ubyte)[] input, scope ubyte[] output,
    ref InflateWorkspace workspace, DecodeLimits limits = DecodeLimits.init,
    bool allMembers = false) @safe pure nothrow @nogc
{
    GzipState state;
    state.reset(limits, allMembers);
    return decodeGzip(state, workspace, input, output, true);
}

@safe pure nothrow @nogc unittest
{
    GzipState state;
    state.memberSize = uint.max - 1;
    immutable ubyte[3] output = [1,2,3];
    state.recordOutput(output);
    assert(state.memberSize == 1 && state.checksum.value == crc32(output));
    state.reset();
    state.phase = Phase.trailerSize;
    state.index = 3;
    state.members = ulong.max;
    InflateWorkspace workspace;
    immutable ubyte[1] zero = [0];
    assert(decodeGzip(state, workspace, zero, null, true).error.code == ErrorCode.sizeOverflow);
}

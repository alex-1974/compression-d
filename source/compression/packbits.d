/// Bounded decoder for the PackBits byte-oriented run-length format.
module compression.packbits;

import compression.core;

private enum Phase : ubyte { control, literal, repeat, finished }

struct PackBitsState
{
    private Phase phase;
    private ulong inputCount;
    private ulong outputCount;
    private DecodeLimits limits;
    private size_t remaining;
    private ubyte repeated;
    private bool haveRepeat;

    @safe pure nothrow @nogc:

    @property ulong totalInput() const { return inputCount; }
    @property ulong totalOutput() const { return outputCount; }

    void reset(DecodeLimits newLimits = DecodeLimits.init)
    {
        this = PackBitsState.init;
        limits = newLimits;
    }
}

/// Decode one PackBits stream. Bytes after the stream are left unconsumed.
Result decodePackBits(ref PackBitsState state, scope const(ubyte)[] input,
    scope ubyte[] output, bool endOfInput = false)
    @safe pure nothrow @nogc
{
    size_t consumed, produced;
    if (state.phase == Phase.finished)
        return Result.failure(ErrorCode.invalidArgument);

    while (true)
    {
        if (state.phase == Phase.control)
        {
            if (consumed == input.length)
            {
                if (endOfInput)
                {
                    state.phase = Phase.finished;
                    return Result.done(consumed, produced);
                }
                return Result.needInput(consumed, produced);
            }
            const ubyte control = input[consumed++];
            if (advanceInput(state.inputCount, 1) != ErrorCode.none)
                return Result.failure(ErrorCode.sizeOverflow, consumed - 1, produced,
                    state.inputCount);
            const byte signedControl = cast(byte) control;
            if (signedControl >= 0)
            {
                state.remaining = cast(size_t) signedControl + 1;
                state.phase = Phase.literal;
            }
            else if (signedControl != byte.min)
            {
                state.remaining = cast(size_t)(-signedControl) + 1;
                state.phase = Phase.repeat;
            }
            // -128 is a no-op, including at end of input.
            continue;
        }

        if (state.phase == Phase.literal)
        {
            while (state.remaining != 0)
            {
                if (consumed == input.length)
                {
                    if (endOfInput)
                        return Result.failure(ErrorCode.truncatedInput, consumed, produced,
                            state.inputCount);
                    return Result.needInput(consumed, produced);
                }
                if (produced == output.length)
                    return Result.needOutput(consumed, produced);
                const auto error = state.limits.checkGrowth(state.inputCount,
                    state.outputCount, 1);
                if (error != ErrorCode.none)
                    return Result.failure(error, consumed, produced, state.inputCount);
                output[produced++] = input[consumed++];
                ++state.outputCount;
                ++state.inputCount;
                --state.remaining;
            }
            state.phase = Phase.control;
            continue;
        }

        if (state.phase == Phase.repeat)
        {
            if (!state.haveRepeat && state.remaining != 0)
            {
                if (consumed == input.length)
                {
                    if (endOfInput)
                        return Result.failure(ErrorCode.truncatedInput, consumed, produced,
                            state.inputCount);
                    return Result.needInput(consumed, produced);
                }
                state.repeated = input[consumed++];
                ++state.inputCount;
                state.haveRepeat = true;
            }
            while (state.remaining != 0)
            {
                if (produced == output.length)
                    return Result.needOutput(consumed, produced);
                const auto error = state.limits.checkGrowth(state.inputCount,
                    state.outputCount, 1);
                if (error != ErrorCode.none)
                    return Result.failure(error, consumed, produced, state.inputCount);
                output[produced++] = state.repeated;
                ++state.outputCount;
                --state.remaining;
            }
            state.repeated = 0;
            state.haveRepeat = false;
            state.phase = Phase.control;
            continue;
        }

        assert(state.phase == Phase.finished);
        return Result.done(consumed, produced);
    }
}

/// One-shot convenience wrapper. It returns a valid output prefix on needOutput.
Result decodePackBits(scope const(ubyte)[] input, scope ubyte[] output,
    DecodeLimits limits = DecodeLimits.init)
    @safe pure nothrow @nogc
{
    PackBitsState state;
    state.reset(limits);
    auto result = decodePackBits(state, input, output, true);
    if (result.status == DecodeStatus.needInput)
        return Result.failure(ErrorCode.truncatedInput, result.consumed, result.produced,
            state.totalInput);
    return result;
}

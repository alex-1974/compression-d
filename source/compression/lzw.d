/// TIFF-compatible LZW decoder (MSB-first, 9..12 bit codes, early change).
module compression.lzw;

import compression.core;

enum size_t lzwDictionarySize = 4096;

struct LzwWorkspace
{
    uint[lzwDictionarySize] prefix;
    ubyte[lzwDictionarySize] suffix;
    ubyte[lzwDictionarySize] stack;
}

private enum Phase : ubyte { first, codes, emit, finished }

struct LzwState
{
    private Phase phase;
    private DecodeLimits limits;
    private ulong inputCount, outputCount;
    private ulong bitBuffer;
    private uint bitCount;
    private uint nextCode;
    private uint codeWidth;
    private uint previous;
    private ubyte firstByte;
    private bool havePrevious;
    private size_t stackLength, stackIndex;

    @safe pure nothrow @nogc:

    @property ulong totalInput() const { return inputCount; }
    @property ulong totalOutput() const { return outputCount; }

    void reset(DecodeLimits newLimits = DecodeLimits.init)
    {
        this = LzwState.init;
        limits = newLimits;
        phase = Phase.first;
        nextCode = 258;
        codeWidth = 9;
    }
}

private Result readCode(ref LzwState state, scope const(ubyte)[] input,
    ref size_t consumed, bool endOfInput)
    @safe pure nothrow @nogc
{
    while (state.bitCount < state.codeWidth)
    {
        if (consumed == input.length)
        {
            if (endOfInput)
                return Result.failure(ErrorCode.truncatedInput, consumed, 0,
                    state.inputCount);
            return Result.needInput(consumed, 0);
        }
        state.bitBuffer = (state.bitBuffer << 8) | input[consumed++];
        state.bitCount += 8;
        ++state.inputCount;
    }
    state.bitCount -= state.codeWidth;
    const ulong mask = (1UL << state.codeWidth) - 1;
    const uint code = cast(uint)((state.bitBuffer >> state.bitCount) & mask);
    if (state.bitCount == 0) state.bitBuffer = 0;
    else state.bitBuffer &= (1UL << state.bitCount) - 1;
    return Result.done(code, 0);
}

Result decodeLzw(ref LzwState state, ref LzwWorkspace workspace,
    scope const(ubyte)[] input, scope ubyte[] output, bool endOfInput = false)
    @safe pure nothrow @nogc
{
    size_t consumed, produced;
    if (state.phase == Phase.finished)
        return Result.failure(ErrorCode.invalidArgument);

    while (true)
    {
        if (state.phase == Phase.emit)
        {
            while (state.stackIndex != 0)
            {
                if (produced == output.length)
                    return Result.needOutput(consumed, produced);
                const error = state.limits.checkGrowth(state.inputCount,
                    state.outputCount, 1);
                if (error != ErrorCode.none)
                    return Result.failure(error, consumed, produced, state.inputCount);
                output[produced++] = workspace.stack[--state.stackIndex];
                ++state.outputCount;
            }
            state.phase = Phase.codes;
            continue;
        }
        auto read = readCode(state, input, consumed, endOfInput);
        if (read.status != DecodeStatus.done)
            return Result(read.status, consumed, produced, read.error);
        const uint code = cast(uint) read.consumed;
        if (code == 256)
        {
            state.nextCode = 258; state.codeWidth = 9; state.havePrevious = false;
            state.phase = Phase.first;
            continue;
        }
        if (code == 257)
        {
            state.phase = Phase.finished;
            return Result.done(consumed, produced);
        }
        if (code >= lzwDictionarySize || (state.phase == Phase.first && code > 255))
            return Result.failure(ErrorCode.invalidData, consumed, produced, state.inputCount);

        if (state.phase == Phase.first)
        {
            state.firstByte = cast(ubyte) code;
            workspace.stack[0] = state.firstByte;
            state.stackLength = 1; state.stackIndex = 1;
            state.previous = code; state.havePrevious = true;
            state.phase = Phase.emit;
            continue;
        }

        uint cursor = code;
        ubyte currentFirst;
        if (code == state.nextCode)
        {
            if (!state.havePrevious || state.stackLength >= lzwDictionarySize)
                return Result.failure(ErrorCode.invalidData, consumed, produced, state.inputCount);
            workspace.stack[0] = state.firstByte;
            state.stackLength = 1;
            cursor = state.previous;
            currentFirst = state.firstByte;
        }
        else if (code < state.nextCode)
        {
            currentFirst = code < 256 ? cast(ubyte) code : workspace.suffix[code];
            state.stackLength = 0;
        }
        else
            return Result.failure(ErrorCode.invalidData, consumed, produced, state.inputCount);

        while (cursor >= 256)
        {
            if (state.stackLength >= lzwDictionarySize || cursor >= state.nextCode)
                return Result.failure(ErrorCode.invalidData, consumed, produced, state.inputCount);
            workspace.stack[state.stackLength++] = workspace.suffix[cursor];
            cursor = workspace.prefix[cursor];
        }
        if (state.stackLength >= lzwDictionarySize)
            return Result.failure(ErrorCode.invalidData, consumed, produced, state.inputCount);
        workspace.stack[state.stackLength++] = cast(ubyte) cursor;
        state.firstByte = currentFirst;

        if (state.havePrevious && state.nextCode < lzwDictionarySize)
        {
            workspace.prefix[state.nextCode] = state.previous;
            workspace.suffix[state.nextCode] = currentFirst;
            ++state.nextCode;
            if (state.nextCode == ((1U << state.codeWidth) - 1) && state.codeWidth < 12)
                ++state.codeWidth;
        }
        state.previous = code;
        state.havePrevious = true;
            state.stackIndex = state.stackLength;
        state.phase = Phase.emit;
    }
}

Result decodeLzw(scope const(ubyte)[] input, scope ubyte[] output,
    ref LzwWorkspace workspace, DecodeLimits limits = DecodeLimits.init)
    @safe pure nothrow @nogc
{
    LzwState state;
    state.reset(limits);
    return decodeLzw(state, workspace, input, output, true);
}

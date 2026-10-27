/// Experimental RFC 1951 raw Inflate. No framing, allocation or C backend.
module compression.deflate;

import compression.bitstream;
import compression.core;
import compression.huffman;

private enum Phase : ubyte
{
    header, storedLength, storedComplement, storedBytes,
    dynamicCounts, codeLengths, alphabet, repeatLength,
    symbol, literal, lengthExtra, distance, distanceExtra, copy,
    finished, failed,
}

/// Caller-owned storage. State never retains a reference to this workspace.
struct InflateWorkspace
{
    private ubyte[32768] history;
    private HuffmanTable!9 literals;
    private HuffmanTable!9 distances;
    private HuffmanTable!0 codes;
    private ubyte[320] lengths;
    private ubyte[19] codeLengths;
}

/// Default initialization starts a new raw stream with disabled policy limits.
struct InflateState
{
    private Phase phase;
    private BitReader bits;
    private DecodeLimits limits;
    private ulong limitInputBase, limitOutputBase;
    private uint windowLimit = 32768;
    private DecodeError failure;
    private ulong inputCount;
    private ulong outputCount;
    private uint writePosition;
    private uint historySize;
    private bool finalBlock;
    private uint stored;
    private uint literalCount, distanceCount, codeCount, index;
    private uint pending, extra, matchLength, matchDistance;

    @safe pure nothrow @nogc:

    @property ulong totalInput() const { return inputCount; }
    @property ulong totalOutput() const { return outputCount; }

    /// Reset logical state and budgets; the workspace need not be cleared.
    void reset(DecodeLimits newLimits = DecodeLimits.init)
    {
        this = InflateState.init;
        limits = newLimits;
    }

    // Framing adapters account for consumed headers and previous GZIP members.
    package(compression) void resetFrame(DecodeLimits newLimits,
        ulong inputBase, ulong outputBase, uint windowSize = 32768)
    {
        reset(newLimits);
        limitInputBase = inputBase;
        limitOutputBase = outputBase;
        windowLimit = windowSize;
    }

    /// Seed the LZ history for a zlib preset dictionary. Only the last 32 KiB
    /// are addressable by RFC 1951 distances.
    package(compression) void seedDictionary(ref InflateWorkspace workspace,
        scope const(ubyte)[] dictionary)
        @safe pure nothrow @nogc
    {
        const start = dictionary.length > 32768 ? dictionary.length - 32768 : 0;
        const bytes = dictionary[start .. $];
        workspace.history[0 .. bytes.length] = bytes;
        writePosition = cast(uint) bytes.length & 32767;
        historySize = cast(uint) bytes.length;
    }

    private ErrorCode growth(ulong amount) const
    {
        ulong input = inputCount, output = outputCount;
        if (advanceInput(input, limitInputBase) != ErrorCode.none ||
            advanceInput(output, limitOutputBase) != ErrorCode.none)
            return ErrorCode.sizeOverflow;
        return limits.checkGrowth(input, output, amount);
    }

    private BitResult read(scope const(ubyte)[] input, ref size_t cursor,
        uint width, bool finalInput)
    {
        const before = cursor;
        auto result = bits.read(input, cursor, width, finalInput);
        if (advanceInput(inputCount, cursor - before) != ErrorCode.none)
            return BitResult(DecodeStatus.error, 0, ErrorCode.sizeOverflow);
        return result;
    }

    private SymbolResult symbol(uint root)(ref const HuffmanTable!root table,
        scope const(ubyte)[] input, ref size_t cursor, bool finalInput)
    {
        const before = cursor;
        auto result = table.decode(bits, input, cursor, finalInput);
        if (advanceInput(inputCount, cursor - before) != ErrorCode.none)
            return SymbolResult(DecodeStatus.error, 0, ErrorCode.sizeOverflow);
        return result;
    }
}

private immutable ubyte[19] codeOrder = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
private immutable ushort[29] lengthBase =
    [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
private immutable ubyte[29] lengthExtra =
    [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
private immutable ushort[30] distanceBase =
    [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
private immutable ubyte[30] distanceExtra =
    [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];

private Result stop(ref InflateState state, DecodeStatus status, ErrorCode code,
    size_t consumed, size_t produced, size_t unread = 0) @safe pure nothrow @nogc
{
    if (status == DecodeStatus.needInput)
        return Result.needInput(consumed, produced);
    // Malformed data points at the last consumed byte; truncation at EOF.
    ulong offset = state.inputCount == 0 ? 0 : state.inputCount - 1;
    if (code == ErrorCode.truncatedInput)
    {
        offset = state.inputCount;
        if (advanceInput(offset, unread) != ErrorCode.none)
            code = ErrorCode.sizeOverflow;
    }
    state.phase = Phase.failed;
    state.failure = DecodeError(code, offset);
    return Result.failure(code, consumed, produced, offset);
}

private void emit(ref InflateState state, ref InflateWorkspace workspace,
    scope ubyte[] output, ref size_t produced, ubyte value) @safe pure nothrow @nogc
{
    output[produced++] = value;
    workspace.history[state.writePosition] = value;
    state.writePosition = (state.writePosition + 1) & 32767;
    if (state.historySize < 32768)
        ++state.historySize;
    ++state.outputCount; // The entire token was checked before its first byte.
}

/** Resume one raw stream. Input/output must not alias each other, state or
    workspace. Keep the same state/workspace pair until done/error. On needInput
    preserve the unread suffix and append input; no slices are retained.
    Output is valid only through Result.produced. See docs/INFLATE.md. */
Result inflate(ref InflateState state, ref InflateWorkspace workspace,
    scope const(ubyte)[] input, scope ubyte[] output, bool endOfInput = false)
    @safe pure nothrow @nogc
{
    size_t consumed, produced;
    if (state.phase == Phase.failed)
        return Result.failure(state.failure.code, 0, 0, state.failure.inputOffset);
    if (state.phase == Phase.finished)
        return Result.failure(ErrorCode.invalidArgument);
    while (true)
    {
        final switch (state.phase)
        {
        case Phase.header:
            const header = state.read(input, consumed, 3, endOfInput);
            if (header.status != DecodeStatus.done)
                return stop(state, header.status, header.error, consumed, produced, input.length - consumed);
            state.finalBlock = (header.value & 1) != 0;
            switch (header.value >> 1)
            {
            case 0:
                state.bits.alignToByte();
                state.phase = Phase.storedLength;
                break;
            case 1:
                foreach (uint i; 0 .. 288)
                    workspace.lengths[i] = cast(ubyte)(i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8);
                workspace.literals.build(workspace.lengths[0 .. 288], TreeKind.literalLength);
                workspace.lengths[0 .. 32] = 5;
                workspace.distances.build(workspace.lengths[0 .. 32], TreeKind.distance);
                state.phase = Phase.symbol;
                break;
            case 2:
                state.phase = Phase.dynamicCounts;
                break;
            default:
                return stop(state, DecodeStatus.error, ErrorCode.invalidHeader, consumed, produced);
            }
            break;
        case Phase.storedLength:
            const value = state.read(input, consumed, 16, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            state.stored = value.value;
            state.phase = Phase.storedComplement;
            break;
        case Phase.storedComplement:
            const value = state.read(input, consumed, 16, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            if ((state.stored ^ value.value) != 65535)
                return stop(state, DecodeStatus.error, ErrorCode.invalidData, consumed, produced);
            state.phase = Phase.storedBytes;
            break;
        case Phase.storedBytes:
            if (state.stored == 0)
            {
                state.phase = state.finalBlock ? Phase.finished : Phase.header;
                break;
            }
            // Parse and reserve one byte even with no output, so policy errors
            // and final truncation are distinguished from output starvation.
            const value = state.read(input, consumed, 8, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            state.pending = value.value;
            --state.stored;
            state.index = 1; // Return to storedBytes after emitting this literal.
            state.phase = Phase.literal;
            const error = state.growth(1);
            if (error != ErrorCode.none)
                return stop(state, DecodeStatus.error, error, consumed, produced);
            break;
        case Phase.dynamicCounts:
            const value = state.read(input, consumed, 14, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            state.literalCount = (value.value & 31) + 257;
            state.distanceCount = ((value.value >> 5) & 31) + 1;
            state.codeCount = (value.value >> 10) + 4;
            if (state.literalCount > 286 || state.distanceCount > 30)
                return stop(state, DecodeStatus.error, ErrorCode.invalidHeader, consumed, produced);
            workspace.codeLengths[] = 0;
            state.index = 0;
            state.phase = Phase.codeLengths;
            break;
        case Phase.codeLengths:
            if (state.index == state.codeCount)
            {
                const error = workspace.codes.build(workspace.codeLengths, TreeKind.codeLength);
                if (error != ErrorCode.none)
                    return stop(state, DecodeStatus.error, error, consumed, produced);
                state.index = 0;
                state.phase = Phase.alphabet;
                break;
            }
            const value = state.read(input, consumed, 3, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            workspace.codeLengths[codeOrder[state.index++]] = cast(ubyte) value.value;
            break;
        case Phase.alphabet:
            if (state.index == state.literalCount + state.distanceCount)
            {
                auto error = workspace.literals.build(workspace.lengths[0 .. state.literalCount], TreeKind.literalLength);
                if (error == ErrorCode.none)
                    error = workspace.distances.build(workspace.lengths[state.literalCount .. state.index], TreeKind.distance);
                if (error != ErrorCode.none)
                    return stop(state, DecodeStatus.error, error, consumed, produced);
                state.phase = Phase.symbol;
                break;
            }
            const value = state.symbol(workspace.codes, input, consumed, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            if (value.symbol < 16)
                workspace.lengths[state.index++] = cast(ubyte) value.symbol;
            else
            {
                if (value.symbol == 16 && state.index == 0)
                    return stop(state, DecodeStatus.error, ErrorCode.invalidHuffmanTree, consumed, produced);
                state.pending = value.symbol;
                state.phase = Phase.repeatLength;
            }
            break;
        case Phase.repeatLength:
            const width = state.pending == 16 ? 2 : state.pending == 17 ? 3 : 7;
            const value = state.read(input, consumed, width, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            const count = value.value + (state.pending == 18 ? 11 : 3);
            if (count > state.literalCount + state.distanceCount - state.index)
                return stop(state, DecodeStatus.error, ErrorCode.invalidHuffmanTree, consumed, produced);
            const length = state.pending == 16 ? workspace.lengths[state.index - 1] : 0;
            workspace.lengths[state.index .. state.index + count] = cast(ubyte) length;
            state.index += count;
            state.phase = Phase.alphabet;
            break;
        case Phase.symbol:
            const value = state.symbol(workspace.literals, input, consumed, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            if (value.symbol < 256)
            {
                state.pending = value.symbol;
                state.index = 0;
                state.phase = Phase.literal;
                const error = state.growth(1);
                if (error != ErrorCode.none)
                    return stop(state, DecodeStatus.error, error, consumed, produced);
            }
            else if (value.symbol == 256)
                state.phase = state.finalBlock ? Phase.finished : Phase.header;
            else if (value.symbol <= 285)
            {
                state.matchLength = lengthBase[value.symbol - 257];
                state.extra = lengthExtra[value.symbol - 257];
                state.phase = Phase.lengthExtra;
            }
            else
                return stop(state, DecodeStatus.error, ErrorCode.invalidData, consumed, produced);
            break;
        case Phase.literal:
            if (produced == output.length)
                return Result.needOutput(consumed, produced);
            emit(state, workspace, output, produced, cast(ubyte) state.pending);
            state.phase = state.index == 1 ? Phase.storedBytes : Phase.symbol;
            break;
        case Phase.lengthExtra:
            const value = state.read(input, consumed, state.extra, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            state.matchLength += value.value;
            state.phase = Phase.distance;
            break;
        case Phase.distance:
            const value = state.symbol(workspace.distances, input, consumed, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            if (value.symbol >= 30)
                return stop(state, DecodeStatus.error, ErrorCode.invalidDistance, consumed, produced);
            state.matchDistance = distanceBase[value.symbol];
            state.extra = distanceExtra[value.symbol];
            state.phase = Phase.distanceExtra;
            break;
        case Phase.distanceExtra:
            const value = state.read(input, consumed, state.extra, endOfInput);
            if (value.status != DecodeStatus.done)
                return stop(state, value.status, value.error, consumed, produced, input.length - consumed);
            state.matchDistance += value.value;
            if (state.matchDistance > state.historySize || state.matchDistance > state.windowLimit)
                return stop(state, DecodeStatus.error, ErrorCode.invalidDistance, consumed, produced);
            const error = state.growth(state.matchLength);
            if (error != ErrorCode.none)
                return stop(state, DecodeStatus.error, error, consumed, produced);
            state.phase = Phase.copy;
            break;
        case Phase.copy:
            while (state.matchLength != 0 && produced < output.length)
            {
                const source = (state.writePosition + 32768 - state.matchDistance) & 32767;
                emit(state, workspace, output, produced, workspace.history[source]);
                --state.matchLength;
            }
            if (state.matchLength != 0)
                return Result.needOutput(consumed, produced);
            state.phase = Phase.symbol;
            break;
        case Phase.finished:
            state.bits.alignToByte();
            return Result.done(consumed, produced);
        case Phase.failed:
            assert(0); // Errors return immediately via stop().
        }
    }
}

/// Convenience one-shot call. needOutput reports a prefix; resuming requires
/// the stateful API instead. The caller still owns the large workspace.
Result inflateRaw(scope const(ubyte)[] input, scope ubyte[] output,
    ref InflateWorkspace workspace, DecodeLimits limits = DecodeLimits.init)
    @safe pure nothrow @nogc
{
    InflateState state;
    state.reset(limits);
    return inflate(state, workspace, input, output, true);
}

@safe pure nothrow @nogc unittest
{
    // Inject near-overflow counters without constructing impractically large streams.
    immutable ubyte[7] encoded = [0xCB,0x48,0xCD,0xC9,0xC9,0x07,0];
    InflateWorkspace workspace;
    InflateState state;
    ubyte[5] output;
    output[] = 0xA5;
    state.inputCount = ulong.max;
    auto result = inflate(state, workspace, encoded, output, true);
    assert(result.error.code == ErrorCode.sizeOverflow && result.produced == 0);
    assert(state.totalInput == ulong.max);
    state.reset();
    state.outputCount = ulong.max;
    result = inflate(state, workspace, encoded, output, true);
    assert(result.error.code == ErrorCode.sizeOverflow && result.produced == 0);
    foreach (value; output) assert(value == 0xA5);
    state.reset();
    assert(state.totalInput == 0 && state.totalOutput == 0);
    result = inflate(state, workspace, encoded, output, true);
    assert(result.status == DecodeStatus.done && output == "hello");
}

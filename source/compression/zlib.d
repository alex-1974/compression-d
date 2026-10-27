/// RFC 1950 streaming zlib framing around the Pure-D raw Inflate engine.
module compression.zlib;
import compression.core;
import compression.checksum;
import compression.deflate;
import compression.framing;

private enum Phase : ubyte { header, dictionary, payload, trailer, finished }

struct ZlibState
{
    private Phase phase;
    private FrameCounters counts;
    private InflateState raw;
    private DecodeLimits limits;
    private Adler32 checksum;
    private uint field, index, cmf, dictId;
    private ulong payloadStart;

    @safe pure nothrow @nogc:
    @property ulong totalInput() const { return counts.input; }
    @property ulong totalOutput() const { return counts.output; }
    /// Available with dictionaryRequired; dictionaries are not silently ignored.
    @property uint dictionaryId() const { return dictId; }
    void reset(DecodeLimits newLimits = DecodeLimits.init)
    {
        this = ZlibState.init;
        limits = newLimits;
    }
    private void startPayload()
    {
        payloadStart = counts.input;
        raw.resetFrame(limits, counts.input, counts.output, 1U << ((cmf >> 4) + 8));
        phase = Phase.payload;
    }
}

Result decodeZlib(ref ZlibState state, ref InflateWorkspace workspace,
    scope const(ubyte)[] input, scope ubyte[] output, bool endOfInput = false,
    scope const(ubyte)[] dictionary = null)
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
            state.checksum.update(output[produced .. produced + result.produced]);
            consumed += result.consumed; produced += result.produced;
            const error = state.counts.account(result);
            if (error != ErrorCode.none) return state.counts.fail(error, consumed, produced);
            if (result.status == DecodeStatus.error)
                return state.counts.fail(result.error.code, consumed, produced,
                    state.counts.translated(state.payloadStart, result.error.inputOffset));
            if (result.status == DecodeStatus.needInput) return Result.needInput(consumed, produced);
            if (result.status == DecodeStatus.needOutput) return Result.needOutput(consumed, produced);
            state.phase = Phase.trailer;
            state.index = 0; state.field = 0;
        }
        if (consumed == input.length)
            return state.counts.shortage(consumed, produced, endOfInput);
        ubyte value;
        const error = state.counts.take(input, consumed, value);
        if (error != ErrorCode.none) return state.counts.fail(error, consumed, produced);
        final switch (state.phase)
        {
        case Phase.header:
            if (state.index++ == 0)
            {
                state.cmf = value;
                if ((value & 15) != 8 || (value >> 4) > 7)
                    return state.counts.fail(ErrorCode.invalidHeader, consumed, produced);
            }
            else
            {
                if (((state.cmf << 8) | value) % 31 != 0)
                    return state.counts.fail(ErrorCode.invalidHeader, consumed, produced);
                if ((value & 32) != 0)
                {
                    state.phase = Phase.dictionary;
                    state.index = 0; state.field = 0;
                }
                else state.startPayload();
            }
            break;
        case Phase.dictionary:
            state.field = (state.field << 8) | value;
            if (++state.index == 4)
            {
                state.dictId = state.field;
                if (dictionary.length == 0 || adler32(dictionary) != state.dictId)
                    return state.counts.fail(ErrorCode.dictionaryRequired, consumed, produced);
                startPayloadWithDictionary(state, workspace, dictionary);
            }
            break;
        case Phase.trailer:
            state.field = (state.field << 8) | value;
            if (++state.index == 4)
            {
                if (state.field != state.checksum.value)
                    return state.counts.fail(ErrorCode.checksumMismatch, consumed, produced);
                state.phase = Phase.finished;
                return Result.done(consumed, produced);
            }
            break;
        case Phase.payload, Phase.finished: assert(0);
        }
    }
}

private void startPayloadWithDictionary(ref ZlibState state,
    ref InflateWorkspace workspace, scope const(ubyte)[] dictionary)
    @safe pure nothrow @nogc
{
    state.payloadStart = state.counts.input;
    state.raw.resetFrame(state.limits, state.counts.input, state.counts.output,
        1U << ((state.cmf >> 4) + 8));
    state.raw.seedDictionary(workspace, dictionary);
    state.phase = Phase.payload;
}

Result inflateZlib(scope const(ubyte)[] input, scope ubyte[] output,
    ref InflateWorkspace workspace, DecodeLimits limits = DecodeLimits.init,
    scope const(ubyte)[] dictionary = null)
    @safe pure nothrow @nogc
{
    ZlibState state;
    state.reset(limits);
    return decodeZlib(state, workspace, input, output, true, dictionary);
}

@safe pure nothrow @nogc unittest
{
    // Generated independently with RFC 1950 preset dictionary "hello ".
    immutable ubyte[19] encoded = [120,187,8,97,2,53,203,0,147,229,249,69,57,41,0,26,11,4,93];
    immutable ubyte[6] dictionary = ['h','e','l','l','o',' '];
    ubyte[11] output;
    InflateWorkspace workspace;
    auto result = inflateZlib(encoded, output, workspace, DecodeLimits.init, dictionary);
    assert(result.status == DecodeStatus.done && output[] == "hello world");
    workspace = InflateWorkspace.init;
    output[] = 0;
    result = inflateZlib(encoded, output, workspace);
    assert(result.status == DecodeStatus.error && result.error.code == ErrorCode.dictionaryRequired);
}

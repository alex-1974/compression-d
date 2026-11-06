module lzw_tests;

import compression.core;
import compression.lzw;

private ubyte[] pack9(scope const(uint)[] codes) @safe
{
    ubyte[] result;
    ulong bits; uint count;
    foreach (code; codes)
    {
        bits = (bits << 9) | code; count += 9;
        while (count >= 8)
        {
            count -= 8; result ~= cast(ubyte)(bits >> count);
            bits &= count == 0 ? 0 : (1UL << count) - 1;
        }
    }
    if (count != 0) result ~= cast(ubyte)(bits << (8 - count));
    return result;
}

@safe unittest
{
    // CLEAR, A, B, A, B, EOI -> ABAB.
    auto encoded = pack9([256, 65, 66, 258, 257]);
    LzwWorkspace workspace;
    ubyte[] output = new ubyte[4];
    auto result = decodeLzw(encoded, output, workspace);
    assert(result.status == DecodeStatus.done && result.produced == 4);
    assert(output == ['A', 'B', 'A', 'B']);
}

@safe unittest
{
    auto encoded = pack9([256, 65, 66, 258, 257]);
    LzwWorkspace workspace; LzwState state; state.reset();
    ubyte[] output = new ubyte[4];
    auto result = decodeLzw(state, workspace, encoded[0 .. 2], output, false);
    assert(result.status == DecodeStatus.needInput || result.status == DecodeStatus.needOutput);
    result = decodeLzw(state, workspace, encoded[result.consumed .. $], output[result.produced .. $], true);
    assert(result.status == DecodeStatus.done && output == ['A', 'B', 'A', 'B']);
}

@safe unittest
{
    LzwWorkspace workspace;
    auto result = decodeLzw(pack9([256, 65, 257]), new ubyte[1], workspace, DecodeLimits(0));
    assert(result.error.code == ErrorCode.outputLimitExceeded);
    result = decodeLzw([cast(ubyte)0], new ubyte[4], workspace);
    assert(result.error.code == ErrorCode.truncatedInput);
}

// Compiled as a separate consumer with -dip1000 by both supported compilers.
module core_probe;

import compression.core;

// Explicit attributes ensure a regression in any called operation fails to compile.
Result probe() @safe pure nothrow @nogc
{
    ulong input;
    auto code = advanceInput(input, 2);
    if (code != ErrorCode.none)
        return Result.failure(code);
    auto limits = DecodeLimits(64, 4);
    code = limits.checkGrowth(input, 0, 8);
    if (code != ErrorCode.none)
        return Result.failure(code, 2);
    auto paused = Result.needInput(2, 8);
    auto blocked = Result.needOutput(paused.consumed, paused.produced);
    return Result.done(blocked.consumed, blocked.produced);
}

void main() @safe nothrow @nogc
{
    const result = probe();
    assert(result.status == DecodeStatus.done);
    assert(result.consumed == 2 && result.produced == 8);
}

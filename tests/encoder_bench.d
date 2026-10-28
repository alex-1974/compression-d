module encoder_bench;

import compression.core : DecodeStatus;
import compression.encode;
import std.datetime.stopwatch : StopWatch;
import std.stdio;

void main()
{
    ubyte[] input = new ubyte[155648];
    foreach (i; 0 .. input.length)
        input[i] = (i % 37 < 32) ? cast(ubyte)('A' + (i % 11)) : cast(ubyte)(i * 13);
    ubyte[] output = new ubyte[input.length * 2 + 128];
    enum rounds = 40;
    size_t produced;
    size_t hashedProduced;
    HashChainMatchFinder finder;
    StopWatch timer;
    timer.start();
    foreach (_; 0 .. rounds)
    {
        auto result = encodeRawFixedLz(input, output);
        assert(result.status == DecodeStatus.done);
        produced = result.produced;
    }
    auto linearSeconds = timer.peek.total!"hnsecs" / 1_000_000_000.0;
    timer.reset();
    timer.start();
    foreach (_; 0 .. rounds)
    {
        finder.reset();
        auto result = encodeRawFixedLzHashChain(finder, input, output);
        assert(result.status == DecodeStatus.done);
        hashedProduced = result.produced;
    }
    auto seconds = timer.peek.total!"hnsecs" / 1_000_000_000.0;
    writeln("compression-d linear: bytes=", input.length, " compressed=", produced,
        " rounds=", rounds, " MB/s=", input.length * rounds / linearSeconds / 1_000_000.0);
    writeln("compression-d hash-chain: bytes=", input.length, " compressed=", hashedProduced,
        " rounds=", rounds, " MB/s=", input.length * rounds / seconds / 1_000_000.0);
}

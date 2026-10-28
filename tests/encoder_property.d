module encoder_property;

import compression.core;
import compression.deflate;
import compression.encode;
import std.stdio;

ubyte next(ref uint state) @safe pure nothrow
{
    state = state * 1664525U + 1013904223U;
    return cast(ubyte)(state >> 24);
}

void main()
{
    uint seed = 0xC0DEC0DE;
    size_t total;
    foreach (caseNo; 0 .. 256)
    {
        const length = (caseNo * 97) % 4097;
        ubyte[] input = new ubyte[length];
        foreach (i; 0 .. length)
        {
            auto random = next(seed);
            input[i] = (caseNo % 3 == 0) ? cast(ubyte)('A' + (i % 7)) :
                (caseNo % 3 == 1 ? cast(ubyte)(random & 0x1f) : random);
        }
        ubyte[] encoded = new ubyte[length * 2 + 128];
        auto encodedResult = encodeRawFixedLz(input, encoded[]);
        assert(encodedResult.status == DecodeStatus.done, "encoder returned needOutput");
        encoded = encoded[0 .. encodedResult.produced];
        ubyte[] decoded = new ubyte[length];
        InflateWorkspace workspace;
        auto decodedResult = inflateRaw(encoded, decoded, workspace);
        assert(decodedResult.status == DecodeStatus.done, "decoder rejected encoder output");
        assert(decoded == input, "roundtrip mismatch");
        HashChainMatchFinder finder;
        ubyte[] hashed = new ubyte[length * 2 + 128];
        auto hashedResult = encodeRawFixedLzHashChain(finder, input, hashed[]);
        assert(hashedResult.status == DecodeStatus.done, "hash-chain encoder returned needOutput");
        ubyte[] hashDecoded = new ubyte[length];
        workspace = InflateWorkspace.init;
        auto hashDecodedResult = inflateRaw(hashed[0 .. hashedResult.produced], hashDecoded, workspace);
        assert(hashDecodedResult.status == DecodeStatus.done, "decoder rejected hash-chain output");
        assert(hashDecoded == input, "hash-chain roundtrip mismatch");
        total += length;
    }
    writeln("encoder property cases=256 bytes=", total, " seed=0xC0DEC0DE");
}

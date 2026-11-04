module packbits_tests;

import compression.core;
import compression.packbits;

@safe unittest
{
    ubyte[] encoded = [2, 'A', 'B', 'C', cast(ubyte)0xff, 'X', cast(ubyte)0x80,
        0, 'Z'];
    ubyte[] output = new ubyte[6];
    auto result = decodePackBits(encoded, output);
    assert(result.status == DecodeStatus.done);
    assert(result.consumed == encoded.length && result.produced == 6);
    assert(output == [cast(ubyte)'A', 'B', 'C', 'X', 'X', 'Z']);
}

@safe unittest
{
    ubyte[] encoded = [cast(ubyte)0, cast(ubyte)'A', cast(ubyte)0xff, cast(ubyte)'B'];
    PackBitsState state;
    ubyte[] output = new ubyte[3];
    auto result = decodePackBits(state, encoded[0 .. 1], output, false);
    assert(result.status == DecodeStatus.needInput && result.consumed == 1);
    result = decodePackBits(state, encoded[1 .. $], output, true);
    assert(result.status == DecodeStatus.done && output == ['A', 'B', 'B']);
}

@safe unittest
{
    ubyte[] encoded = [cast(ubyte)0xff, cast(ubyte)'A'];
    auto result = decodePackBits(encoded, new ubyte[2], DecodeLimits(1));
    assert(result.error.code == ErrorCode.outputLimitExceeded);
    assert(decodePackBits([cast(ubyte)1, cast(ubyte)'A'], new ubyte[2]).error.code == ErrorCode.truncatedInput);
}

module inflate_probe;
import compression.core;
import compression.deflate;

void probe() @safe pure nothrow @nogc
{
    immutable ubyte[7] encoded = [0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0];
    InflateWorkspace workspace;
    InflateState state;
    state.reset(DecodeLimits(5, 10));
    ubyte[5] output;
    auto result = inflate(state, workspace, encoded, output, true);
    assert(result.status == DecodeStatus.done && output == "hello");
    assert(state.totalInput == 7 && state.totalOutput == 5);
    result = inflateRaw(encoded, output, workspace);
    assert(result.status == DecodeStatus.done);
}

void main() @safe nothrow @nogc { probe(); }

module encoder_dip1000_probe;

import compression.core : DecodeStatus;
import compression.encode;

void probe() @safe nothrow @nogc
{
    ubyte[256] input;
    foreach (i; 0 .. input.length) input[i] = cast(ubyte) (i % 11);
    ubyte[1024] output;
    auto raw = encodeRawFixedLz(input[], output[]);
    assert(raw.status == DecodeStatus.done);
    HashChainMatchFinder finder;
    auto hashed = encodeRawFixedLzHashChain(finder, input[], output[]);
    assert(hashed.status == DecodeStatus.done);
    ubyte[2048] zlibOutput, gzipOutput;
    auto zlib = encodeZlibStored(input[], zlibOutput[]);
    auto gzip = encodeGzipStored(input[], gzipOutput[]);
    assert(zlib.status == DecodeStatus.done && gzip.status == DecodeStatus.done);
    ZlibStoredEncoderState zstate;
    auto zchunk = encodeZlibStoredChunk(zstate, input[0 .. 128], zlibOutput[], false);
    auto zfinal = encodeZlibStoredChunk(zstate, input[128 .. $], zlibOutput[], true);
    assert(zchunk.status == DecodeStatus.done && zfinal.status == DecodeStatus.done);
    GzipStoredEncoderState gstate;
    auto gchunk = encodeGzipStoredChunk(gstate, input[0 .. 128], gzipOutput[], false);
    auto gfinal = encodeGzipStoredChunk(gstate, input[128 .. $], gzipOutput[], true);
    assert(gchunk.status == DecodeStatus.done && gfinal.status == DecodeStatus.done);
}

void main() @safe nothrow @nogc { probe(); }

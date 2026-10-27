module framing_probe;
import compression.core;
import compression.checksum;
import compression.deflate;
import compression.zlib;
import compression.gzip;

void probe() @safe pure nothrow @nogc
{
    immutable ubyte[8] z = [0x78,0x9C,3,0,0,0,0,1];
    immutable ubyte[20] g = [31,139,8,0,0,0,0,0,0,255,3,0,0,0,0,0,0,0,0,0];
    InflateWorkspace workspace;
    ZlibState zs;
    GzipState gs;
    zs.reset(DecodeLimits(0)); gs.reset(DecodeLimits(0), true);
    assert(decodeZlib(zs, workspace, z, null, true).status == DecodeStatus.done);
    assert(decodeGzip(gs, workspace, g, null, true).status == DecodeStatus.done);
    assert(zs.totalInput == 8 && zs.totalOutput == 0 && zs.dictionaryId == 0);
    assert(gs.totalInput == 20 && gs.totalOutput == 0 && gs.memberCount == 1);
    assert(inflateZlib(z, null, workspace).status == DecodeStatus.done);
    assert(inflateGzip(g, null, workspace).status == DecodeStatus.done);
    Adler32 a; Crc32 c;
    a.update(z); c.update(g); a.reset(); c.reset();
    assert(a.value == adler32(null) && c.value == crc32(null));
}

void main() @safe nothrow @nogc { probe(); }

module png_main;
import png_scanlines;
import compression.deflate : InflateWorkspace;
import compression.checksum : crc32;
import core.memory : GC;
import core.time : MonoTime;
import std.conv : to;
import std.file : read;
import std.stdio : writefln;

pragma(inline, false)
private PngResult decodeOnce(scope const(ubyte)[] encoded, PngShape shape,
    ref InflateWorkspace decoder, scope ubyte[] scratch, scope ubyte[] output)
    @safe pure nothrow @nogc
{ return decodeScanlines(encoded, shape, decoder, scratch, output); }

void main(string[] args)
{
    assert(args.length >= 7);
    auto encoded = cast(const(ubyte)[])read(args[1]);
    auto expected = cast(const(ubyte)[])read(args[2]);
    const shape = PngShape(to!uint(args[3]), to!uint(args[4]), to!uint(args[5]), to!uint(args[6]));
    const req = requirements(shape);
    assert(req.status == PngStatus.ok && req.pixelBytes == expected.length);
    auto output = new ubyte[req.pixelBytes];
    auto scratch = new ubyte[req.filteredBytes];
    InflateWorkspace decoder;
    const warmup = decodeOnce(encoded, shape, decoder, scratch, output);
    assert(warmup.status == PngStatus.ok);
    assert(output == expected);
    const iterations = args.length > 7 ? to!uint(args[7]) : 1;
    const fresh = args.length > 8 && args[8] == "fresh";
    const before = GC.allocatedInCurrentThread;
    const start = MonoTime.currTime;
    ulong checksum;
    foreach (iteration; 0 .. iterations)
    {
        if (fresh) decoder = InflateWorkspace.init;
        const result = decodeOnce(encoded, shape, decoder, scratch, output);
        assert(result.status == PngStatus.ok);
        checksum += crc32(output) + iteration;
    }
    const seconds = (MonoTime.currTime - start).total!"nsecs" / 1e9;
    const allocated = GC.allocatedInCurrentThread - before;
    assert(output == expected && allocated == 0 && iterations > 0);
    writefln("PNG mode=%s bytes=%s scratch=%s decoder=%s iterations=%s MBps=%.3f gcBytes=%s checksum=%s",
        fresh ? "fresh" : "reuse", output.length, scratch.length, decoder.sizeof,
        iterations, output.length * cast(double)iterations / seconds / 1e6, allocated, checksum);
}

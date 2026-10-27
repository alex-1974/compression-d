module consumer_tests;
import deflate_bridge;
import png_scanlines;
import compression.core : ErrorCode;
import compression.deflate : InflateWorkspace;
import compression.checksum : adler32;
import core.thread : Thread;
import core.sync.barrier : Barrier;
import core.memory : GC;
import tiff_metadata;
import std.file : read;
import std.path : buildPath;
import std.stdio : writeln;

private immutable ubyte[13] hello = [0x78,0x9C,0xCB,0x48,0xCD,0xC9,0xC9,0x07,0,0x06,0x2C,0x02,0x15];
private immutable ubyte[15] pngPixel = [0x78,1,1,4,0,0xFB,0xFF,0,1,2,3,0,14,0,7];

@safe pure nothrow @nogc unittest
{
    const spec = ImageSpec(5,1,1,1,5,1);
    const layout = Layout(5,1,1);
    Block[1] blocks = [Block(0,13)];
    InflateWorkspace decoder;
    ubyte[5] scratch, output;
    assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch, output, layout).ok);
    assert(output == "hello");
    output[] = 0xA5;
    assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch[0 .. 4], output, layout).status == BridgeStatus.workspaceTooSmall);
    assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch, output[0 .. 4], layout).status == BridgeStatus.destinationTooSmall);
    foreach (value; output) assert(value == 0xA5);
    ubyte[13] bad = hello;
    bad[$-1] ^= 1;
    const failed = decodeDeflateBlocks(bad, blocks, spec, decoder, scratch, output, layout);
    assert(failed.status == BridgeStatus.codecError && failed.codec == ErrorCode.checksumMismatch);
    foreach (value; output) assert(value == 0xA5);
    blocks[0].byteCount = 12;
    assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch, output, layout).codec == ErrorCode.truncatedInput);
    blocks[0] = Block(12,13);
    assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch, output, layout).status == BridgeStatus.truncated);
    assert(requirements(ImageSpec(uint.max,uint.max,uint.max,2,uint.max,uint.max,true)).status == BridgeStatus.sizeOverflow);
    ImageSpec unsupported = spec; unsupported.predictor = 3;
    assert(requirements(unsupported).status == BridgeStatus.unsupported);
    blocks[0] = Block(0,13);
    assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch, output, Layout(5,0,1)).status == BridgeStatus.invalidMetadata);
    assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch, output, Layout(size_t.max,2,1)).status == BridgeStatus.destinationTooSmall);
    ubyte[14] trailing;
    trailing[0 .. 13] = hello[];
    blocks[0].byteCount = 14;
    assert(decodeDeflateBlocks(trailing, blocks, spec, decoder, scratch, output, layout).status == BridgeStatus.decodedSizeMismatch);
    blocks[0].byteCount = 13;
    ubyte[6] largerScratch, largerOutput;
    assert(decodeDeflateBlocks(hello, blocks, ImageSpec(6,1,1,1,6,1), decoder,
        largerScratch, largerOutput, Layout(6,1,1)).status == BridgeStatus.decodedSizeMismatch);
    assert(decodeDeflateBlocks(hello, blocks, ImageSpec(4,1,1,1,4,1), decoder,
        scratch, output, Layout(4,1,1)).codec == ErrorCode.outputLimitExceeded);
}

@safe pure nothrow @nogc unittest
{
    // The failing block never commits pixels; earlier blocks remain visible.
    ubyte[26] file;
    file[0 .. 13] = hello[]; file[13 .. $] = hello[]; file[$-1] ^= 1;
    Block[2] blocks = [Block(0,13), Block(13,13)];
    const spec = ImageSpec(5,2,1,1,5,1);
    InflateWorkspace decoder;
    ubyte[5] scratch;
    ubyte[10] output;
    output[] = 0xA5;
    const result = decodeDeflateBlocks(file, blocks, spec, decoder, scratch, output, Layout(5,1,1));
    assert(result.status == BridgeStatus.codecError && result.blocksWritten == 1);
    assert(output[0 .. 5] == "hello");
    foreach (value; output[5 .. $]) assert(value == 0xA5);
    blocks[1] = blocks[0];
    output[] = 0xA5;
    assert(decodeDeflateBlocks(file, blocks, spec, decoder, scratch, output, Layout(5,1,1)).status == BridgeStatus.invalidMetadata);
    foreach (value; output) assert(value == 0xA5);
    file[$-1] ^= 1;
    blocks[0] = Block(13,13); blocks[1] = Block(0,13);
    assert(decodeDeflateBlocks(file, blocks, spec, decoder, scratch, output, Layout(5,1,1)).ok);
    assert(output == "hellohello");
    // Decoder reuse with a separate output layout (gaps must stay untouched).
    ubyte[11] strided;
    strided[] = 0xA5;
    blocks[0] = Block(0,13);
    assert(decodeDeflateBlocks(hello, blocks[0 .. 1], ImageSpec(5,1,1,1,5,1), decoder,
        scratch, strided, Layout(11,2,1)).ok);
    foreach (i; 0 .. 5) assert(strided[i*2] == "hello"[i]);
    foreach (i; [1,3,5,7,9,10]) assert(strided[i] == 0xA5);
}

private ubyte[] stored(scope const(ubyte)[] bytes) @safe
{
    assert(bytes.length < 65536);
    auto n = cast(uint)bytes.length;
    auto data = [cast(ubyte)0x78, cast(ubyte)1, cast(ubyte)1,
        cast(ubyte)n, cast(ubyte)(n>>8), cast(ubyte)~n, cast(ubyte)(~n>>8)] ~ bytes;
    const checksum = adler32(bytes);
    foreach_reverse (uint shift; 0 .. 4) data ~= cast(ubyte)(checksum >> (shift*8));
    return data;
}

@safe unittest
{
    InflateWorkspace decoder;
    ubyte[8] scratch;
    ubyte[6] output;
    const shape = PngShape(1,1,3,8);
    output[] = 0xA5;
    auto encoded = stored([cast(ubyte)0,cast(ubyte)1,cast(ubyte)2,cast(ubyte)3]);
    assert(decodeScanlines(encoded, shape, decoder, scratch, output).status == PngStatus.ok);
    assert(output[0 .. 3] == [1,2,3]);
    foreach (guard; output[3 .. $]) assert(guard == 0xA5);
    output[] = 0xA5;
    assert(decodeScanlines(encoded, shape, decoder, scratch[0 .. 3], output).status == PngStatus.workspaceTooSmall);
    assert(decodeScanlines(encoded, shape, decoder, scratch, output[0 .. 2]).status == PngStatus.destinationTooSmall);
    auto invalid = stored([cast(ubyte)5,cast(ubyte)1,cast(ubyte)2,cast(ubyte)3]);
    assert(decodeScanlines(invalid, shape, decoder, scratch, output).status == PngStatus.invalidFilter);
    foreach (value; output) assert(value == 0xA5);
    encoded[$-1] ^= 1;
    assert(decodeScanlines(encoded, shape, decoder, scratch, output).codec == ErrorCode.checksumMismatch);
    foreach (value; output) assert(value == 0xA5);
    assert(png_scanlines.requirements(PngShape(uint.max,uint.max,4,16)).status == PngStatus.sizeOverflow);
    // Invalid later-row filter must not leak the earlier row into destination.
    invalid = stored([cast(ubyte)0,cast(ubyte)1,cast(ubyte)2,cast(ubyte)3,cast(ubyte)5,cast(ubyte)4,cast(ubyte)5,cast(ubyte)6]);
    assert(decodeScanlines(invalid, PngShape(1,2,3,8), decoder, scratch, output).status == PngStatus.invalidFilter);
    foreach (value; output) assert(value == 0xA5);
}

@safe unittest
{
    ubyte[16] plain;
    foreach (i, ref value; plain) value = cast(ubyte)i;
    const encoded = stored(plain);
    Block[1] blocks = [Block(0, cast(uint)encoded.length)];
    const spec = ImageSpec(3,2,1,1,4,4,true);
    const layout = Layout(3,1,1);
    assert(deflate_bridge.requirements(spec).scratchBytes == 16);
    InflateWorkspace decoder;
    ubyte[16] scratch;
    ubyte[8] output;
    output[] = 0xA5;
    assert(decodeDeflateBlocks(encoded, blocks, spec, decoder, scratch, output, layout).ok);
    assert(output[0 .. 6] == [0,1,2,4,5,6] && output[6] == 0xA5 && output[7] == 0xA5);
    output[] = 0xA5;
    assert(decodeDeflateBlocks(encoded, blocks, spec, decoder, scratch[0 .. 15], output, layout).status == BridgeStatus.workspaceTooSmall);
    foreach (value; output) assert(value == 0xA5);
}

void main(string[] args)
{
    auto barrier = new Barrier(2);
    bool[2] passed;
    Thread[2] workers;
    foreach (uint index; 0 .. 2)
    {
        // Bind the worker index by value rather than capture the loop variable.
        Thread makeWorker(uint worker)
        {
            return new Thread({
                InflateWorkspace decoder;
                ubyte[5] scratch, output;
                Block[1] blocks = [Block(0,13)];
                const spec = ImageSpec(5,1,1,1,5,1);
                barrier.wait();
                const before = GC.allocatedInCurrentThread;
                foreach (round; 0 .. 2000)
                {
                    output[] = 0xFF;
                    if (worker == 0)
                    {
                        assert(decodeDeflateBlocks(hello, blocks, spec, decoder, scratch, output, Layout(5,1,1)).ok);
                        assert(output == "hello");
                    }
                    else
                    {
                        assert(decodeScanlines(pngPixel, PngShape(1,1,3,8), decoder, scratch, output).status == PngStatus.ok);
                        assert(output[0 .. 3] == [1,2,3]);
                    }
                }
                assert(GC.allocatedInCurrentThread == before);
                passed[worker] = true;
            });
        }
        workers[index] = makeWorker(index);
        workers[index].start();
    }
    foreach (worker; workers) worker.join();
    assert(passed[0] && passed[1]);
    if (args.length > 1)
    {
        auto file = cast(ubyte[])read(buildPath(args[1], "tiff-1-16-3-p2-1.tif"));
        TiffInfo info;
        foreach (cut; 0 .. 8) assert(inspectTiff(file[0 .. cut], info) == BridgeStatus.truncated);
        auto original = file.dup;
        file[0] = 0;
        assert(inspectTiff(file, info) == BridgeStatus.invalidMetadata);
        file[] = original[];
        file[2] = 0; file[3] = 43;
        assert(inspectTiff(file, info) == BridgeStatus.unsupported);
        // Mutated bounded metadata must return a status, never a bounds failure.
        uint seed = 4;
        foreach (trial; 0 .. 500)
        {
            file[] = original[];
            seed = seed * 1664525 + 1013904223;
            const offset = (seed >> 16) % (file.length < 512 ? file.length : 512);
            file[offset] ^= cast(ubyte)(1U << (seed % 8));
            const status = inspectTiff(file, info);
            if (status == BridgeStatus.ok && info.offsets.count < 1024)
            {
                auto blocks = new Block[info.offsets.count];
                readBlocks(file, info, blocks);
            }
        }
    }
    writeln("consumer negative/attribute tests and two-thread isolation passed");
}

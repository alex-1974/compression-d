// Reproducible JPEG ROI benchmark. Build with:
// dub build --config=unittest --compiler=ldc2
// and compile this module against source/ as a standalone D program.
module jpeg_roi_benchmark;

import compression.jpeg;
import core.time : MonoTime;
import std.stdio : writefln;

void main()
{
    enum w = 256, h = 256, passes = 20;
    ubyte[w * h] pixels;
    foreach (i, ref p; pixels) p = cast(ubyte)((i * 17 + i / w * 3) & 255);
    foreach (restart; [1U, 4U, 16U])
    foreach (region; [PixelRegion(0, 0, 32, 32),
                      PixelRegion(112, 112, 32, 32),
                      PixelRegion(224, 224, 32, 32)])
    {
        ConstPlane[1] source = [ConstPlane(pixels[], w)];
        ubyte[1_000_000] encoded;
        EncodeOptions options;
        options.restartInterval = cast(ushort)(restart);
        const encodedResult = encodeJfifPlanes(Info(w, h, 1), source[], encoded[], options);
        assert(encodedResult.ok);
        const input = encoded[0 .. encodedResult.written];
        RestartIndexEntry[4096] entries;
        const index = buildJpegRestartIndex(input, entries[]);
        assert(index.ok);
        ubyte[32 * 32] roiBytes;
        MutablePlane[1] roi = [MutablePlane(roiBytes[], 32)];
        auto report = new RoiDecodeReport;
        auto start = MonoTime.currTime;
        foreach (pass; 0 .. passes)
            assert(decodeJpegPlanesRegion(input, region, roi[], report).ok);
        const fullNs = (MonoTime.currTime - start).total!"nsecs";
        start = MonoTime.currTime;
        foreach (pass; 0 .. passes)
            assert(decodeJpegPlanesRegionIndexed(input, region, roi[], index,
                entries[0 .. index.entries], report).ok);
        const indexedNs = (MonoTime.currTime - start).total!"nsecs";
        writefln("restart=%s roi=(%s,%s) bytes=%s entries=%s requested=%s decoded=%s full_ms=%.3f indexed_ms=%.3f path=%s",
            restart, region.x, region.y, input.length, index.entries,
            report.requestedMcuCount, report.decodedMcuCount,
            fullNs / 1_000_000.0, indexedNs / 1_000_000.0, report.path);
    }
}

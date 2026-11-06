module jpeg_tests;

import compression.jpeg;

@safe unittest
{
    enum w = 32, h = 16;
    ubyte[w * h] pixels;
    foreach (i, ref p; pixels) p = cast(ubyte)((i * 13 + i / w * 7) & 255);
    ConstPlane[1] source = [ConstPlane(pixels[], w)];
    ubyte[65536] encoded;
    EncodeOptions options;
    options.restartInterval = 1;
    auto er = encodeJfifPlanes(Info(w, h, 1), source[], encoded[], options);
    assert(er.ok);
    ubyte[w * h] full;
    MutablePlane[1] fullPlane = [MutablePlane(full[], w)];
    assert(decodeJpegPlanes(encoded[0 .. er.written], fullPlane[]).ok);
    RestartIndexEntry[16] entries;
    auto index = buildJpegRestartIndex(encoded[0 .. er.written], entries[]);
    assert(index.ok && index.entries != 0);
    ubyte[64] roiPixels;
    MutablePlane[1] roiPlane = [MutablePlane(roiPixels[], 8)];
    auto report = new RoiDecodeReport;
    auto dr = decodeJpegPlanesRegion(encoded[0 .. er.written],
        PixelRegion(8, 0, 8, 8), roiPlane[], report);
    assert(dr.ok && report.path == RoiDecodePath.fullDecodeFallback);
    foreach (y; 0 .. 8) foreach (x; 0 .. 8)
        assert(roiPixels[y * 8 + x] == full[y * w + 8 + x]);
    roiPixels[] = 0;
    auto indexed = decodeJpegPlanesRegionIndexed(encoded[0 .. er.written],
        PixelRegion(8, 0, 8, 8), roiPlane[], index,
        entries[0 .. index.entries], report);
    assert(indexed.ok);
    assert(report.path == RoiDecodePath.restartBoundedScan);
    foreach (y; 0 .. 8) foreach (x; 0 .. 8)
        assert(roiPixels[y * 8 + x] == full[y * w + 8 + x]);
    auto badIndex = index;
    badIndex.sourceFingerprint ^= 1;
    assert(decodeJpegPlanesRegionIndexed(encoded[0 .. er.written],
        PixelRegion(8, 0, 8, 8), roiPlane[], badIndex,
        entries[0 .. index.entries], report).status == Status.invalid);
    assert(decodeJpegPlanesRegionIndexed(encoded[0 .. er.written],
        PixelRegion(8, 0, 8, 8), roiPlane[], index,
        entries[0 .. index.entries - 1], report).status == Status.invalid);
}

@safe unittest
{
    enum w = 32, h = 16;
    ubyte[w * h] y;
    ubyte[(w / 2) * (h / 2)] cb;
    ubyte[(w / 2) * (h / 2)] cr;
    foreach (i, ref p; y) p = cast(ubyte)((i * 5) & 255);
    foreach (i, ref p; cb) p = cast(ubyte)(96 + (i & 31));
    foreach (i, ref p; cr) p = cast(ubyte)(160 - (i & 31));
    ConstPlane[3] source = [ConstPlane(y[], w),
        ConstPlane(cb[], w / 2), ConstPlane(cr[], w / 2)];
    ubyte[65536] encoded;
    EncodeOptions options;
    options.sampling = Sampling.s420;
    options.restartInterval = 1;
    auto er = encodeJfifPlanes(Info(w, h, 3), source[], encoded[], options);
    assert(er.ok);
    ubyte[w * h] yd;
    ubyte[(w / 2) * (h / 2)] cbd, crd;
    MutablePlane[3] decoded = [MutablePlane(yd[], w),
        MutablePlane(cbd[], w / 2), MutablePlane(crd[], w / 2)];
    assert(decodeJpegPlanes(encoded[0 .. er.written], decoded[]).ok);
    RestartIndexEntry[32] entries;
    auto index = buildJpegRestartIndex(encoded[0 .. er.written], entries[]);
    assert(index.ok && index.entries != 0);
    auto report = new RoiDecodeReport;
    ubyte[64] roiY;
    ubyte[16] roiCb, roiCr;
    MutablePlane[3] roi = [MutablePlane(roiY[], 8),
        MutablePlane(roiCb[], 4), MutablePlane(roiCr[], 4)];
    auto rr = decodeJpegPlanesRegionIndexed(encoded[0 .. er.written],
        PixelRegion(8, 0, 8, 8), roi[], index,
        entries[0 .. index.entries], report);
    assert(rr.ok);
    foreach (i; 0 .. roiY.length) assert(roiY[i] == yd[(i / 8) * w + 8 + i % 8]);
}

@safe unittest
{
    FrameResult frame;
    frame.status = Status.ok;
    frame.info = Info(101, 67, 3);
    frame.horizontal = [2, 1, 1];
    frame.vertical = [2, 1, 1];
    auto edge = planJpegPlanesRegion(frame, PixelRegion(100, 66, 1, 1));
    assert(edge.ok);
    assert(edge.requestedMcuCount == 1);
    assert(edge.components[0].width == 1);
    assert(edge.components[0].height == 1);
    assert(!planJpegPlanesRegion(frame, PixelRegion(101, 66, 1, 1)).ok);
    assert(!planJpegPlanesRegion(frame, PixelRegion(100, 67, 1, 1)).ok);
}

@safe unittest
{
    FrameResult frame;
    frame.status = Status.ok;
    frame.info = Info(33, 17, 3);
    frame.horizontal = [2, 1, 1];
    frame.vertical = [1, 1, 1];
    auto plan = planJpegPlanesRegion(frame, PixelRegion(16, 8, 9, 8));
    assert(plan.ok);
    assert(plan.components[0].width == 5);
    assert(plan.components[0].height == 8);
    assert(plan.components[1].width == 9);
    assert(plan.components[1].height == 8);
    assert(plan.requestedMcuCount == 1);
}

@safe unittest
{
    // A syntactically valid JPEG without DRI produces an empty, reusable index.
    // The bounded output contract must reject a zero-capacity buffer only when
    // an actual restart marker needs to be recorded.
    auto result = buildJpegRestartIndex(
        cast(const(ubyte)[])[0xff, 0xd8, 0xff, 0xd9],
        cast(RestartIndexEntry[])[]);
    assert(result.status == Status.invalid || result.status == Status.truncated);
}

@safe unittest
{
    FrameResult frame;
    frame.status = Status.ok;
    frame.info = Info(101, 67, 3);
    frame.horizontal = [2, 1, 1];
    frame.vertical = [2, 1, 1];
    auto plan = planJpegPlanesRegion(frame, PixelRegion(17, 9, 1, 1));
    assert(plan.ok);
    assert(plan.requestedMcuCount == 1);
    assert(plan.components[0].originX == 8);
    assert(plan.components[0].originY == 4);
    assert(plan.components[0].width == 1);
    assert(plan.components[0].height == 1);
    assert(plan.components[1].originX == 17);
    assert(plan.components[1].originY == 9);
}

@safe unittest
{
    FrameResult frame;
    frame.status = Status.ok;
    frame.info = Info(10, 10, 1);
    frame.horizontal[0] = 1;
    frame.vertical[0] = 1;
    assert(!planJpegPlanesRegion(frame, PixelRegion(10, 0, 1, 1)).ok);
    assert(!planJpegPlanesRegion(frame, PixelRegion(0, 0, 0, 1)).ok);
}

@safe unittest
{
    auto invalid = decodeJpegPlanes(cast(const(ubyte)[])[0, 1, 2],
        cast(MutablePlane[])[]);
    assert(invalid.status == Status.invalid);
}

@safe unittest
{
    Limits limits;
    limits.maxFileBytes = 2;
    auto result = decodeJpeg(cast(const(ubyte)[])[0xff, 0xd8, 0xff],
        new ubyte[8], 8, limits);
    assert(result.status == Status.limit);
}

@safe unittest
{
    auto truncated = decodeJpeg(cast(const(ubyte)[])[0xff, 0xd8, 0xff, 0xe0],
        new ubyte[8], 8);
    assert(truncated.status == Status.truncated);
}

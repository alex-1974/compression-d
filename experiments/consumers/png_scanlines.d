/// Research-only non-interlaced PNG scanline consumer, not a PNG file parser.
module png_scanlines;
import compression.core : DecodeLimits, ErrorCode, DecodeStatus;
import compression.deflate : InflateWorkspace;
import compression.zlib : inflateZlib;

enum PngStatus { invalidShape, ok, sizeOverflow, workspaceTooSmall, destinationTooSmall, codecError, wrongSize, invalidFilter }
struct PngResult { PngStatus status; ErrorCode codec = ErrorCode.none; }
struct PngShape { uint width, height, channels, depth; }
struct PngRequirements { PngStatus status; size_t filteredBytes, pixelBytes, rowBytes, pixelStride; }

PngRequirements requirements(PngShape s) @safe pure nothrow @nogc
{
    if (!s.width || !s.height || !s.channels || s.channels > 4 || (s.depth != 8 && s.depth != 16))
        return PngRequirements(PngStatus.invalidShape);
    const stride = cast(size_t)s.channels * (s.depth / 8);
    if (s.width > (size_t.max - 1) / stride) return PngRequirements(PngStatus.sizeOverflow);
    const row = s.width * stride;
    if (s.height > size_t.max / (row + 1)) return PngRequirements(PngStatus.sizeOverflow);
    return PngRequirements(PngStatus.ok, (row + 1) * s.height, row * s.height, row, stride);
}

private uint paeth(uint a, uint b, uint c) @safe pure nothrow @nogc
{
    const p = cast(int)a + cast(int)b - cast(int)c;
    const da = p >= cast(int)a ? p - cast(int)a : cast(int)a - p;
    const db = p >= cast(int)b ? p - cast(int)b : cast(int)b - p;
    const dc = p >= cast(int)c ? p - cast(int)c : cast(int)c - p;
    return da <= db && da <= dc ? a : db <= dc ? b : c;
}

PngResult decodeScanlines(scope const(ubyte)[] idat, PngShape shape,
    ref InflateWorkspace decoder, scope ubyte[] scratch, scope ubyte[] output)
    @safe pure nothrow @nogc
{
    const r = requirements(shape);
    if (r.status != PngStatus.ok) return PngResult(r.status);
    if (scratch.length < r.filteredBytes) return PngResult(PngStatus.workspaceTooSmall);
    if (output.length < r.pixelBytes) return PngResult(PngStatus.destinationTooSmall);
    const decoded = inflateZlib(idat, scratch[0 .. r.filteredBytes], decoder, DecodeLimits(r.filteredBytes));
    if (decoded.status != DecodeStatus.done) return PngResult(PngStatus.codecError, decoded.error.code);
    if (decoded.consumed != idat.length || decoded.produced != r.filteredBytes) return PngResult(PngStatus.wrongSize);
    foreach (size_t y; 0 .. shape.height)
        if (scratch[y * (r.rowBytes + 1)] > 4) return PngResult(PngStatus.invalidFilter);
    foreach (size_t y; 0 .. shape.height)
    {
        const start = y * (r.rowBytes + 1);
        const filter = scratch[start];
        foreach (size_t x; 0 .. r.rowBytes)
        {
            const offset = y * r.rowBytes + x;
            const left = x >= r.pixelStride ? output[offset - r.pixelStride] : 0U;
            const up = y ? output[offset - r.rowBytes] : 0U;
            const upperLeft = y && x >= r.pixelStride ? output[offset - r.rowBytes - r.pixelStride] : 0U;
            uint predictor;
            final switch (filter)
            {
            case 0: predictor = 0; break;
            case 1: predictor = left; break;
            case 2: predictor = up; break;
            case 3: predictor = (left + up) / 2; break;
            case 4: predictor = paeth(left, up, upperLeft); break;
            }
            output[offset] = cast(ubyte)(scratch[start + 1 + x] + predictor);
        }
    }
    return PngResult(PngStatus.ok);
}
